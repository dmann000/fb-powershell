#Requires -Version 7.0
<#
.SYNOPSIS
    The pure half of the backlog scorer (tools/Build-PfbBacklog.ps1).
.DESCRIPTION
    Turns open issues, as the REST API returns them, and the current drift findings into
    lanes that say what the next unit of work is, and why. docs/TRIAGE-ROLES.md is the
    vocabulary: the lane follows from the one status: label, and the human priority: label
    is the primary sort key. The score only orders issues inside a priority band.

    Nothing here touches the network or the filesystem. The shell script owns the reads and
    the output, so every rule below is testable against in-memory fixtures
    (Tests/PfbBacklogTools.Tests.ps1).

    READ-ONLY BY DESIGN. A status:triage issue gets a PROPOSED priority and size; no label
    is ever written. Confirming a proposal is a person's call.

    ONE TABLE DRIVES BOTH SORTING AND PROPOSALS: $script:PfbBacklogImpactClass. A finding
    category or a dead-key severity the table does not name throws, so a new one cannot
    land silently in the wrong class.

    PowerShell 7, like the rest of the tooling CI invokes. The syntax stays 5.1-parseable
    because PSUseCompatibleSyntax is held at zero, and the file is pure ASCII because
    PSUseBOMForUnicodeEncodedFile is held at zero.
#>

. (Join-Path $PSScriptRoot 'PfbDriftIssueTools.ps1')

# The seven lanes, in output order: JSON lane order and Markdown section order.
$script:PfbBacklogLane = @('build', 'design', 'triage', 'inFlight', 'parked', 'confirmClose', 'labelErrors')

# Only these are ranked. status:triage is deliberately not: docs/TRIAGE-ROLES.md says it is
# "not a scoring input". Triage issues get a proposal instead.
$script:PfbBacklogRankedLane = @('build', 'design')

# status: value -> lane. Any other status: value is an error (labelErrors).
$script:PfbBacklogStatusLane = @{
    'agent-ready'       = 'build'
    'design-approved'   = 'build'
    'needs-design'      = 'design'
    'triage'            = 'triage'
    'in-progress'       = 'inFlight'
    'needs-review'      = 'inFlight'
    'blocked'           = 'parked'
    'human-only'        = 'parked'
    'resolved-upstream' = 'confirmClose'
}

function Get-PfbBacklogMember {
    <#
    .SYNOPSIS
        A member of a REST record, or $null when the record does not carry it.
    .DESCRIPTION
        Plain member access on a missing property throws under Set-StrictMode, and REST
        rows differ in what they carry: pull_request appears only on pull requests, and
        state_reason may be absent. Every REST member is read through here. An array value
        is returned unrolled, so wrap collection reads in Get-PfbDriftItem.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowNull()]$InputObject,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($null -eq $InputObject) { return $null }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function ConvertFrom-PfbBacklogRestIssue {
    <#
    .SYNOPSIS
        Normalises REST /issues rows: pull requests dropped, each issue's block parsed alone.
    .DESCRIPTION
        GET /repos/{repo}/issues returns pull requests too. A row that carries a
        pull_request member is one, and is dropped.

        ConvertFrom-PfbDriftIssue (tools/lib/PfbDriftIssueTools.ps1) is reused for the trust
        boundary and the block parser, but it reads the gh shape: stateReason where REST has
        state_reason, and no html_url at all. So each row is rebuilt in that shape first.
        That keeps the call safe under Set-StrictMode, where the missing stateReason would
        throw. The github.com link comes from the raw row's html_url; REST `url` is the API
        address and is never shown.

        ONE ISSUE AT A TIME, INSIDE try/catch. The reconciler lets a malformed block on a
        trusted issue stop its run, because it writes. The scorer only reads, so that issue
        comes back with BlockError set (and lands in labelErrors), and the rest are still
        scored. A block on an untrusted issue (no source:drift) is ignored, exactly as the
        reconciler ignores it: Marker is $null and the issue is ranked on its labels alone.
    .OUTPUTS
        [PSCustomObject] Number, Title, Url, Labels, Trusted, Marker, IgnoredBlock, BlockError.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Issue)

    foreach ($raw in @(Get-PfbDriftItem -Value $Issue)) {
        if ($null -ne $raw.PSObject.Properties['pull_request']) { continue }

        $labels = @(@(Get-PfbDriftItem -Value (Get-PfbBacklogMember -InputObject $raw -Name 'labels')) | ForEach-Object {
                if ($_ -is [string]) { $_ }
                else { [string](Get-PfbBacklogMember -InputObject $_ -Name 'name') }
            })
        $ghShaped = [PSCustomObject]@{
            number      = [int](Get-PfbBacklogMember -InputObject $raw -Name 'number')
            title       = [string](Get-PfbBacklogMember -InputObject $raw -Name 'title')
            body        = [string](Get-PfbBacklogMember -InputObject $raw -Name 'body')
            state       = [string](Get-PfbBacklogMember -InputObject $raw -Name 'state')
            stateReason = [string](Get-PfbBacklogMember -InputObject $raw -Name 'state_reason')
            labels      = $labels
        }

        $parsed = $null
        $blockError = $null
        try {
            $parsed = @(ConvertFrom-PfbDriftIssue -Issue @($ghShaped))[0]
        }
        catch {
            $blockError = $_.Exception.Message
        }

        $marker = $null
        $ignoredBlock = $false
        if ($null -ne $parsed) {
            $marker = $parsed.Marker
            $ignoredBlock = [bool]$parsed.IgnoredBlock
        }
        [PSCustomObject]@{
            Number       = $ghShaped.number
            Title        = $ghShaped.title
            Url          = [string](Get-PfbBacklogMember -InputObject $raw -Name 'html_url')
            Labels       = $labels
            Trusted      = ($labels -ccontains $script:PfbDriftLabel.Source)
            Marker       = $marker
            IgnoredBlock = $ignoredBlock
            BlockError   = $blockError
        }
    }
}

$script:PfbBacklogPriority = @('P0', 'P1', 'P2', 'P3')
$script:PfbBacklogSize = @('S', 'M', 'L')

function Get-PfbBacklogLabelSet {
    <#
    .SYNOPSIS
        An issue's labels split by axis: the values after 'status:', 'priority:', and so on.
    .DESCRIPTION
        Prefixes match case-sensitively, the way docs/TRIAGE-ROLES.md spells them. Any other
        label (bug, enhancement, Status:triage) is on no axis and is ignored.
    .OUTPUTS
        [PSCustomObject] Status, Priority, Size, Area, Source (string arrays of values) and
        NeedsLiveTest (bool).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Label)

    $prefix = [ordered]@{ Status = 'status:'; Priority = 'priority:'; Size = 'size:'; Area = 'area:'; Source = 'source:' }
    $values = @{}
    foreach ($axis in $prefix.Keys) { $values[$axis] = [System.Collections.Generic.List[string]]::new() }
    foreach ($text in @($Label)) {
        foreach ($axis in $prefix.Keys) {
            if ($text.StartsWith($prefix[$axis], [System.StringComparison]::Ordinal)) {
                $values[$axis].Add($text.Substring($prefix[$axis].Length))
            }
        }
    }
    [PSCustomObject]@{
        Status        = @($values['Status'])
        Priority      = @($values['Priority'])
        Size          = @($values['Size'])
        Area          = @($values['Area'])
        Source        = @($values['Source'])
        NeedsLiveTest = (@($Label) -ccontains $script:PfbDriftLabel.LiveTest)
    }
}

function Format-PfbBacklogLabelList {
    <#
    .SYNOPSIS
        'prefix:a, prefix:b' for a label problem message, ordinally sorted.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)][string]$Prefix,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Value
    )

    return (@(Get-PfbDriftSortedString -Value $Value | ForEach-Object { $Prefix + $_ }) -join ', ')
}

function Get-PfbBacklogPlacement {
    <#
    .SYNOPSIS
        The lane an issue belongs in, the label values it is scored on, and its label problems.
    .DESCRIPTION
        The lane follows from the single status: label (docs/TRIAGE-ROLES.md). Problems come
        in two tiers.

        ERRORS move the issue to labelErrors, because the scorer cannot place it:
          no status: label, more than one, or an unknown value;
          a build or design issue with no priority:, more than one, or an unknown value
          (the band is the primary sort key);
          a malformed block on a trusted issue.

        WARNINGS leave the issue in its lane and are listed beside it:
          more than one size:, or an unknown value -- treated as missing, so it sorts after L;
          on a triage issue, more than one priority:, or an unknown value -- current is null;
          two source: labels where neither is source:drift, or three or more. The paired
          legacy issue (source:drift beside its origin label) is legal and never warned on.
          It is a warning rather than an error here only because it does not affect placement;
          no area:, or more than one;
          no source:.

        priority: is not checked on inFlight, parked or confirmClose: nothing there is ranked.
    .OUTPUTS
        [PSCustomObject] Lane, Status, Priority, Size, Sources, NeedsLiveTest, Errors, Warnings.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Issue)

    $set = Get-PfbBacklogLabelSet -Label @($Issue.Labels)
    $errors = [System.Collections.Generic.List[string]]::new()
    $warnings = [System.Collections.Generic.List[string]]::new()

    $status = $null
    $lane = $null
    if ($set.Status.Count -eq 0) { $errors.Add('no status: label') }
    elseif ($set.Status.Count -gt 1) { $errors.Add("more than one status: label ($(Format-PfbBacklogLabelList -Prefix 'status:' -Value $set.Status))") }
    else {
        $status = $set.Status[0]
        if (@($script:PfbBacklogStatusLane.Keys) -ccontains $status) { $lane = $script:PfbBacklogStatusLane[$status] }
        else { $errors.Add("unknown status: label (status:$status)") }
    }

    if ($null -ne $Issue.BlockError) { $errors.Add("malformed pfb-drift block: $($Issue.BlockError)") }

    $priority = $null
    if ($set.Priority.Count -eq 1 -and $script:PfbBacklogPriority -ccontains $set.Priority[0]) { $priority = $set.Priority[0] }
    if ($script:PfbBacklogRankedLane -ccontains $lane) {
        if ($set.Priority.Count -eq 0) { $errors.Add('no priority: label on a ranked lane') }
        elseif ($set.Priority.Count -gt 1) { $errors.Add("more than one priority: label ($(Format-PfbBacklogLabelList -Prefix 'priority:' -Value $set.Priority))") }
        elseif ($null -eq $priority) { $errors.Add("unknown priority: label (priority:$($set.Priority[0]))") }
    }
    elseif ($lane -ceq 'triage') {
        if ($set.Priority.Count -gt 1) { $warnings.Add("more than one priority: label ($(Format-PfbBacklogLabelList -Prefix 'priority:' -Value $set.Priority)); treated as missing") }
        elseif ($set.Priority.Count -eq 1 -and $null -eq $priority) { $warnings.Add("unknown priority: label (priority:$($set.Priority[0])); treated as missing") }
    }

    $size = $null
    if ($set.Size.Count -gt 1) { $warnings.Add("more than one size: label ($(Format-PfbBacklogLabelList -Prefix 'size:' -Value $set.Size)); treated as missing") }
    elseif ($set.Size.Count -eq 1) {
        if ($script:PfbBacklogSize -ccontains $set.Size[0]) { $size = $set.Size[0] }
        else { $warnings.Add("unknown size: label (size:$($set.Size[0])); treated as missing") }
    }

    $origin = @($set.Source | Where-Object { $_ -cne 'drift' })
    if ($set.Source.Count -eq 0) { $warnings.Add('no source: label') }
    elseif ($set.Source.Count -ge 3) { $warnings.Add("three or more source: labels ($(Format-PfbBacklogLabelList -Prefix 'source:' -Value $set.Source))") }
    elseif ($set.Source.Count -eq 2 -and $origin.Count -eq 2) { $warnings.Add("two source: labels and neither is source:drift ($(Format-PfbBacklogLabelList -Prefix 'source:' -Value $set.Source))") }

    if ($set.Area.Count -eq 0) { $warnings.Add('no area: label') }
    elseif ($set.Area.Count -gt 1) { $warnings.Add("more than one area: label ($(Format-PfbBacklogLabelList -Prefix 'area:' -Value $set.Area))") }

    if ($errors.Count -gt 0) { $lane = 'labelErrors' }

    [PSCustomObject]@{
        Lane          = $lane
        Status        = $status
        Priority      = $priority
        Size          = $size
        Sources       = @(Get-PfbDriftSortedString -Value @($set.Source))
        NeedsLiveTest = $set.NeedsLiveTest
        Errors        = @($errors)
        Warnings      = @($warnings)
    }
}
