#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    tools/New-PfbDriftIssue.ps1 end to end against a fake gh, and the workflow that runs it.
.DESCRIPTION
    The decisions are tested in Tests/PfbDriftIssueTools.Tests.ps1. This file proves what
    only the shell can get wrong: that a dry run makes no write call at all, that -Apply
    does make them (the control that keeps the first assertion from passing vacuously),
    and that the two stop conditions -- a missing label and the restructure guard -- stop
    before the first write rather than halfway through.

    THE FAKE gh IS A SCRIPT FILE, passed as -GhCommand. It appends every argument list it
    receives to a log and answers the two reads from fixture files. Array splatting passes
    '--repo' and friends through to a script verbatim on both editions (measured), so the
    log shows exactly the argv a real gh would have received.

    NOT EDITION-GATED: the script and its library are 5.1-compatible, so this runs on both
    legs and skips nothing.
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:scriptPath = Join-Path (Join-Path $script:repoRoot 'tools') 'New-PfbDriftIssue.ps1'
    $script:utf8 = New-Object System.Text.UTF8Encoding $false

    # One uncovered endpoint (fingerprint 69f4e2d74329848a) and one parameter gap, both in
    # family 'widgets', so a clean run plans exactly one Create.
    $script:driftJson = @'
{
  "schemaVersion": 1, "analysedVersions": [ "2.28" ],
  "uncoveredEndpoints": [ { "endpoint": "GET /widgets", "minVersion": "2.3" } ],
  "parameterGaps": [ { "endpoint": "PATCH /widgets", "cmdlets": [ "Update-PfbWidget" ], "missingQueryParameters": [ "ids" ], "missingBodyProperties": [], "readOnlyFields": [], "confidence": { "level": "high", "caveat": "" }, "annotations": [] } ],
  "systemicGaps": [], "conventionStrength": [], "validateSetDrift": [], "newValidateSetCandidates": [],
  "responseFieldRemovals": [], "responseFieldRenameCandidates": [], "unhandledResponseEnvelopeFields": []
}
'@
    $script:deadKeyJson = '{ "specVersion": "2.28", "counts": {}, "deadKeys": [], "noSurvivingSelector": [] }'
    $script:allLabels = '[{"name":"source:drift"},{"name":"status:triage"},{"name":"needs:live-test"},{"name":"area:cmdlet-coverage"},{"name":"area:wire-contract"},{"name":"status:resolved-upstream"}]'
    $script:uncoveredFp = '69f4e2d74329848a'

    $script:fakeGhTemplate = @'
[System.IO.File]::AppendAllText('__LOG__', ((@($args) | ForEach-Object { [string]$_ }) -join "`t") + "`n")
$verb = ''
if (@($args).Count -ge 2) { $verb = '{0} {1}' -f $args[0], $args[1] }
if ($verb -eq 'issue list') { [System.IO.File]::ReadAllText('__ISSUES__'); exit 0 }
if ($verb -eq 'label list') { [System.IO.File]::ReadAllText('__LABELS__'); exit 0 }
if ($verb -eq 'issue create') { 'https://github.com/example/repo/issues/901'; exit 0 }
exit 0
'@

    function Write-TestFile {
        param([string]$Path, [string]$Text)
        [System.IO.File]::WriteAllText($Path, $Text, $script:utf8)
    }

    # An isolated fixture directory per test: reports, a settled directory, gh's canned
    # answers, the fake gh and its call log.
    function Build-TestRun {
        param([string]$IssuesJson = '[]', [string]$LabelsJson = $script:allLabels)
        $dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $dir
        $paths = @{
            Log     = Join-Path $dir 'gh.log'
            Settled = Join-Path $dir 'settled'
            Drift   = Join-Path $dir 'drift.json'
            DeadKey = Join-Path $dir 'deadkey.json'
            Issues  = Join-Path $dir 'issues.json'
            Labels  = Join-Path $dir 'labels.json'
            Gh      = Join-Path $dir 'fake-gh.ps1'
        }
        $null = New-Item -ItemType Directory -Path $paths.Settled
        Write-TestFile -Path $paths.Drift -Text $script:driftJson
        Write-TestFile -Path $paths.DeadKey -Text $script:deadKeyJson
        Write-TestFile -Path $paths.Issues -Text $IssuesJson
        Write-TestFile -Path $paths.Labels -Text $LabelsJson
        Write-TestFile -Path $paths.Log -Text ''
        Write-TestFile -Path $paths.Gh -Text ($script:fakeGhTemplate.Replace('__LOG__', $paths.Log).Replace('__ISSUES__', $paths.Issues).Replace('__LABELS__', $paths.Labels))
        return $paths
    }

    function Invoke-TestRun {
        param([hashtable]$Paths, [switch]$Apply, [switch]$AcceptMassVanish)
        $params = @{
            GhCommand         = $Paths.Gh
            Repo              = 'example/repo'
            DriftReportPath   = $Paths.Drift
            DeadKeyReportPath = $Paths.DeadKey
            SettledDirectory  = $Paths.Settled
            PassThru          = $true
        }
        if ($Apply) { $params['Apply'] = $true }
        if ($AcceptMassVanish) { $params['AcceptMassVanish'] = $true }
        & $script:scriptPath @params 6>$null 3>$null
    }

    # Every call the fake received, one tab-joined argv per string.
    function Get-TestGhCall {
        param([hashtable]$Paths)
        @([System.IO.File]::ReadAllLines($Paths.Log) | Where-Object { $_ -ne '' })
    }

    function Get-TestWriteCall {
        param([hashtable]$Paths)
        @(Get-TestGhCall -Paths $Paths | Where-Object { -not ($_.StartsWith("issue`tlist`t") -or $_.StartsWith("label`tlist`t")) })
    }

    function Get-TestIssueJson {
        param([int]$Number, [string]$GroupKey, [string[]]$Fingerprints, [string[]]$Labels = @('source:drift', 'status:triage'))
        $body = "Human text.`n`n<!-- pfb-drift-block:start -->`n<!-- pfb-drift-group: $GroupKey -->`n<!-- pfb-drift-fingerprints: $($Fingerprints -join ',') -->`n<!-- pfb-drift-block:end -->"
        $issue = @{ number = $Number; title = 'Drift issue'; body = $body; state = 'OPEN'; stateReason = ''; labels = @($Labels | ForEach-Object { @{ name = $_ } }) }
        return (ConvertTo-Json -Depth 5 -InputObject @($issue))
    }
}

Describe 'New-PfbDriftIssue.ps1' {
    It 'makes no write call in a dry run' {
        $paths = Build-TestRun
        $result = Invoke-TestRun -Paths $paths
        @(Get-TestWriteCall -Paths $paths).Count | Should -Be 0
        @(Get-TestGhCall -Paths $paths).Count | Should -Be 2
        @($result.Plan.Actions | Where-Object { $_.Action -ceq 'Create' }).Count | Should -Be 1
    }

    It 'makes the planned write calls with -Apply (the control for the dry-run assertion)' {
        $paths = Build-TestRun
        $null = Invoke-TestRun -Paths $paths -Apply
        $writes = @(Get-TestWriteCall -Paths $paths)
        $writes.Count | Should -Be 1
        $writes[0].StartsWith("issue`tcreate`t--repo`texample/repo`t--title`t") | Should -BeTrue
        $writes[0] | Should -Match "`t--label`tsource:drift`t"
        $writes[0] | Should -Match "`t--body-file`t"
    }

    It 'passes the --json field list to gh as a single argument' {
        $paths = Build-TestRun
        $null = Invoke-TestRun -Paths $paths
        $list = @(Get-TestGhCall -Paths $paths | Where-Object { $_.StartsWith("issue`tlist`t") })[0]
        # 'labels' is load-bearing twice over: it carries status:, and source:drift is the only
        # thing that makes an issue's machine block count (ConvertFrom-PfbDriftIssue).
        @($list -split "`t") -ccontains 'number,title,body,state,stateReason,labels' | Should -BeTrue
    }

    It 'appends to an open group issue by editing its body and then commenting' {
        $paths = Build-TestRun -IssuesJson (Get-TestIssueJson -Number 7 -GroupKey 'family:widgets' -Fingerprints @($script:uncoveredFp))
        $result = Invoke-TestRun -Paths $paths -Apply
        $result.Plan.TrackedCount | Should -Be 1
        $writes = @(Get-TestWriteCall -Paths $paths)
        $writes.Count | Should -Be 2
        $writes[0].StartsWith("issue`tedit`t7`t") | Should -BeTrue
        $writes[1].StartsWith("issue`tcomment`t7`t") | Should -BeTrue
    }

    It 'fixes a status label that disagrees with the block by commenting and relabelling, with no body edit' {
        # Both fixture findings (the uncovered endpoint and c3e450c0c7e47163, the ids gap) are
        # tracked, so the block is current; only the label is wrong.
        $issueJson = Get-TestIssueJson -Number 7 -GroupKey 'family:widgets' -Fingerprints @($script:uncoveredFp, 'c3e450c0c7e47163') -Labels @('source:drift', 'status:resolved-upstream')
        $paths = Build-TestRun -IssuesJson $issueJson
        $result = Invoke-TestRun -Paths $paths -Apply
        $result.Plan.TrackedCount | Should -Be 2
        $writes = @(Get-TestWriteCall -Paths $paths)
        $writes.Count | Should -Be 2
        $writes[0].StartsWith("issue`tcomment`t7`t") | Should -BeTrue
        $writes[1] | Should -BeExactly "issue`tedit`t7`t--repo`texample/repo`t--add-label`tstatus:triage`t--remove-label`tstatus:resolved-upstream"
    }

    It 'stops before any write when a label the plan needs does not exist' {
        $paths = Build-TestRun -LabelsJson '[{"name":"source:drift"}]'
        { Invoke-TestRun -Paths $paths -Apply } | Should -Throw -ExpectedMessage '*has no label*'
        @(Get-TestWriteCall -Paths $paths).Count | Should -Be 0
    }

    It 'only warns about a missing label in a dry run' {
        $paths = Build-TestRun -LabelsJson '[{"name":"source:drift"}]'
        { Invoke-TestRun -Paths $paths } | Should -Not -Throw
    }

    It 'stops before any write when the restructure guard trips, and proceeds with -AcceptMassVanish' {
        $gone = @('00000000000000a1', '00000000000000a2', '00000000000000a3')
        $paths = Build-TestRun -IssuesJson (Get-TestIssueJson -Number 7 -GroupKey 'family:widgets' -Fingerprints (@($script:uncoveredFp) + $gone))
        { Invoke-TestRun -Paths $paths -Apply } | Should -Throw -ExpectedMessage '*restructure guard*'
        @(Get-TestWriteCall -Paths $paths).Count | Should -Be 0
        $result = Invoke-TestRun -Paths $paths -AcceptMassVanish
        $result.Plan.Aborted | Should -BeFalse
    }

    It 'skips a finding a settled entry names, and never reads docs/settled/README.md' {
        $paths = Build-TestRun
        Write-TestFile -Path (Join-Path $paths.Settled 'README.md') -Text "**Drift keys:** fp:$($script:uncoveredFp)`n"
        $readmeOnly = Invoke-TestRun -Paths $paths
        @($readmeOnly.SettledKeys).Count | Should -Be 0
        Write-TestFile -Path (Join-Path $paths.Settled 'widgets.md') -Text "# Widgets`n`n**Drift keys:** fp:$($script:uncoveredFp)`n"
        $settled = Invoke-TestRun -Paths $paths
        $skip = @($settled.Plan.Actions | Where-Object { $_.Action -ceq 'Skip' })
        $skip.Count | Should -Be 1
        $skip[0].Reason | Should -BeExactly "settled: widgets.md (fp:$($script:uncoveredFp))"
    }

    It 'returns the findings, issues and plan with -PassThru' {
        $paths = Build-TestRun
        $result = Invoke-TestRun -Paths $paths
        @($result.Findings).Count | Should -Be 2
        @($result.Issues).Count | Should -Be 0
        $result.Plan.Aborted | Should -BeFalse
    }
}

Describe 'drift-issues workflow' {
    BeforeAll {
        $script:workflow = [System.IO.File]::ReadAllText((Join-Path (Join-Path (Join-Path $script:repoRoot '.github') 'workflows') 'drift-issues.yml'))
    }

    It 'runs only when dispatched by hand' {
        # Only the on: block, up to the next top-level key -- `issues: write` under
        # permissions: is not a trigger.
        $on = [regex]::Match($script:workflow, '(?ms)^on:\r?\n(.*?)(?=^\S)').Groups[1].Value
        $on | Should -Match '(?m)^  workflow_dispatch:'
        @([regex]::Matches($on, '(?m)^  ([a-z_]+):') | ForEach-Object { $_.Groups[1].Value }) -join ',' | Should -BeExactly 'workflow_dispatch'
    }

    It 'defaults the apply input to false and passes -Apply only when it is true' {
        $script:workflow | Should -Match '(?s)apply:.*?type: boolean.*?default: false'
        $script:workflow | Should -Match ([regex]::Escape("if ('`${{ inputs.apply }}' -eq 'true') { `$params['Apply'] = `$true }"))
    }

    It 'asks for issues: write and nothing else writable, using only the built-in token' {
        $script:workflow | Should -Match '(?m)^  issues: write\s*$'
        $script:workflow | Should -Match '(?m)^  contents: read\s*$'
        @([regex]::Matches($script:workflow, '(?m)^  [a-z-]+: write')).Count | Should -Be 1
        @([regex]::Matches($script:workflow, 'secrets\.([A-Za-z_]+)') | ForEach-Object { $_.Groups[1].Value } | Where-Object { $_ -cne 'GITHUB_TOKEN' }).Count | Should -Be 0
    }

    It 'never cancels a run in progress, which could leave half its writes made' {
        $script:workflow | Should -Match '(?m)^  cancel-in-progress: false\s*$'
    }
}
