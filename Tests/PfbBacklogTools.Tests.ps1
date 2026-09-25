#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    The pure half of the backlog scorer (tools/lib/PfbBacklogTools.ps1), against fixtures.
.DESCRIPTION
    Every rule the scorer applies runs here against small synthetic fixtures: REST
    normalisation, lanes and label problems, the impact table and triage proposals, the
    in-band sort and decidedBy, and the JSON and Markdown shapes. The #163-#172 calibration
    fixture holds each issue's hand labels and its category/severity mix, not its body; the
    live issues have since moved out of status:triage, so this is a fixture, not a live
    check.

    Issue bodies arrive from GitHub with CRLF as well as LF, so every body-bearing Describe
    runs once per line ending (-ForEach $script:lineEndings).

    EDITION-GATED, BUT NOT WITH #Requires: the library is #Requires -Version 7.0, so every
    Describe carries -Skip:($PSVersionTable.PSVersion.Major -lt 7) and the file-level
    BeforeAll guards its dot-source. The 5.1 skip count is pinned in
    Tests/coverage-baseline.psd1. -ForEach data lives in BeforeDiscovery, because it must
    exist before the library is loaded.
#>

BeforeDiscovery {
    $script:lineEndings = @(
        @{ Eol = 'LF'; NewLine = "`n" }
        @{ Eol = 'CRLF'; NewLine = "`r`n" }
    )
}

BeforeAll {
    $script:isPwsh7 = $PSVersionTable.PSVersion.Major -ge 7
    $script:repoRoot = Split-Path -Parent $PSScriptRoot

    if ($script:isPwsh7) {
        . (Join-Path (Join-Path (Join-Path $script:repoRoot 'tools') 'lib') 'PfbBacklogTools.ps1')
    }

    # A REST /issues row, round-tripped through JSON so it has exactly the shape
    # Invoke-RestMethod gives: PSCustomObject members, labels as objects carrying a name,
    # state_reason (not stateReason), and both html_url and the API url.
    function Build-TestRestIssue {
        param(
            [int]$Number,
            [string[]]$Label = @(),
            [AllowNull()][string[]]$Fingerprint = $null,
            [string]$NewLine = "`n",
            [string]$Title,
            [string]$Body,
            [switch]$NullBody,
            [switch]$PullRequest
        )
        if (-not $PSBoundParameters.ContainsKey('Title')) { $Title = "Issue $Number" }
        if (-not $PSBoundParameters.ContainsKey('Body')) {
            $Body = "Human text.$NewLine"
            if ($null -ne $Fingerprint) {
                $marker = [PSCustomObject]@{ Kind = 'group'; GroupKey = 'deadkey:widgets'; Fingerprints = @($Fingerprint); Vanished = @() }
                $Body = "Human text.$NewLine$NewLine" + (Format-PfbDriftMarker -Marker $marker -NewLine $NewLine)
            }
        }
        $row = [ordered]@{
            url          = "https://api.github.com/repos/example/repo/issues/$Number"
            html_url     = "https://github.com/example/repo/issues/$Number"
            number       = $Number
            title        = $Title
            labels       = @($Label | ForEach-Object { [ordered]@{ name = $_; color = 'ededed' } })
            state        = 'open'
            state_reason = $null
            body         = $Body
        }
        if ($NullBody) { $row['body'] = $null }
        if ($PullRequest) { $row['pull_request'] = [ordered]@{ url = "https://api.github.com/repos/example/repo/pulls/$Number" } }
        return ($row | ConvertTo-Json -Depth 5 | ConvertFrom-Json)
    }

    # Placement reads only Labels and BlockError, so a two-member object is a complete fixture.
    function Get-TestPlacement {
        param([string[]]$Label = @(), [string]$BlockError)
        $issue = [PSCustomObject]@{ Number = 1; Labels = @($Label); BlockError = $null }
        if ($BlockError) { $issue.BlockError = $BlockError }
        Get-PfbBacklogPlacement -Issue $issue
    }
}

Describe 'ConvertFrom-PfbBacklogRestIssue (<Eol>)' -ForEach $script:lineEndings -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
    It 'drops pull requests, which the /issues endpoint returns too' {
        $rows = @(ConvertFrom-PfbBacklogRestIssue -Issue @(
                (Build-TestRestIssue -Number 1 -Label @('status:triage') -NewLine $NewLine)
                (Build-TestRestIssue -Number 2 -Label @('status:triage') -NewLine $NewLine -PullRequest)
            ))
        @($rows | ForEach-Object { $_.Number }) -join ',' | Should -BeExactly '1'
    }

    It 'control: the raw REST row would throw inside ConvertFrom-PfbDriftIssue under StrictMode' {
        Set-StrictMode -Version Latest
        $raw = Build-TestRestIssue -Number 3 -Label @('source:drift') -Fingerprint @('0123456789abcdef') -NewLine $NewLine
        { ConvertFrom-PfbDriftIssue -Issue @($raw) } | Should -Throw -ExpectedMessage '*stateReason*'
    }

    It 'normalises a REST row carrying state_reason and html_url under Set-StrictMode -Version Latest' {
        Set-StrictMode -Version Latest
        $raw = Build-TestRestIssue -Number 3 -Label @('status:triage', 'source:drift') -Fingerprint @('0123456789abcdef') -NewLine $NewLine
        $row = @(ConvertFrom-PfbBacklogRestIssue -Issue @($raw))[0]
        $row.Number | Should -Be 3
        $row.Trusted | Should -BeTrue
        $row.BlockError | Should -BeNullOrEmpty
        @($row.Marker.Fingerprints) -join ',' | Should -BeExactly '0123456789abcdef'
    }

    It 'links to github.com through html_url, never to the API url' {
        $row = @(ConvertFrom-PfbBacklogRestIssue -Issue @((Build-TestRestIssue -Number 4 -NewLine $NewLine)))[0]
        $row.Url | Should -BeExactly 'https://github.com/example/repo/issues/4'
    }

    It 'ignores a block on an untrusted issue, exactly as the reconciler does' {
        $raw = Build-TestRestIssue -Number 5 -Label @('status:needs-design', 'source:human') -Fingerprint @('0123456789abcdef') -NewLine $NewLine
        $row = @(ConvertFrom-PfbBacklogRestIssue -Issue @($raw))[0]
        $row.Trusted | Should -BeFalse
        $row.Marker | Should -BeNullOrEmpty
        $row.IgnoredBlock | Should -BeTrue
        $row.BlockError | Should -BeNullOrEmpty
    }

    It 'reports a malformed block on a trusted issue as BlockError, and keeps normalising the rest' {
        $bad = "Human text.$NewLine$NewLine<!-- pfb-drift-block:start -->$NewLine<!-- pfb-drift-group: family:widgets -->$NewLine"
        $rows = @(ConvertFrom-PfbBacklogRestIssue -Issue @(
                (Build-TestRestIssue -Number 7 -Label @('status:agent-ready', 'source:drift') -Body $bad)
                (Build-TestRestIssue -Number 8 -Label @('status:triage') -NewLine $NewLine)
            ))
        $rows.Count | Should -Be 2
        $rows[0].BlockError | Should -BeLike 'Issue #7: Expected exactly one pfb-drift block*'
        $rows[0].Marker | Should -BeNullOrEmpty
        $rows[1].BlockError | Should -BeNullOrEmpty
    }

    It 'ignores a malformed block on an untrusted issue, so a public user cannot force labelErrors' {
        $bad = "Human text.$NewLine$NewLine<!-- pfb-drift-block:start -->$NewLine<!-- pfb-drift-group: family:widgets -->$NewLine"
        $row = @(ConvertFrom-PfbBacklogRestIssue -Issue @(
                (Build-TestRestIssue -Number 10 -Label @('status:triage', 'source:human') -Body $bad)
            ))[0]
        $row.BlockError | Should -BeNullOrEmpty
        $row.Marker | Should -BeNullOrEmpty
        $row.IgnoredBlock | Should -BeTrue
        $row.Trusted | Should -BeFalse
    }

    It 'normalises an issue with a null body and no labels' {
        $row = @(ConvertFrom-PfbBacklogRestIssue -Issue @((Build-TestRestIssue -Number 9 -NullBody)))[0]
        $row.Number | Should -Be 9
        @($row.Labels).Count | Should -Be 0
        $row.Trusted | Should -BeFalse
        $row.Marker | Should -BeNullOrEmpty
        $row.BlockError | Should -BeNullOrEmpty
    }

    It 'returns nothing for no issues' {
        @(ConvertFrom-PfbBacklogRestIssue -Issue @()).Count | Should -Be 0
    }
}

Describe 'Get-PfbBacklogPlacement' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
    It 'maps status:<Status> to the <Lane> lane' -ForEach @(
        @{ Status = 'agent-ready'; Lane = 'build' }
        @{ Status = 'design-approved'; Lane = 'build' }
        @{ Status = 'needs-design'; Lane = 'design' }
        @{ Status = 'triage'; Lane = 'triage' }
        @{ Status = 'in-progress'; Lane = 'inFlight' }
        @{ Status = 'needs-review'; Lane = 'inFlight' }
        @{ Status = 'blocked'; Lane = 'parked' }
        @{ Status = 'human-only'; Lane = 'parked' }
        @{ Status = 'resolved-upstream'; Lane = 'confirmClose' }
    ) {
        $placement = Get-TestPlacement -Label @("status:$Status", 'priority:P1', 'size:S', 'area:ci', 'source:human')
        $placement.Lane | Should -BeExactly $Lane
        $placement.Status | Should -BeExactly $Status
        @($placement.Errors).Count | Should -Be 0
        @($placement.Warnings).Count | Should -Be 0
    }

    It 'sends <Name> to labelErrors' -ForEach @(
        @{ Name = 'no status: label'; Label = @('priority:P1', 'size:S', 'area:ci', 'source:human'); Expected = 'no status: label' }
        @{ Name = 'two status: labels'; Label = @('status:triage', 'status:blocked', 'priority:P1', 'size:S', 'area:ci', 'source:human'); Expected = 'more than one status: label (status:blocked, status:triage)' }
        @{ Name = 'an unknown status:'; Label = @('status:wontfix', 'priority:P1', 'size:S', 'area:ci', 'source:human'); Expected = 'unknown status: label (status:wontfix)' }
        @{ Name = 'a build issue with no priority:'; Label = @('status:agent-ready', 'size:S', 'area:ci', 'source:human'); Expected = 'no priority: label on a ranked lane' }
        @{ Name = 'a design issue with two priority: labels'; Label = @('status:needs-design', 'priority:P0', 'priority:P1', 'size:S', 'area:ci', 'source:human'); Expected = 'more than one priority: label (priority:P0, priority:P1)' }
        @{ Name = 'a design issue with an unknown priority:'; Label = @('status:needs-design', 'priority:P9', 'size:S', 'area:ci', 'source:human'); Expected = 'unknown priority: label (priority:P9)' }
    ) {
        $placement = Get-TestPlacement -Label $Label
        $placement.Lane | Should -BeExactly 'labelErrors'
        @($placement.Errors) -join ' / ' | Should -BeExactly $Expected
        @($placement.Warnings).Count | Should -Be 0
    }

    It 'sends a trusted issue with a malformed block to labelErrors, with the parser message' {
        $placement = Get-TestPlacement -Label @('status:agent-ready', 'priority:P1', 'size:S', 'area:wire-contract', 'source:drift') -BlockError 'Issue #7: boom'
        $placement.Lane | Should -BeExactly 'labelErrors'
        @($placement.Errors) -join ' / ' | Should -BeExactly 'malformed pfb-drift block: Issue #7: boom'
    }

    It 'keeps <Name> in the <Lane> lane with a warning' -ForEach @(
        @{ Name = 'two size: labels'; Lane = 'build'; Label = @('status:agent-ready', 'priority:P1', 'size:S', 'size:M', 'area:wire-contract', 'source:drift'); Expected = 'more than one size: label (size:M, size:S); treated as missing' }
        @{ Name = 'an unknown size:'; Lane = 'build'; Label = @('status:agent-ready', 'priority:P1', 'size:XL', 'area:wire-contract', 'source:drift'); Expected = 'unknown size: label (size:XL); treated as missing' }
        @{ Name = 'a triage issue with two priority: labels'; Lane = 'triage'; Label = @('status:triage', 'priority:P1', 'priority:P2', 'size:S', 'area:wire-contract', 'source:drift'); Expected = 'more than one priority: label (priority:P1, priority:P2); treated as missing' }
        @{ Name = 'a triage issue with an unknown priority:'; Lane = 'triage'; Label = @('status:triage', 'priority:urgent', 'size:S', 'area:ci', 'source:human'); Expected = 'unknown priority: label (priority:urgent); treated as missing' }
        @{ Name = 'two origin source: labels'; Lane = 'design'; Label = @('status:needs-design', 'priority:P2', 'size:M', 'area:fusion', 'source:human', 'source:livetest'); Expected = 'two source: labels and neither is source:drift (source:human, source:livetest)' }
        @{ Name = 'three source: labels'; Lane = 'parked'; Label = @('status:blocked', 'priority:P1', 'size:S', 'area:ci', 'source:drift', 'source:human', 'source:livetest'); Expected = 'three or more source: labels (source:drift, source:human, source:livetest)' }
        @{ Name = 'no area: label'; Lane = 'inFlight'; Label = @('status:in-progress', 'priority:P1', 'size:S', 'source:human'); Expected = 'no area: label' }
        @{ Name = 'two area: labels'; Lane = 'build'; Label = @('status:agent-ready', 'priority:P0', 'size:S', 'area:ci', 'area:fusion', 'source:drift'); Expected = 'more than one area: label (area:ci, area:fusion)' }
        @{ Name = 'no source: label'; Lane = 'confirmClose'; Label = @('status:resolved-upstream', 'priority:P2', 'size:S', 'area:wire-contract'); Expected = 'no source: label' }
    ) {
        $placement = Get-TestPlacement -Label $Label
        $placement.Lane | Should -BeExactly $Lane
        @($placement.Errors).Count | Should -Be 0
        @($placement.Warnings) -join ' / ' | Should -BeExactly $Expected
    }

    It 'accepts source:drift beside the origin label without a warning (the paired legacy exception)' {
        $placement = Get-TestPlacement -Label @('status:triage', 'priority:P2', 'size:M', 'area:cmdlet-coverage', 'source:drift', 'source:human')
        @($placement.Warnings).Count | Should -Be 0
        @($placement.Sources) -join ',' | Should -BeExactly 'drift,human'
    }

    It 'does not check priority: on an unranked lane' {
        $placement = Get-TestPlacement -Label @('status:blocked', 'priority:P0', 'priority:P1', 'size:S', 'area:ci', 'source:human')
        $placement.Lane | Should -BeExactly 'parked'
        @($placement.Errors).Count | Should -Be 0
        @($placement.Warnings).Count | Should -Be 0
        $placement.Priority | Should -BeNullOrEmpty
    }

    It 'reports the values a clean build issue is scored on' {
        $placement = Get-TestPlacement -Label @('status:agent-ready', 'priority:P1', 'size:S', 'area:wire-contract', 'source:drift', 'needs:live-test')
        $placement.Lane | Should -BeExactly 'build'
        $placement.Priority | Should -BeExactly 'P1'
        $placement.Size | Should -BeExactly 'S'
        $placement.NeedsLiveTest | Should -BeTrue
        @($placement.Errors).Count + @($placement.Warnings).Count | Should -Be 0
    }

    It 'ignores labels on no axis, and a prefix in the wrong case is not a status' {
        $placement = Get-TestPlacement -Label @('bug', 'Status:triage', 'priority:P1', 'size:S', 'area:ci', 'source:human')
        $placement.Lane | Should -BeExactly 'labelErrors'
        @($placement.Errors) -join ' / ' | Should -BeExactly 'no status: label'
        @($placement.Warnings).Count | Should -Be 0
    }

    It 'an issue with no labels at all lands in labelErrors, with its warnings' {
        $placement = Get-TestPlacement -Label @()
        $placement.Lane | Should -BeExactly 'labelErrors'
        @($placement.Errors) -join ' / ' | Should -BeExactly 'no status: label'
        @($placement.Warnings) -join ' / ' | Should -BeExactly 'no source: label / no area: label'
        $placement.NeedsLiveTest | Should -BeFalse
    }
}
