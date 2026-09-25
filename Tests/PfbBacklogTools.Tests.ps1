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

    # The hand triage of #163-#172 (2026-09-25): each issue's hand labels and the mix of its
    # live findings, keyed by dead-key ReportSeverity (or 'noSurvivingSelector').
    $script:calibrationCases = @(
        @{ Number = 163; Priority = 'P1'; Size = 'M'; Mix = @{ 'WRONG-RESULTS' = 21 } }
        @{ Number = 164; Priority = 'P0'; Size = 'M'; Mix = @{ 'DESTRUCTIVE' = 1; 'WRONG-RESULTS' = 13; 'noSurvivingSelector' = 1 } }
        @{ Number = 165; Priority = 'P0'; Size = 'S'; Mix = @{ 'DESTRUCTIVE' = 2; 'WRONG-RESULTS' = 4; 'noSurvivingSelector' = 2 } }
        @{ Number = 166; Priority = 'P1'; Size = 'S'; Mix = @{ 'WRONG-RESULTS' = 6; 'noSurvivingSelector' = 1 } }
        @{ Number = 167; Priority = 'P1'; Size = 'S'; Mix = @{ 'WRONG-RESULTS' = 5; 'noSurvivingSelector' = 1 } }
        @{ Number = 168; Priority = 'P0'; Size = 'S'; Mix = @{ 'CREATE' = 1; 'DESTRUCTIVE' = 1; 'WRONG-RESULTS' = 2 } }
        @{ Number = 169; Priority = 'P1'; Size = 'S'; Mix = @{ 'WRONG-RESULTS' = 4 } }
        @{ Number = 170; Priority = 'P1'; Size = 'S'; Mix = @{ 'WRONG-RESULTS' = 3 } }
        @{ Number = 171; Priority = 'P1'; Size = 'S'; Mix = @{ 'WRONG-RESULTS' = 3 } }
        @{ Number = 172; Priority = 'P1'; Size = 'S'; Mix = @{ 'WRONG-RESULTS' = 3 } }
    )

    $script:assembledCalibration = @(
        @{ Eol = 'LF'; NewLine = "`n"; Cases = $script:calibrationCases }
        @{ Eol = 'CRLF'; NewLine = "`r`n"; Cases = $script:calibrationCases }
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

    # One finding through the drift library's only constructor, so fingerprints and families
    # are computed exactly as Get-PfbDriftFinding computes them.
    function Build-TestFinding {
        param([string]$Category, [string]$Endpoint = '', [string]$Field = '', [string]$Severity = '')
        $detail = @{}
        if ($Category -ceq 'deadKey') {
            $detail = @{ Cmdlets = @('Get-PfbWidget'); Parameters = @('Get-PfbWidget -Name'); ReportSeverity = $Severity; Classification = 'test' }
        }
        return (ConvertTo-PfbDriftFindingRecord -Category $Category -Endpoint $Endpoint -Field $Field -Detail $detail)
    }

    # Fingerprint -> finding. The leading comma matters: a Dictionary is IEnumerable, and
    # returning it bare would unroll it into KeyValuePairs.
    function Build-TestFindingIndex {
        param([object[]]$Finding)
        $index = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
        foreach ($f in @($Finding)) { $index[$f.Fingerprint] = $f }
        return , $index
    }

    function Build-TestMarker {
        param([string[]]$Fingerprint, [string[]]$Vanished = @())
        [PSCustomObject]@{ Kind = 'group'; GroupKey = 'deadkey:widgets'; Fingerprints = @($Fingerprint); Vanished = @($Vanished) }
    }

    # A calibration issue's findings, from its mix: one dead key per severity count, one
    # no-surviving-selector finding per count, all in family cal<Number>.
    function Get-TestCalibrationFinding {
        param([int]$Number, [hashtable]$Mix)
        foreach ($kind in @($Mix.Keys)) {
            for ($i = 1; $i -le [int]$Mix[$kind]; $i++) {
                if ($kind -ceq 'noSurvivingSelector') {
                    Build-TestFinding -Category 'noSurvivingSelector' -Endpoint "GET /cal$Number/nss$i"
                }
                else {
                    Build-TestFinding -Category 'deadKey' -Endpoint "GET /cal$Number" -Field ('{0}-{1}' -f $kind.ToLowerInvariant(), $i) -Severity $kind
                }
            }
        }
    }

    # A ranked-lane row carrying only the members the sort reads (and the two it writes).
    function Build-TestRow {
        param([int]$Number, [string]$Priority, [string]$Status = 'agent-ready', [string]$Impact = 'B', [AllowNull()][string]$Size = 'S', [int]$Live = 1)
        $sizeValue = $null
        if ($Size) { $sizeValue = $Size }
        [PSCustomObject]@{ number = $Number; status = $Status; priority = $Priority; size = $sizeValue; impactClass = $Impact; liveFindings = $Live; rank = $null; decidedBy = $null }
    }

    # The Get-PfbBacklog fixture: at least one issue per lane, plus a pull request, an
    # untrusted block, a malformed trusted block and a trusted issue whose findings are gone.
    function Build-TestBacklogFixture {
        param([string]$NewLine = "`n")
        $a = Build-TestFinding -Category 'deadKey' -Endpoint 'DELETE /widgets' -Field 'names' -Severity 'DESTRUCTIVE'
        $b = Build-TestFinding -Category 'deadKey' -Endpoint 'GET /widgets' -Field 'names' -Severity 'WRONG-RESULTS'
        $d = Build-TestFinding -Category 'uncoveredEndpoint' -Endpoint 'GET /gadgets'
        $malformed = "Human text.$NewLine$NewLine<!-- pfb-drift-block:start -->$NewLine<!-- pfb-drift-group: family:widgets -->$NewLine"
        $issues = @(
            (Build-TestRestIssue -Number 17 -Label @('priority:P2', 'size:S', 'area:ci', 'source:human') -NewLine $NewLine)
            (Build-TestRestIssue -Number 11 -Label @('status:design-approved', 'priority:P0', 'size:S', 'area:wire-contract', 'source:drift') -Fingerprint @($b.Fingerprint) -NewLine $NewLine)
            (Build-TestRestIssue -Number 21 -Label @('status:needs-design', 'priority:P1', 'size:S', 'area:wire-contract', 'source:human') -Fingerprint @($a.Fingerprint) -NewLine $NewLine)
            (Build-TestRestIssue -Number 10 -Label @('status:agent-ready', 'priority:P0', 'size:S', 'area:wire-contract', 'source:drift', 'needs:live-test') -Fingerprint @($a.Fingerprint) -NewLine $NewLine)
            (Build-TestRestIssue -Number 18 -Label @('status:agent-ready', 'priority:P0') -NewLine $NewLine -PullRequest)
            (Build-TestRestIssue -Number 13 -Label @('status:triage', 'area:cmdlet-coverage', 'source:drift') -Fingerprint @($d.Fingerprint) -NewLine $NewLine)
            (Build-TestRestIssue -Number 19 -Label @('status:agent-ready', 'priority:P1', 'size:S', 'area:wire-contract', 'source:drift') -Fingerprint @('00000000000000a2') -NewLine $NewLine)
            (Build-TestRestIssue -Number 12 -Label @('status:needs-design', 'priority:P2', 'size:M', 'area:auth', 'source:human') -NewLine $NewLine)
            (Build-TestRestIssue -Number 14 -Label @('status:in-progress', 'priority:P1', 'size:S', 'area:core-runtime', 'source:human') -NewLine $NewLine)
            (Build-TestRestIssue -Number 20 -Label @('status:agent-ready', 'priority:P1', 'size:S', 'area:wire-contract', 'source:drift') -Body $malformed)
            (Build-TestRestIssue -Number 15 -Label @('status:blocked', 'priority:P1', 'size:S', 'area:fusion', 'source:drift') -NewLine $NewLine)
            (Build-TestRestIssue -Number 16 -Label @('status:resolved-upstream', 'priority:P1', 'size:S', 'area:wire-contract', 'source:drift') -Fingerprint @('00000000000000a1') -NewLine $NewLine)
        )
        @{ Issue = $issues; Finding = @($a, $b, $d) }
    }

    function Get-TestBacklog {
        param([string]$NewLine = "`n")
        $fixture = Build-TestBacklogFixture -NewLine $NewLine
        Get-PfbBacklog -Issue $fixture.Issue -Finding $fixture.Finding -Repo 'example/repo' -SpecVersion '2.28' -GeneratedAt '2026-09-25T18:00:00Z'
    }

    function Get-TestLaneNumber {
        param($Backlog, [string]$Lane)
        @(@(Get-PfbDriftItem -Value $Backlog.lanes.$Lane) | ForEach-Object { $_.number }) -join ','
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
        @{ Name = 'two size: labels'; NullField = 'Size'; Lane = 'build'; Label = @('status:agent-ready', 'priority:P1', 'size:S', 'size:M', 'area:wire-contract', 'source:drift'); Expected = 'more than one size: label (size:M, size:S); treated as missing' }
        @{ Name = 'an unknown size:'; NullField = 'Size'; Lane = 'build'; Label = @('status:agent-ready', 'priority:P1', 'size:XL', 'area:wire-contract', 'source:drift'); Expected = 'unknown size: label (size:XL); treated as missing' }
        @{ Name = 'a triage issue with two priority: labels'; NullField = 'Priority'; Lane = 'triage'; Label = @('status:triage', 'priority:P1', 'priority:P2', 'size:S', 'area:wire-contract', 'source:drift'); Expected = 'more than one priority: label (priority:P1, priority:P2); treated as missing' }
        @{ Name = 'a triage issue with an unknown priority:'; NullField = 'Priority'; Lane = 'triage'; Label = @('status:triage', 'priority:urgent', 'size:S', 'area:ci', 'source:human'); Expected = 'unknown priority: label (priority:urgent); treated as missing' }
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
        if ($NullField) { $placement.$NullField | Should -BeNullOrEmpty }
    }

    It 'lists a malformed block before a missing priority: in Errors' {
        $placement = Get-TestPlacement -Label @('status:agent-ready', 'size:S', 'area:wire-contract', 'source:drift') -BlockError 'Issue #7: boom'
        $placement.Lane | Should -BeExactly 'labelErrors'
        @($placement.Errors).Count | Should -Be 2
        $placement.Errors[0] | Should -BeExactly 'malformed pfb-drift block: Issue #7: boom'
        $placement.Errors[1] | Should -BeExactly 'no priority: label on a ranked lane'
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

Describe 'Get-PfbBacklogFindingClass' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
    It 'classes <Category> <Severity> as <Class>' -ForEach @(
        @{ Category = 'deadKey'; Endpoint = 'DELETE /widgets'; Field = 'names'; Severity = 'DESTRUCTIVE'; Class = 'A' }
        @{ Category = 'deadKey'; Endpoint = 'POST /widgets'; Field = 'names'; Severity = 'CREATE'; Class = 'A' }
        @{ Category = 'deadKey'; Endpoint = 'GET /widgets'; Field = 'names'; Severity = 'WRONG-RESULTS'; Class = 'B' }
        @{ Category = 'noSurvivingSelector'; Endpoint = 'GET /widgets'; Field = ''; Severity = ''; Class = 'B' }
        @{ Category = 'responseFieldRemoval'; Endpoint = 'GET /widgets'; Field = 'items:name'; Severity = ''; Class = 'C' }
        @{ Category = 'responseFieldRename'; Endpoint = 'GET /widgets'; Field = 'items:a->b'; Severity = ''; Class = 'C' }
        @{ Category = 'validateSetDrift'; Endpoint = ''; Field = 'Get-PfbWidget:Type=missing:x'; Severity = ''; Class = 'C' }
        @{ Category = 'uncoveredEndpoint'; Endpoint = 'GET /widgets'; Field = ''; Severity = ''; Class = 'D' }
        @{ Category = 'unhandledEnvelopeField'; Endpoint = ''; Field = 'more_items_remaining'; Severity = ''; Class = 'D' }
        @{ Category = 'parameterGap'; Endpoint = 'PATCH /widgets'; Field = 'query:ids'; Severity = ''; Class = 'D' }
        @{ Category = 'newValidateSetCandidate'; Endpoint = ''; Field = 'Get-PfbWidget:Type'; Severity = ''; Class = 'E' }
    ) {
        $finding = Build-TestFinding -Category $Category -Endpoint $Endpoint -Field $Field -Severity $Severity
        Get-PfbBacklogFindingClass -Finding $finding | Should -BeExactly $Class
    }

    It 'throws on a category the impact table does not name' {
        $finding = Build-TestFinding -Category 'uncoveredEndpoint' -Endpoint 'GET /widgets'
        $finding.Category = 'brandNewCategory'
        { Get-PfbBacklogFindingClass -Finding $finding } | Should -Throw -ExpectedMessage '*brandNewCategory*'
    }

    It 'throws on a dead-key severity the generator does not emit, including a case variant' {
        $finding = Build-TestFinding -Category 'deadKey' -Endpoint 'GET /widgets' -Field 'names' -Severity 'CATASTROPHIC'
        { Get-PfbBacklogFindingClass -Finding $finding } | Should -Throw -ExpectedMessage '*CATASTROPHIC*'
        $finding.Detail.ReportSeverity = 'destructive'
        { Get-PfbBacklogFindingClass -Finding $finding } | Should -Throw -ExpectedMessage '*destructive*'
    }

    It 'names every category token the drift library defines' {
        foreach ($token in $script:PfbDriftCategoryToken) {
            if ($token -ceq 'deadKey') { continue }
            (@($script:PfbBacklogCategoryClass.Keys) -ccontains $token) | Should -BeTrue -Because "'$token' needs an impact class"
        }
        @($script:PfbBacklogCategoryClass.Keys).Count | Should -Be ($script:PfbDriftCategoryToken.Count - 1)
    }
}

Describe 'Get-PfbBacklogImpact' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
    It 'gives class - and empty counts to an issue with no trusted block' {
        $impact = Get-PfbBacklogImpact -Marker $null -FindingIndex (Build-TestFindingIndex -Finding @())
        $impact.ImpactClass | Should -BeExactly '-'
        $impact.LiveFindings | Should -Be 0
        $impact.TrackedFindings | Should -Be 0
        @($impact.Families).Count | Should -Be 0
    }

    It 'takes the worst live class, counts only reported fingerprints as live, and every active one as tracked' {
        $dead = Build-TestFinding -Category 'deadKey' -Endpoint 'GET /widgets' -Field 'names' -Severity 'WRONG-RESULTS'
        $uncovered = Build-TestFinding -Category 'uncoveredEndpoint' -Endpoint 'GET /widgets'
        $marker = Build-TestMarker -Fingerprint @($dead.Fingerprint, $uncovered.Fingerprint, '00000000000000a1') -Vanished @('00000000000000b2')
        $impact = Get-PfbBacklogImpact -Marker $marker -FindingIndex (Build-TestFindingIndex -Finding @($dead, $uncovered))
        $impact.ImpactClass | Should -BeExactly 'B'
        $impact.LiveFindings | Should -Be 2
        $impact.TrackedFindings | Should -Be 3
    }

    It 'derives families from the live findings, ordinally sorted, leaving out the empty family' {
        $findings = @(
            (Build-TestFinding -Category 'uncoveredEndpoint' -Endpoint 'GET /widgets')
            (Build-TestFinding -Category 'uncoveredEndpoint' -Endpoint 'GET /file-systems')
            (Build-TestFinding -Category 'uncoveredEndpoint' -Endpoint 'GET /file-system-snapshots')
            (Build-TestFinding -Category 'unhandledEnvelopeField' -Field 'more_items_remaining')
        )
        $marker = Build-TestMarker -Fingerprint @($findings | ForEach-Object { $_.Fingerprint })
        $impact = Get-PfbBacklogImpact -Marker $marker -FindingIndex (Build-TestFindingIndex -Finding $findings)
        @($impact.Families) -join ',' | Should -BeExactly 'file-system-snapshots,file-systems,widgets'
    }

    It 'gives class - to a trusted issue whose findings are all gone, and still counts them as tracked' {
        $marker = Build-TestMarker -Fingerprint @('00000000000000a1', '00000000000000a2')
        $impact = Get-PfbBacklogImpact -Marker $marker -FindingIndex (Build-TestFindingIndex -Finding @())
        $impact.ImpactClass | Should -BeExactly '-'
        $impact.LiveFindings | Should -Be 0
        $impact.TrackedFindings | Should -Be 2
    }
}

Describe 'Get-PfbBacklogProposal' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
    It 'proposes <Priority> for class <Class>, with its reason' -ForEach @(
        @{ Class = 'A'; Priority = 'P0' }
        @{ Class = 'B'; Priority = 'P1' }
        @{ Class = 'C'; Priority = 'P1' }
        @{ Class = 'D'; Priority = 'P2' }
        @{ Class = 'E'; Priority = 'P3' }
    ) {
        $proposal = Get-PfbBacklogProposal -ImpactClass $Class -LiveFindings 3
        $proposal.priority | Should -BeExactly $Priority
        $proposal.size | Should -BeExactly 'S'
        $proposal.reason | Should -BeExactly $script:PfbBacklogImpactClass[$Class].Reason
    }

    It 'proposes S at 10 live findings and M at 11, and never L' {
        (Get-PfbBacklogProposal -ImpactClass 'B' -LiveFindings 10).size | Should -BeExactly 'S'
        (Get-PfbBacklogProposal -ImpactClass 'B' -LiveFindings 11).size | Should -BeExactly 'M'
        (Get-PfbBacklogProposal -ImpactClass 'B' -LiveFindings 5000).size | Should -BeExactly 'M'
    }

    It 'sets differs when the current labels disagree, and clears it when they match' {
        (Get-PfbBacklogProposal -ImpactClass 'B' -LiveFindings 7 -CurrentPriority 'P1' -CurrentSize 'S').differs | Should -BeFalse
        (Get-PfbBacklogProposal -ImpactClass 'B' -LiveFindings 7 -CurrentPriority 'P2' -CurrentSize 'S').differs | Should -BeTrue
        (Get-PfbBacklogProposal -ImpactClass 'B' -LiveFindings 7 -CurrentPriority 'P1' -CurrentSize 'M').differs | Should -BeTrue
        (Get-PfbBacklogProposal -ImpactClass 'B' -LiveFindings 7).differs | Should -BeTrue
    }

    It 'proposes nothing for class -: no priority, no size, needs a person, and differs false' {
        $proposal = Get-PfbBacklogProposal -ImpactClass '-' -LiveFindings 0 -CurrentPriority 'P2' -CurrentSize 'M'
        $proposal.priority | Should -BeNullOrEmpty
        $proposal.size | Should -BeNullOrEmpty
        $proposal.reason | Should -BeExactly 'needs a person'
        $proposal.differs | Should -BeFalse
    }

    It 'carries the current values beside the proposal, null when absent' {
        $proposal = Get-PfbBacklogProposal -ImpactClass 'D' -LiveFindings 1 -CurrentPriority 'P2'
        $proposal.current.priority | Should -BeExactly 'P2'
        $proposal.current.size | Should -BeNullOrEmpty
        @($proposal.PSObject.Properties.Name) -join ',' | Should -BeExactly 'priority,size,reason,differs,current'
    }
}

Describe 'Calibration: the hand triage of #163-#172 (<Eol>)' -ForEach $script:lineEndings -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
    It 'proposes <Priority> <Size> for #<Number>, matching its hand labels' -ForEach $script:calibrationCases {
        $findings = @(Get-TestCalibrationFinding -Number $Number -Mix $Mix)
        $labels = @('status:triage', "priority:$Priority", "size:$Size", 'source:drift', 'area:wire-contract')
        $raw = Build-TestRestIssue -Number $Number -Label $labels -Fingerprint @($findings | ForEach-Object { $_.Fingerprint }) -NewLine $NewLine
        $issue = @(ConvertFrom-PfbBacklogRestIssue -Issue @($raw))[0]
        $placement = Get-PfbBacklogPlacement -Issue $issue
        $impact = Get-PfbBacklogImpact -Marker $issue.Marker -FindingIndex (Build-TestFindingIndex -Finding $findings)
        $proposal = Get-PfbBacklogProposal -ImpactClass $impact.ImpactClass -LiveFindings $impact.LiveFindings -CurrentPriority $placement.Priority -CurrentSize $placement.Size

        $impact.LiveFindings | Should -Be $findings.Count
        $proposal.priority | Should -BeExactly $Priority
        $proposal.size | Should -BeExactly $Size
        $proposal.differs | Should -BeFalse
    }
}

Describe 'Get-PfbBacklogRankedRow' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
    It 'orders by every key in turn, and names the key that placed each row' {
        $rows = @(
            # Each row is worse than the one below it on the key after the one that places it,
            # so swapping any two keys in the lib reorders the result.
            (Build-TestRow -Number 11 -Priority 'P1' -Status 'design-approved' -Impact 'B' -Size 'M' -Live 3)
            (Build-TestRow -Number 40 -Priority 'P1' -Status 'design-approved' -Impact 'A' -Size 'L' -Live 1)
            (Build-TestRow -Number 20 -Priority 'P1' -Status 'design-approved' -Impact 'B' -Size 'M' -Live 9)
            (Build-TestRow -Number 60 -Priority 'P0' -Status 'design-approved' -Impact 'B' -Size 'M' -Live 1)
            (Build-TestRow -Number 10 -Priority 'P1' -Status 'design-approved' -Impact 'B' -Size 'M' -Live 3)
            (Build-TestRow -Number 30 -Priority 'P1' -Status 'design-approved' -Impact 'B' -Size 'S' -Live 1)
            (Build-TestRow -Number 50 -Priority 'P1' -Status 'agent-ready' -Impact 'B' -Size 'M' -Live 1)
        )
        $ranked = @(Get-PfbBacklogRankedRow -Row $rows -Lane 'build')
        @($ranked | ForEach-Object { $_.number }) -join ',' | Should -BeExactly '60,50,40,30,20,10,11'
        @($ranked | ForEach-Object { $_.rank }) -join ',' | Should -BeExactly '1,2,3,4,5,6,7'
        $ranked[0].decidedBy | Should -BeNull
        @($ranked | Select-Object -Skip 1 | ForEach-Object { $_.decidedBy }) -join ',' |
            Should -BeExactly 'priority,readiness,impact,size,liveFindings,number'
    }

    It 'does not use readiness in the design lane' {
        $ranked = @(Get-PfbBacklogRankedRow -Lane 'design' -Row @(
                (Build-TestRow -Number 1 -Priority 'P1' -Status 'needs-design' -Impact 'B')
                (Build-TestRow -Number 2 -Priority 'P1' -Status 'needs-design' -Impact 'A')
            ))
        @($ranked | ForEach-Object { $_.number }) -join ',' | Should -BeExactly '2,1'
        $ranked[1].decidedBy | Should -BeExactly 'impact'
    }

    It 'sorts a missing size after L' {
        $ranked = @(Get-PfbBacklogRankedRow -Lane 'build' -Row @(
                (Build-TestRow -Number 1 -Priority 'P1' -Size '')
                (Build-TestRow -Number 2 -Priority 'P1' -Size 'L')
            ))
        @($ranked | ForEach-Object { $_.number }) -join ',' | Should -BeExactly '2,1'
        $ranked[1].decidedBy | Should -BeExactly 'size'
    }

    It 'sorts impact - after E' {
        $ranked = @(Get-PfbBacklogRankedRow -Lane 'build' -Row @(
                (Build-TestRow -Number 1 -Priority 'P2' -Impact '-')
                (Build-TestRow -Number 2 -Priority 'P2' -Impact 'E')
            ))
        @($ranked | ForEach-Object { $_.number }) -join ',' | Should -BeExactly '2,1'
    }

    It 'orders the four priority bands P0 to P3' {
        $ranked = @(Get-PfbBacklogRankedRow -Lane 'design' -Row @(
                (Build-TestRow -Number 1 -Priority 'P3' -Status 'needs-design')
                (Build-TestRow -Number 2 -Priority 'P1' -Status 'needs-design')
                (Build-TestRow -Number 3 -Priority 'P0' -Status 'needs-design')
                (Build-TestRow -Number 4 -Priority 'P2' -Status 'needs-design')
            ))
        @($ranked | ForEach-Object { $_.priority }) -join ',' | Should -BeExactly 'P0,P1,P2,P3'
    }

    It 'returns nothing for an empty lane' {
        @(Get-PfbBacklogRankedRow -Row @() -Lane 'build').Count | Should -Be 0
    }

    It 'refuses to rank a row with no single known priority' {
        { Get-PfbBacklogRankedRow -Lane 'build' -Row @((Build-TestRow -Number 9 -Priority '')) } |
            Should -Throw -ExpectedMessage 'Issue #9 has no single known priority*'
    }

    It 'refuses to rank a row with an unknown impact class' {
        { Get-PfbBacklogRankedRow -Lane 'build' -Row @((Build-TestRow -Number 8 -Priority 'P1' -Impact 'a')) } |
            Should -Throw -ExpectedMessage 'Issue #8 has no known impact class*'
    }

    It 'refuses a non-build status in the build lane' {
        { Get-PfbBacklogRankedRow -Lane 'build' -Row @((Build-TestRow -Number 7 -Priority 'P1' -Status 'needs-design')) } |
            Should -Throw -ExpectedMessage "*has status 'needs-design', which is not a build-lane status."
    }
}

Describe 'Get-PfbBacklog (<Eol>)' -ForEach $script:lineEndings -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
    BeforeAll {
        $script:backlog = Get-TestBacklog -NewLine $NewLine
        $script:lfBacklog = Get-TestBacklog -NewLine "`n"
    }

    It 'places every open issue in exactly one lane, and drops pull requests' {
        $numbers = @(foreach ($lane in $script:PfbBacklogLane) { @(Get-PfbDriftItem -Value $script:backlog.lanes.$lane) | ForEach-Object { [int]$_.number } })
        @($numbers | Sort-Object) -join ',' | Should -BeExactly '10,11,12,13,14,15,16,17,19,20,21'
    }

    It 'counts every lane, and orders counts and lanes as the lanes are ordered' {
        @($script:backlog.counts.PSObject.Properties.Name) -join ',' | Should -BeExactly 'build,design,triage,inFlight,parked,confirmClose,labelErrors'
        @($script:backlog.lanes.PSObject.Properties.Name) -join ',' | Should -BeExactly 'build,design,triage,inFlight,parked,confirmClose,labelErrors'
        @($script:PfbBacklogLane | ForEach-Object { $script:backlog.counts.$_ }) -join ',' | Should -BeExactly '3,2,1,1,1,1,2'
    }

    It 'ranks the ranked lanes and names the deciding key' {
        Get-TestLaneNumber -Backlog $script:backlog -Lane 'build' | Should -BeExactly '10,11,19'
        @($script:backlog.lanes.build | ForEach-Object { [string]$_.decidedBy }) -join ',' | Should -BeExactly ',readiness,priority'
        Get-TestLaneNumber -Backlog $script:backlog -Lane 'design' | Should -BeExactly '21,12'
        $script:backlog.lanes.design[1].decidedBy | Should -BeExactly 'priority'
    }

    It 'lists unranked lanes by number, with null rank and decidedBy' {
        Get-TestLaneNumber -Backlog $script:backlog -Lane 'labelErrors' | Should -BeExactly '17,20'
        foreach ($row in @($script:backlog.lanes.labelErrors) + @($script:backlog.lanes.triage)) {
            $row.rank | Should -BeNullOrEmpty
            $row.decidedBy | Should -BeNullOrEmpty
        }
    }

    It 'carries a proposal in the triage lane only' {
        $triage = $script:backlog.lanes.triage[0]
        $triage.proposed.priority | Should -BeExactly 'P2'
        $triage.proposed.size | Should -BeExactly 'S'
        $triage.proposed.differs | Should -BeTrue
        $triage.proposed.current.priority | Should -BeNullOrEmpty
        foreach ($row in @($script:backlog.lanes.build) + @($script:backlog.lanes.design)) { $row.proposed | Should -BeNullOrEmpty }
    }

    It 'ignores a block on an untrusted issue, and ranks it on its labels alone' {
        $row = @($script:backlog.lanes.design | Where-Object { $_.number -eq 21 })[0]
        $row.impactClass | Should -BeExactly '-'
        $row.trackedFindings | Should -Be 0
        $row.rank | Should -Be 1
    }

    It 'reports a malformed trusted block under labelErrors and still scores every other issue' {
        $row = @($script:backlog.lanes.labelErrors | Where-Object { $_.number -eq 20 })[0]
        @($row.labelProblems)[0] | Should -BeLike 'malformed pfb-drift block: Issue #20: *'
        $script:backlog.counts.build | Should -Be 3
    }

    It 'notes a trusted issue with no live finding, unless it is already resolved-upstream' {
        $open = @($script:backlog.lanes.build | Where-Object { $_.number -eq 19 })[0]
        @($open.notes) -join '' | Should -BeExactly $script:PfbBacklogResolvedNote
        $open.impactClass | Should -BeExactly '-'
        @($script:backlog.lanes.confirmClose[0].notes).Count | Should -Be 0
    }

    It 'writes the schema-v1 top level' {
        @($script:backlog.PSObject.Properties.Name) -join ',' | Should -BeExactly 'schemaVersion,generatedAt,repo,specVersion,counts,lanes'
        $script:backlog.schemaVersion | Should -Be 1
        $script:backlog.repo | Should -BeExactly 'example/repo'
        $script:backlog.specVersion | Should -BeExactly '2.28'
        $script:backlog.generatedAt | Should -BeExactly '2026-09-25T18:00:00Z'
    }

    It 'gives every row exactly the schema-v1 fields, in order, with the derived values' {
        $row = $script:backlog.lanes.build[0]
        @($row.PSObject.Properties.Name) -join ',' |
            Should -BeExactly 'number,title,url,rank,decidedBy,status,priority,size,sources,needsLiveTest,impactClass,liveFindings,trackedFindings,families,proposed,labelProblems,notes'
        $row.url | Should -BeExactly 'https://github.com/example/repo/issues/10'
        $row.status | Should -BeExactly 'agent-ready'
        @($row.sources) -join ',' | Should -BeExactly 'drift'
        $row.needsLiveTest | Should -BeTrue
        $row.impactClass | Should -BeExactly 'A'
        @($row.families) -join ',' | Should -BeExactly 'widgets'
    }

    It 'serialises one-element and empty lists as JSON arrays' {
        $parsed = $script:backlog | ConvertTo-Json -Depth 10 | ConvertFrom-Json
        $parsed.lanes.triage.GetType().IsArray | Should -BeTrue
        $parsed.lanes.build[0].sources.GetType().IsArray | Should -BeTrue
        $parsed.lanes.build[0].families.GetType().IsArray | Should -BeTrue
        $parsed.lanes.labelErrors[0].labelProblems.GetType().IsArray | Should -BeTrue
        $parsed.lanes.build[0].labelProblems.GetType().IsArray | Should -BeTrue
        @($parsed.lanes.build[0].labelProblems).Count | Should -Be 0
        $parsed.lanes.triage[0].proposed.current.PSObject.Properties.Name -join ',' | Should -BeExactly 'priority,size'
    }

    It 'gives the same backlog for LF and CRLF bodies' {
        ($script:backlog | ConvertTo-Json -Depth 10) | Should -BeExactly ($script:lfBacklog | ConvertTo-Json -Depth 10)
    }

    It 'assembles the whole fixture under Set-StrictMode -Version Latest' {
        Set-StrictMode -Version Latest
        $strict = Get-TestBacklog -NewLine $NewLine
        ($strict | ConvertTo-Json -Depth 10) | Should -BeExactly ($script:backlog | ConvertTo-Json -Depth 10)
    }
}

Describe 'Get-PfbBacklog: edge cases' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
    It 'gives a complete result with every lane empty when there are no open issues' {
        $empty = Get-PfbBacklog -Issue @() -Finding @() -Repo 'example/repo' -SpecVersion '2.28' -GeneratedAt '2026-09-25T18:00:00Z'
        @($script:PfbBacklogLane | ForEach-Object { $empty.counts.$_ }) -join ',' | Should -BeExactly '0,0,0,0,0,0,0'
        ($empty | ConvertTo-Json -Depth 10) | Should -Match '"build": \[\]'
    }

    It 'throws on a finding the impact table cannot classify, even when no issue tracks it' {
        $finding = Build-TestFinding -Category 'uncoveredEndpoint' -Endpoint 'GET /widgets'
        $finding.Category = 'brandNewCategory'
        { Get-PfbBacklog -Issue @() -Finding @($finding) -Repo 'example/repo' -SpecVersion '2.28' -GeneratedAt 'x' } |
            Should -Throw -ExpectedMessage '*brandNewCategory*'
    }
}

Describe 'Get-PfbBacklog: the calibration issues assembled together (<Eol>)' -ForEach $script:assembledCalibration -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
    It 'reproduces all ten hand triages (10/10)' {
        $findings = [System.Collections.Generic.List[object]]::new()
        $issues = [System.Collections.Generic.List[object]]::new()
        foreach ($case in $Cases) {
            $mine = @(Get-TestCalibrationFinding -Number $case.Number -Mix $case.Mix)
            foreach ($f in $mine) { $findings.Add($f) }
            $labels = @('status:triage', "priority:$($case.Priority)", "size:$($case.Size)", 'source:drift', 'area:wire-contract')
            $issues.Add((Build-TestRestIssue -Number $case.Number -Label $labels -Fingerprint @($mine | ForEach-Object { $_.Fingerprint }) -NewLine $NewLine))
        }
        $backlog = Get-PfbBacklog -Issue $issues.ToArray() -Finding $findings.ToArray() -Repo 'example/repo' -SpecVersion '2.28' -GeneratedAt 'x'
        $matched = @($backlog.lanes.triage | Where-Object {
                $_.proposed.priority -ceq $_.priority -and $_.proposed.size -ceq $_.size -and -not $_.proposed.differs
            })
        $backlog.counts.triage | Should -Be 10
        $matched.Count | Should -Be 10
    }
}

Describe 'Format-PfbBacklogMarkdown' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
    BeforeAll {
        $script:mdBacklog = Get-TestBacklog
        $script:md = Format-PfbBacklogMarkdown -Backlog $script:mdBacklog
        $script:mdLines = @($script:md -split "`n")
    }

    It 'writes the header, then one section per lane in lane order, with its count' {
        $script:mdLines[0] | Should -BeExactly '# Backlog: example/repo'
        $script:mdLines | Should -Contain 'Lanes: build 3, design 2, triage 1, inFlight 1, parked 1, confirmClose 1, labelErrors 2.'
        @($script:mdLines | Where-Object { $_.StartsWith('## ') }) -join ' / ' |
            Should -BeExactly '## Build (agent-ready, design-approved): 3 / ## Design (needs-design): 2 / ## Triage (proposals to confirm): 1 / ## In flight (in-progress, needs-review): 1 / ## Parked (blocked, human-only): 1 / ## Confirm close (resolved-upstream): 1 / ## Label errors: 2'
    }

    It 'shows decidedBy in ranked lanes, the proposal in triage, and the problems in labelErrors' {
        $script:mdLines | Should -Contain '| Rank | Issue | P | S | Impact | Live | Live test | Decided by |'
        $script:mdLines | Should -Contain '| 1 | [#10](https://github.com/example/repo/issues/10) Issue 10 | P0 | S | A | 1 | yes | - |'
        $script:mdLines | Should -Contain '| 2 | [#11](https://github.com/example/repo/issues/11) Issue 11 | P0 | S | B | 1 |  | readiness |'
        $script:mdLines | Should -Contain '| - | [#13](https://github.com/example/repo/issues/13) Issue 13 | - | - | D | 1 |  | P2 S: net-new coverage | yes |'
        $script:mdLines | Should -Contain '| - | [#17](https://github.com/example/repo/issues/17) Issue 17 | P2 | S | - | 0 |  | no status: label |'
    }

    It 'caps each lane at -First rows and says how many more' {
        $lines = @((Format-PfbBacklogMarkdown -Backlog $script:mdBacklog -First 1) -split "`n")
        $lines | Should -Contain '_+2 more._'
        $lines | Should -Not -Contain '| 2 | [#11](https://github.com/example/repo/issues/11) Issue 11 | P0 | S | B | 1 |  | readiness |'
    }

    It 'lists a shown row''s notes under its table' {
        $script:mdLines | Should -Contain "- #19: $($script:PfbBacklogResolvedNote)"
    }

    It 'escapes pipes and flattens newlines in titles' {
        $raw = Build-TestRestIssue -Number 30 -Title "a | b`r`nc" -Label @('status:in-progress', 'area:ci', 'source:human')
        $backlog = Get-PfbBacklog -Issue @($raw) -Finding @() -Repo 'example/repo' -SpecVersion '2.28' -GeneratedAt 'x'
        (Format-PfbBacklogMarkdown -Backlog $backlog) | Should -Match ([regex]::Escape('[#30](https://github.com/example/repo/issues/30) a \| b c |'))
    }

    It 'restricts sections to -Lane, in lane order whatever order it is given in, case-insensitively' {
        $lines = @((Format-PfbBacklogMarkdown -Backlog $script:mdBacklog -Lane 'Triage', 'build') -split "`n")
        @($lines | Where-Object { $_.StartsWith('## ') }) -join ' / ' |
            Should -BeExactly '## Build (agent-ready, design-approved): 3 / ## Triage (proposals to confirm): 1'
    }

    It 'says None for an empty lane' {
        $empty = Get-PfbBacklog -Issue @() -Finding @() -Repo 'example/repo' -SpecVersion '2.28' -GeneratedAt 'x'
        @((Format-PfbBacklogMarkdown -Backlog $empty) -split "`n" | Where-Object { $_ -ceq '_None._' }).Count | Should -Be 7
    }
}
