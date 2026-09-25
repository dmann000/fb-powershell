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
