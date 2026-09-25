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

# THE IMPACT TABLE. It drives the in-band sort (Rank) and the triage proposal (Priority,
# Reason). The letters follow docs/TRIAGE-ROLES.md's meanings for priority:.
#   A  dead key, ReportSeverity DESTRUCTIVE or CREATE         can damage an array         P0
#   B  dead key, WRONG-RESULTS; no surviving selector         wrong on the wire           P1
#   C  response field removed or renamed; ValidateSet drift   breaks callers or rejects   P1
#                                                             legal values
#   D  uncovered endpoint; unread envelope field; param gap   net-new coverage            P2
#   E  new ValidateSet candidate                              ergonomic                   P3
#   -  no trusted block, or no live finding                   needs a person              none
$script:PfbBacklogImpactClass = [ordered]@{
    'A' = @{ Rank = 1; Priority = 'P0'; Reason = 'can damage an array' }
    'B' = @{ Rank = 2; Priority = 'P1'; Reason = 'wrong on the wire' }
    'C' = @{ Rank = 3; Priority = 'P1'; Reason = 'breaks callers or rejects legal values' }
    'D' = @{ Rank = 4; Priority = 'P2'; Reason = 'net-new coverage' }
    'E' = @{ Rank = 5; Priority = 'P3'; Reason = 'ergonomic' }
    '-' = @{ Rank = 6; Priority = $null; Reason = 'needs a person' }
}

# Every drift category except deadKey, which is classed by severity below. A category not
# named here throws in Get-PfbBacklogFindingClass.
$script:PfbBacklogCategoryClass = @{
    'noSurvivingSelector'     = 'B'
    'responseFieldRemoval'    = 'C'
    'responseFieldRename'     = 'C'
    'validateSetDrift'        = 'C'
    'uncoveredEndpoint'       = 'D'
    'unhandledEnvelopeField'  = 'D'
    'parameterGap'            = 'D'
    'newValidateSetCandidate' = 'E'
}

# The only three ReportSeverity values tools/Build-PfbDeadKeyReport.ps1 emits
# (Get-PfbDeadKeySeverity). Any other, including a case variant, throws.
$script:PfbBacklogDeadKeySeverityClass = @{
    'DESTRUCTIVE'   = 'A'
    'CREATE'        = 'A'
    'WRONG-RESULTS' = 'B'
}

# A proposal is S at or below this many live findings, else M. It is never L: L means
# "needs a plan" (docs/TRIAGE-ROLES.md), which is a judgement, not a count.
$script:PfbBacklogSmallFindingLimit = 10

# The note on a trusted issue none of whose findings is still reported (used in Get-PfbBacklog).
$script:PfbBacklogResolvedNote = 'No finding this issue tracks is still reported; the next reconciler run will label it status:resolved-upstream.'

function Get-PfbBacklogFindingClass {
    <#
    .SYNOPSIS
        The impact class of one drift finding. Throws on a category or severity the table does not name.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory = $true)]$Finding)

    $category = [string]$Finding.Category
    if ($category -ceq 'deadKey') {
        $severity = [string]$Finding.Detail.ReportSeverity
        if (@($script:PfbBacklogDeadKeySeverityClass.Keys) -cnotcontains $severity) {
            throw "Dead key $($Finding.Fingerprint) ($($Finding.Endpoint) $($Finding.Field)) has ReportSeverity '$severity'. The impact table knows only DESTRUCTIVE, CREATE and WRONG-RESULTS, the values tools/Build-PfbDeadKeyReport.ps1 emits; add the new one to `$script:PfbBacklogDeadKeySeverityClass deliberately rather than let it land in a guessed class."
        }
        return $script:PfbBacklogDeadKeySeverityClass[$severity]
    }
    if (@($script:PfbBacklogCategoryClass.Keys) -cnotcontains $category) {
        throw "Finding $($Finding.Fingerprint) has category '$category', which the impact table does not classify. Add it to `$script:PfbBacklogCategoryClass deliberately rather than let it land in a guessed class."
    }
    return $script:PfbBacklogCategoryClass[$category]
}

function Get-PfbBacklogImpact {
    <#
    .SYNOPSIS
        An issue's impact class and finding counts, from its trusted block and the live findings.
    .DESCRIPTION
        An issue's LIVE findings are its trusted block's Fingerprints that match a finding in
        the current reports. Its impact class is the worst (lowest-ranked) class among them,
        or '-' when it has no trusted block or no live finding.

        TrackedFindings is Marker.Fingerprints.Count. Fingerprints and Vanished are disjoint
        (Assert-PfbDriftMarker), so vanished ones are not counted. TrackedFindings minus
        LiveFindings is how a fingerprint the reports no longer contain shows up; it is not
        an error.

        Families are the distinct Finding.Family values of the live findings, ordinally
        sorted. A finding with no endpoint has family '' (Get-PfbDriftFamily), which means
        "no family" and is left out.
    .OUTPUTS
        [PSCustomObject] ImpactClass, LiveFindings, TrackedFindings, Families.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]$Marker,
        [Parameter(Mandatory = $true)]$FindingIndex
    )

    if ($null -eq $Marker) {
        return [PSCustomObject]@{ ImpactClass = '-'; LiveFindings = 0; TrackedFindings = 0; Families = @() }
    }

    $tracked = @(Get-PfbDriftItem -Value $Marker.Fingerprints)
    $live = @(foreach ($fingerprint in $tracked) {
            if ($FindingIndex.ContainsKey([string]$fingerprint)) { $FindingIndex[[string]$fingerprint] }
        })

    $class = '-'
    $best = [int]$script:PfbBacklogImpactClass['-'].Rank
    foreach ($finding in $live) {
        $candidate = Get-PfbBacklogFindingClass -Finding $finding
        $rank = [int]$script:PfbBacklogImpactClass[$candidate].Rank
        if ($rank -lt $best) {
            $best = $rank
            $class = $candidate
        }
    }

    $families = @(Get-PfbDriftSortedString -Value @($live | ForEach-Object { [string]$_.Family } | Where-Object { $_ -ne '' }))
    [PSCustomObject]@{
        ImpactClass     = $class
        LiveFindings    = $live.Count
        TrackedFindings = $tracked.Count
        Families        = $families
    }
}

function Get-PfbBacklogProposal {
    <#
    .SYNOPSIS
        The proposed priority and size for a status:triage issue, beside its current labels.
    .DESCRIPTION
        Priority comes from the impact table. Size is S at or below
        $script:PfbBacklogSmallFindingLimit live findings, else M, and never L. Class '-'
        proposes nothing (priority and size null, reason 'needs a person').

        differs is true when a proposal exists and its priority or size disagrees with the
        current label, so confirming a batch comes down to reading the rows where differs is
        true. With no proposal there is nothing to disagree with, so differs is false; the
        reason still says a person is needed.
    .OUTPUTS
        [PSCustomObject] priority, size, reason, differs, current { priority, size }.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ImpactClass,
        [Parameter(Mandatory = $true)][int]$LiveFindings,
        [AllowNull()]$CurrentPriority = $null,
        [AllowNull()]$CurrentSize = $null
    )

    if (@($script:PfbBacklogImpactClass.Keys) -cnotcontains $ImpactClass) {
        throw "'$ImpactClass' is not an impact class ($(@($script:PfbBacklogImpactClass.Keys) -join ', '))."
    }
    $entry = $script:PfbBacklogImpactClass[$ImpactClass]
    $priority = $entry.Priority
    $size = $null
    if ($null -ne $priority) {
        $size = 'M'
        if ($LiveFindings -le $script:PfbBacklogSmallFindingLimit) { $size = 'S' }
    }
    $differs = ($null -ne $priority) -and (($priority -cne $CurrentPriority) -or ($size -cne $CurrentSize))

    [PSCustomObject]@{
        priority = $priority
        size     = $size
        reason   = $entry.Reason
        differs  = [bool]$differs
        current  = [PSCustomObject]@{ priority = $CurrentPriority; size = $CurrentSize }
    }
}

# Build lane only: an issue with a brief is ready before one whose approach is merely decided.
$script:PfbBacklogReadiness = @{ 'agent-ready' = 0; 'design-approved' = 1 }

# The in-band sort keys, in the order they apply; decidedBy reports one of these names.
$script:PfbBacklogSortKeyName = @('priority', 'readiness', 'impact', 'size', 'liveFindings', 'number')

function Get-PfbBacklogSortKey {
    <#
    .SYNOPSIS
        A ranked row's six sort keys as integers, each compared ascending, in the order they apply.
    .DESCRIPTION
        1 priority band, P0 to P3. 2 readiness (build lane only: agent-ready before
        design-approved; always 0 in design). 3 impact class, A to E, then '-'. 4 size S, M,
        L, then missing. 5 live finding count, negated so that more sorts first. 6 issue
        number. No weights: a later key only orders rows the earlier keys tie.
    .OUTPUTS
        [int] six values; wrap the call in @().
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory = $true)]$Row,
        [Parameter(Mandatory = $true)][ValidateSet('build', 'design')][string]$Lane
    )

    $priority = [array]::IndexOf($script:PfbBacklogPriority, [string]$Row.priority)
    if ($priority -lt 0) {
        throw "Issue #$($Row.number) has no single known priority: label, so it cannot be ranked. Get-PfbBacklogPlacement sends such an issue to labelErrors; ranking it means a caller skipped placement."
    }
    $readiness = 0
    if ($Lane -ceq 'build') {
        if (@($script:PfbBacklogReadiness.Keys) -cnotcontains [string]$Row.status) {
            throw "Issue #$($Row.number) has status '$($Row.status)', which is not a build-lane status."
        }
        $readiness = [int]$script:PfbBacklogReadiness[[string]$Row.status]
    }
    $size = [array]::IndexOf($script:PfbBacklogSize, [string]$Row.size)
    if ($size -lt 0) { $size = $script:PfbBacklogSize.Count }
    $impact = [int]$script:PfbBacklogImpactClass[[string]$Row.impactClass].Rank

    $priority
    $readiness
    $impact
    $size
    (-1 * [int]$Row.liveFindings)
    [int]$Row.number
}

function Get-PfbBacklogRankedRow {
    <#
    .SYNOPSIS
        Sorts a ranked lane, and sets each row's rank and decidedBy.
    .DESCRIPTION
        decidedBy is the name of the first sort key whose value differs from the row directly
        above; it is null on rank 1. Issue numbers are unique, so every row after the first
        is decided by some key. The order is fully deterministic.

        Sets rank and decidedBy on the rows it is given, and emits them in rank order.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Row,
        [Parameter(Mandatory = $true)][ValidateSet('build', 'design')][string]$Lane
    )

    $keyed = @(foreach ($item in @(Get-PfbDriftItem -Value $Row)) {
            [PSCustomObject]@{ Row = $item; Key = @(Get-PfbBacklogSortKey -Row $item -Lane $Lane) }
        })
    $sorted = @($keyed | Sort-Object -Property @{ Expression = { $_.Key[0] } }, @{ Expression = { $_.Key[1] } },
        @{ Expression = { $_.Key[2] } }, @{ Expression = { $_.Key[3] } }, @{ Expression = { $_.Key[4] } },
        @{ Expression = { $_.Key[5] } })

    $previous = $null
    $rank = 0
    foreach ($entry in $sorted) {
        $rank++
        $entry.Row.rank = $rank
        $entry.Row.decidedBy = $null
        if ($null -ne $previous) {
            for ($k = 0; $k -lt $script:PfbBacklogSortKeyName.Count; $k++) {
                if ($entry.Key[$k] -ne $previous.Key[$k]) {
                    $entry.Row.decidedBy = $script:PfbBacklogSortKeyName[$k]
                    break
                }
            }
        }
        $previous = $entry
        $entry.Row
    }
}
