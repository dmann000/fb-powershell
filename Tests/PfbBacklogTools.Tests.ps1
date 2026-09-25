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
        { ConvertFrom-PfbDriftIssue -Issue @($raw) } | Should -Throw
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
