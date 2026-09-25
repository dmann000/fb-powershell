#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    tools/Build-PfbBacklog.ps1 end to end with the network mocked, and the workflow that runs it.
.DESCRIPTION
    The rules are tested in Tests/PfbBacklogTools.Tests.ps1 and the REST helpers in
    Tests/PfbGitHubRead.Tests.ps1. This file proves what only the shell can get wrong: the
    two files land where -OutputPath says (a relative path included), the JSON is schema v1,
    console mode prints and writes nothing, the request is the paged, anonymous-unless-told
    GET it should be, and a failed call surfaces the library's message.

    The script is invoked in-process with & (as Tests/New-PfbDriftIssue.Tests.ps1:100
    does), so Pester's Invoke-RestMethod mock reaches it. The non-zero process exit on a
    throw follows from pwsh semantics and is not tested: an in-process call has no exit
    code, and a child pwsh cannot see the mock.

    EDITION-GATED like the other tooling tests: every Describe carries
    -Skip:($PSVersionTable.PSVersion.Major -lt 7), the file-level BeforeAll guards its
    dot-source, and the 5.1 skip count is pinned in Tests/coverage-baseline.psd1.
#>

BeforeAll {
    $script:isPwsh7 = $PSVersionTable.PSVersion.Major -ge 7
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:scriptPath = Join-Path (Join-Path $script:repoRoot 'tools') 'Build-PfbBacklog.ps1'
    $script:workflowDir = Join-Path (Join-Path $script:repoRoot '.github') 'workflows'
    $script:utf8 = New-Object System.Text.UTF8Encoding $false

    if ($script:isPwsh7) {
        # For fixture fingerprints only; the script under test dot-sources its own copy.
        # The fingerprints are computed inside Get-TestIssuePage, NOT stored in $script: here:
        # that helper runs inside the Invoke-RestMethod mock body, below `& Build-PfbBacklog.ps1`
        # on the call stack, where $script: resolves to the script under test (see Global
        # Constraints).
        . (Join-Path (Join-Path (Join-Path $script:repoRoot 'tools') 'lib') 'PfbDriftIssueTools.ps1')
    }

    $script:driftJson = @'
{
  "schemaVersion": 1, "analysedVersions": [ "2.27" ],
  "uncoveredEndpoints": [ { "endpoint": "GET /widgets", "minVersion": "2.3" } ],
  "parameterGaps": [], "systemicGaps": [], "conventionStrength": [], "validateSetDrift": [], "newValidateSetCandidates": [],
  "responseFieldRemovals": [], "responseFieldRenameCandidates": [], "unhandledResponseEnvelopeFields": []
}
'@
    $script:deadKeyJson = '{ "specVersion": "2.28", "counts": {}, "deadKeys": [ { "method": "DELETE", "endpoint": "widgets", "wireKey": "names", "cmdlet": "Remove-PfbWidget", "parameter": "Name", "severity": "DESTRUCTIVE", "classification": "test" } ], "noSurvivingSelector": [] }'

    # A fresh directory per test holding the two fixture reports.
    function Build-TestReport {
        $dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $dir
        $paths = @{ Dir = $dir; Drift = (Join-Path $dir 'drift.json'); DeadKey = (Join-Path $dir 'deadkey.json') }
        [System.IO.File]::WriteAllText($paths.Drift, $script:driftJson, $script:utf8)
        [System.IO.File]::WriteAllText($paths.DeadKey, $script:deadKeyJson, $script:utf8)
        return $paths
    }

    function Build-TestRestIssue {
        param([int]$Number, [string[]]$Label = @(), [AllowNull()][string[]]$Fingerprint = $null, [switch]$PullRequest)
        $body = "Human text.`n"
        if ($null -ne $Fingerprint) {
            $body = "Human text.`n`n<!-- pfb-drift-block:start -->`n<!-- pfb-drift-group: deadkey:widgets -->`n<!-- pfb-drift-fingerprints: $($Fingerprint -join ',') -->`n<!-- pfb-drift-block:end -->"
        }
        $row = [ordered]@{
            url = "https://api.github.com/repos/example/repo/issues/$Number"; html_url = "https://github.com/example/repo/issues/$Number"
            number = $Number; title = "Issue $Number"; labels = @($Label | ForEach-Object { [ordered]@{ name = $_ } })
            state = 'open'; state_reason = $null; body = $body
        }
        if ($PullRequest) { $row['pull_request'] = [ordered]@{ url = 'x' } }
        return ($row | ConvertTo-Json -Depth 5 | ConvertFrom-Json)
    }

    # One page of open issues: a build issue, a triage issue, a pull request, an issue with
    # no status: label, and one in flight.
    function Get-TestIssuePage {
        $records = @(
            (Build-TestRestIssue -Number 10 -Label @('status:agent-ready', 'priority:P0', 'size:S', 'area:wire-contract', 'source:drift') -Fingerprint @((Get-PfbDriftFingerprint -Category 'deadKey' -Endpoint 'DELETE /widgets' -Field 'names')))
            (Build-TestRestIssue -Number 11 -Label @('status:triage', 'area:cmdlet-coverage', 'source:drift') -Fingerprint @((Get-PfbDriftFingerprint -Category 'uncoveredEndpoint' -Endpoint 'GET /widgets' -Field '')))
            (Build-TestRestIssue -Number 12 -Label @('status:agent-ready') -PullRequest)
            (Build-TestRestIssue -Number 13 -Label @('priority:P2', 'area:ci', 'source:human'))
            (Build-TestRestIssue -Number 14 -Label @('status:in-progress', 'priority:P1', 'size:S', 'area:ci', 'source:human'))
        )
        , $records
    }

    # Runs the script with the token variables cleared (then set from -Environment), so a
    # developer's own GH_TOKEN never leaks into what a test observes.
    function Invoke-TestBacklog {
        param([hashtable]$Parameter, [hashtable]$Environment = @{})
        $saved = @{}
        foreach ($name in 'GH_TOKEN', 'GITHUB_TOKEN') {
            $saved[$name] = [Environment]::GetEnvironmentVariable($name)
            [Environment]::SetEnvironmentVariable($name, $null)
        }
        foreach ($name in $Environment.Keys) { [Environment]::SetEnvironmentVariable($name, $Environment[$name]) }
        try { & $script:scriptPath @Parameter 6>$null }
        finally {
            foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
        }
    }

    function Get-TestParameter {
        param([hashtable]$Paths, [hashtable]$Extra = @{})
        $parameter = @{ Repo = 'example/repo'; DriftReportPath = $Paths.Drift; DeadKeyReportPath = $Paths.DeadKey }
        foreach ($key in $Extra.Keys) { $parameter[$key] = $Extra[$key] }
        return $parameter
    }
}

Describe 'Build-PfbBacklog.ps1' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
    It 'writes PfbBacklog.json and PfbBacklog.md to -OutputPath, creating the directory' {
        Mock Invoke-RestMethod { Get-TestIssuePage }
        $paths = Build-TestReport
        $out = Join-Path (Join-Path $paths.Dir 'out') 'nested'
        $result = Invoke-TestBacklog -Parameter (Get-TestParameter -Paths $paths -Extra @{ OutputPath = $out })
        $result | Should -BeNullOrEmpty
        Test-Path -LiteralPath (Join-Path $out 'PfbBacklog.json') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $out 'PfbBacklog.md') | Should -BeTrue
    }

    It 'writes JSON that matches schema v1' {
        Mock Invoke-RestMethod { Get-TestIssuePage }
        $paths = Build-TestReport
        $out = Join-Path $paths.Dir 'out'
        $null = Invoke-TestBacklog -Parameter (Get-TestParameter -Paths $paths -Extra @{ OutputPath = $out })
        $text = [System.IO.File]::ReadAllText((Join-Path $out 'PfbBacklog.json'))
        $text | Should -Match '"generatedAt": "\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z"'
        $json = $text | ConvertFrom-Json
        @($json.PSObject.Properties.Name) -join ',' | Should -BeExactly 'schemaVersion,generatedAt,repo,specVersion,counts,lanes'
        $json.schemaVersion | Should -Be 1
        $json.repo | Should -BeExactly 'example/repo'
        $json.specVersion | Should -BeExactly '2.28'
        @($json.lanes.PSObject.Properties.Name) -join ',' | Should -BeExactly 'build,design,triage,inFlight,parked,confirmClose,labelErrors'
        $json.lanes.build[0].number | Should -Be 10
        $json.lanes.build[0].rank | Should -Be 1
        $json.lanes.build[0].impactClass | Should -BeExactly 'A'
        @($json.lanes.build[0].families) -join ',' | Should -BeExactly 'widgets'
        $json.lanes.triage[0].proposed.priority | Should -BeExactly 'P2'
        $json.lanes.triage[0].proposed.differs | Should -BeTrue
        $json.counts.labelErrors | Should -Be 1
        $text | Should -Not -Match '"number": 12\b'
    }

    It 'resolves a relative -OutputPath against the current PowerShell location, not the process directory' {
        Mock Invoke-RestMethod { Get-TestIssuePage }
        $paths = Build-TestReport
        Push-Location -LiteralPath $paths.Dir
        try { $null = Invoke-TestBacklog -Parameter (Get-TestParameter -Paths $paths -Extra @{ OutputPath = 'relative-out' }) }
        finally { Pop-Location }
        Test-Path -LiteralPath (Join-Path (Join-Path $paths.Dir 'relative-out') 'PfbBacklog.json') | Should -BeTrue
    }

    It 'prints the Markdown to the console when -OutputPath is omitted' {
        Mock Invoke-RestMethod { Get-TestIssuePage }
        $paths = Build-TestReport
        $text = [string](Invoke-TestBacklog -Parameter (Get-TestParameter -Paths $paths))
        $text | Should -Match '(?m)^# Backlog: example/repo$'
        $text | Should -Match ([regex]::Escape('[#10](https://github.com/example/repo/issues/10)'))
        @(Get-ChildItem -LiteralPath $paths.Dir -Filter 'PfbBacklog.*' -Recurse).Count | Should -Be 0
    }

    It 'shapes the console output with -Lane and -First, and takes -Lane in any case' {
        Mock Invoke-RestMethod { Get-TestIssuePage }
        $paths = Build-TestReport
        $text = [string](Invoke-TestBacklog -Parameter (Get-TestParameter -Paths $paths -Extra @{ Lane = @('Triage'); First = 1 }))
        $text | Should -Match '(?m)^## Triage \(proposals to confirm\): 1$'
        $text | Should -Not -Match '(?m)^## Build'
    }

    It 'reads the open issues of -Repo, paged, with its own User-Agent and no token by default' {
        Mock Invoke-RestMethod { Get-TestIssuePage }
        $paths = Build-TestReport
        $null = Invoke-TestBacklog -Parameter (Get-TestParameter -Paths $paths)
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $Uri -ceq 'https://api.github.com/repos/example/repo/issues?state=open&per_page=100' -and $FollowRelLink -and
            $Method -eq 'Get' -and $Headers['User-Agent'] -ceq 'fb-powershell-backlog-scorer' -and -not $Headers.ContainsKey('Authorization')
        }
    }

    It 'sends -Token as a bearer header' {
        Mock Invoke-RestMethod { Get-TestIssuePage }
        $paths = Build-TestReport
        $null = Invoke-TestBacklog -Parameter (Get-TestParameter -Paths $paths -Extra @{ Token = 'abc123' })
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { $Headers['Authorization'] -ceq 'Bearer abc123' }
    }

    It 'falls back to GH_TOKEN, then GITHUB_TOKEN' {
        Mock Invoke-RestMethod { Get-TestIssuePage }
        $paths = Build-TestReport
        $null = Invoke-TestBacklog -Parameter (Get-TestParameter -Paths $paths) -Environment @{ GITHUB_TOKEN = 'from-github-token' }
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { $Headers['Authorization'] -ceq 'Bearer from-github-token' }
        $null = Invoke-TestBacklog -Parameter (Get-TestParameter -Paths $paths) -Environment @{ GH_TOKEN = 'from-gh-token'; GITHUB_TOKEN = 'from-github-token' }
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { $Headers['Authorization'] -ceq 'Bearer from-gh-token' }
    }

    It 'throws with the library''s message when the API call fails' {
        Mock Invoke-RestMethod { throw [System.Net.Http.HttpRequestException]::new('No such host is known.') }
        $paths = Build-TestReport
        { Invoke-TestBacklog -Parameter (Get-TestParameter -Paths $paths) } |
            Should -Throw -ExpectedMessage 'GET https://api.github.com/repos/example/repo/issues?state=open&per_page=100 failed: No such host is known.'
    }

    It 'throws when a report file is missing' {
        Mock Invoke-RestMethod { Get-TestIssuePage }
        $paths = Build-TestReport
        $parameter = Get-TestParameter -Paths $paths -Extra @{ DriftReportPath = (Join-Path $paths.Dir 'absent.json') }
        { Invoke-TestBacklog -Parameter $parameter } | Should -Throw -ExpectedMessage '*drift report was not found*'
    }

    It 'writes valid output with every lane empty when there are no open issues' {
        Mock Invoke-RestMethod { , @() }
        $paths = Build-TestReport
        $out = Join-Path $paths.Dir 'out'
        $null = Invoke-TestBacklog -Parameter (Get-TestParameter -Paths $paths -Extra @{ OutputPath = $out })
        $text = [System.IO.File]::ReadAllText((Join-Path $out 'PfbBacklog.json'))
        $text | Should -Match '"build": \[\]'
        $json = $text | ConvertFrom-Json
        @($json.counts.PSObject.Properties | ForEach-Object { $_.Value }) -join ',' | Should -BeExactly '0,0,0,0,0,0,0'
    }
}

Describe 'backlog workflow' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
    BeforeAll {
        $script:workflow = [System.IO.File]::ReadAllText((Join-Path $script:workflowDir 'backlog.yml'))
        $drift = [System.IO.File]::ReadAllText((Join-Path $script:workflowDir 'drift-issues.yml'))
        $script:driftWorkflowName = [regex]::Match($drift, '(?m)^name:\s*(.+?)\s*$').Groups[1].Value
    }

    It 'runs on dispatch and after every Drift Issues run, whatever its conclusion' {
        # Only the on: block, up to the next top-level key.
        $on = [regex]::Match($script:workflow, '(?ms)^on:\r?\n(.*?)(?=^\S)').Groups[1].Value
        @([regex]::Matches($on, '(?m)^  ([a-z_]+):') | ForEach-Object { $_.Groups[1].Value }) -join ',' | Should -BeExactly 'workflow_dispatch,workflow_run'
        # Chained by NAME: renaming drift-issues.yml's name: would silently break the chain.
        $script:driftWorkflowName | Should -BeExactly 'Drift Issues'
        $on | Should -Match ("(?m)^    workflows: \['" + [regex]::Escape($script:driftWorkflowName) + "'\]\s*$")
        $on | Should -Match '(?m)^    types: \[completed\]\s*$'
        $script:workflow | Should -Not -Match 'workflow_run\.conclusion'
    }

    It 'reads contents and issues only, with no secret but the built-in token' {
        $script:workflow | Should -Match '(?m)^  contents: read\s*$'
        $script:workflow | Should -Match '(?m)^  issues: read\s*$'
        @([regex]::Matches($script:workflow, '(?m)^\s+[a-z-]+: write\s*$')).Count | Should -Be 0
        @([regex]::Matches($script:workflow, 'secrets\.([A-Za-z_]+)') | ForEach-Object { $_.Groups[1].Value } | Where-Object { $_ -cne 'GITHUB_TOKEN' }).Count | Should -Be 0
    }

    It 'lets the latest run win, since it only reads' {
        $script:workflow | Should -Match '(?m)^  group: backlog\s*$'
        $script:workflow | Should -Match '(?m)^  cancel-in-progress: true\s*$'
    }

    It 'passes -First only when the input is non-empty, which it is not on workflow_run' {
        $script:workflow | Should -Match ([regex]::Escape('BACKLOG_FIRST: ${{ inputs.first }}'))
        $script:workflow | Should -Match ([regex]::Escape("if (`$env:BACKLOG_FIRST) { `$params['First'] = [int]`$env:BACKLOG_FIRST }"))
        $script:workflow | Should -Not -Match '-First \$\{\{'
    }

    It 'publishes the Markdown to the job summary and the JSON as a 90-day artifact, on the pinned actions' {
        @([regex]::Matches($script:workflow, '(?m)^\s+uses: (\S+)') | ForEach-Object { $_.Groups[1].Value }) -join ',' |
            Should -BeExactly 'actions/checkout@v7,actions/upload-artifact@v5'
        $script:workflow | Should -Match ([regex]::Escape("OutputPath = (Join-Path `$env:RUNNER_TEMP 'backlog')"))
        $script:workflow | Should -Match 'PfbBacklog\.md'
        $script:workflow | Should -Match '\$env:GITHUB_STEP_SUMMARY'
        $script:workflow | Should -Match '(?m)^\s+path: \$\{\{ runner\.temp \}\}/backlog/PfbBacklog\.json\s*$'
        $script:workflow | Should -Match '(?m)^\s+retention-days: 90\s*$'
    }
}
