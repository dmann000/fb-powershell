#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    tools/Test-PfbCapabilityMapMerge.ps1 against a fake gh: the gate in front of the Drift
    Issues workflow's push path.
.DESCRIPTION
    The verdict itself is tested in Tests/PfbDriftIssueTools.Tests.ps1. This file proves
    what only the shell can get wrong: the exact API call, the retry on an empty
    association, that a failed call throws instead of answering false, the output line the
    workflow branches on, and that a one-element JSON array still parses as one pull on
    Windows PowerShell 5.1 (where ConvertFrom-Json emits an array as a single object).

    THE FAKE gh IS A SCRIPT FILE, passed as -GhCommand, as in New-PfbDriftIssue.Tests.ps1.
    It logs each argv and answers call N with line N of a responses file (the last line
    repeats); a line reading FAIL exits 1.

    GITHUB_OUTPUT IS ALWAYS REDIRECTED. In CI it names the real step output of the Pester
    job, so every invocation points it at a fixture file and restores it afterwards.

    NOT EDITION-GATED: the script and its library are 5.1-compatible.
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:scriptPath = Join-Path (Join-Path $script:repoRoot 'tools') 'Test-PfbCapabilityMapMerge.ps1'
    $script:utf8 = New-Object System.Text.UTF8Encoding $false
    $script:sha = '0123456789abcdef0123456789abcdef01234567'

    $script:capPull = '[{"number":201,"merged_at":"2026-09-25T00:00:00Z","head":{"ref":"automated/update-api-capability-map","repo":{"full_name":"example/repo"}},"base":{"ref":"main"}}]'
    $script:forkPull = '[{"number":173,"merged_at":"2026-09-25T00:00:00Z","head":{"ref":"feat/backlog-scorer","repo":{"full_name":"someone/repo"}},"base":{"ref":"main"}}]'

    $script:fakeGhTemplate = @'
[System.IO.File]::AppendAllText('__LOG__', ((@($args) | ForEach-Object { [string]$_ }) -join "`t") + "`n")
$count = @([System.IO.File]::ReadAllLines('__LOG__') | Where-Object { $_ -ne '' }).Count
$responses = @([System.IO.File]::ReadAllLines('__RESPONSES__') | Where-Object { $_ -ne '' })
$line = $responses[[Math]::Min($count, $responses.Count) - 1]
if ($line -eq 'FAIL') { exit 1 }
$line
exit 0
'@

    function Build-TestGate {
        param([Parameter(Mandatory = $true)][string[]]$Response)
        $dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $dir
        $paths = @{
            Log       = Join-Path $dir 'gh.log'
            Responses = Join-Path $dir 'responses.txt'
            Output    = Join-Path $dir 'github-output.txt'
            Gh        = Join-Path $dir 'fake-gh.ps1'
        }
        [System.IO.File]::WriteAllText($paths.Log, '', $script:utf8)
        [System.IO.File]::WriteAllText($paths.Output, '', $script:utf8)
        [System.IO.File]::WriteAllText($paths.Responses, (($Response -join "`n") + "`n"), $script:utf8)
        [System.IO.File]::WriteAllText($paths.Gh, $script:fakeGhTemplate.Replace('__LOG__', $paths.Log).Replace('__RESPONSES__', $paths.Responses), $script:utf8)
        return $paths
    }

    # Returns the script's stdout lines. GITHUB_OUTPUT points at the fixture for the call.
    function Invoke-TestGate {
        param([hashtable]$Paths, [int]$Attempts = 3, [string]$Sha = $script:sha)
        $hadOutput = Test-Path -Path 'Env:GITHUB_OUTPUT'
        $savedOutput = $env:GITHUB_OUTPUT
        $env:GITHUB_OUTPUT = $Paths.Output
        try {
            @(& $script:scriptPath -Repo 'example/repo' -Sha $Sha -GhCommand $Paths.Gh -Attempts $Attempts -RetryDelaySeconds 0 6>$null)
        }
        finally {
            if ($hadOutput) { $env:GITHUB_OUTPUT = $savedOutput }
            else { Remove-Item -Path 'Env:GITHUB_OUTPUT' -ErrorAction SilentlyContinue }
        }
    }

    function Get-TestGhCall {
        param([hashtable]$Paths)
        @([System.IO.File]::ReadAllLines($Paths.Log) | Where-Object { $_ -ne '' })
    }
}

Describe 'Test-PfbCapabilityMapMerge.ps1' {
    It 'asks GitHub for the pull requests of exactly that commit, and answers true for the capability-map merge' {
        $paths = Build-TestGate -Response $script:capPull
        $out = @(Invoke-TestGate -Paths $paths)
        $out[-1] | Should -BeExactly 'true'
        $calls = @(Get-TestGhCall -Paths $paths)
        $calls.Count | Should -Be 1
        $calls[0] | Should -BeExactly "api`trepos/example/repo/commits/$($script:sha)/pulls"
    }

    It 'answers false for a feature merge, without retrying a non-empty answer' {
        $paths = Build-TestGate -Response $script:forkPull
        $out = @(Invoke-TestGate -Paths $paths)
        $out[-1] | Should -BeExactly 'false'
        @(Get-TestGhCall -Paths $paths).Count | Should -Be 1
    }

    It 'retries an empty association and accepts it once it appears' {
        $paths = Build-TestGate -Response '[]', '[]', $script:capPull
        $out = @(Invoke-TestGate -Paths $paths -Attempts 3)
        $out[-1] | Should -BeExactly 'true'
        @(Get-TestGhCall -Paths $paths).Count | Should -Be 3
    }

    It 'gives up after -Attempts empty answers and answers false' {
        $paths = Build-TestGate -Response '[]'
        $out = @(Invoke-TestGate -Paths $paths -Attempts 3)
        $out[-1] | Should -BeExactly 'false'
        @(Get-TestGhCall -Paths $paths).Count | Should -Be 3
    }

    It 'throws when gh fails, rather than answering false and skipping a release' {
        $paths = Build-TestGate -Response 'FAIL'
        { Invoke-TestGate -Paths $paths } | Should -Throw '*failed with exit code 1*'
    }

    It 'appends the verdict to GITHUB_OUTPUT' {
        $paths = Build-TestGate -Response $script:capPull
        $null = Invoke-TestGate -Paths $paths
        [System.IO.File]::ReadAllText($paths.Output) | Should -BeExactly "is_capability_map_merge=true`n"
    }

    It 'rejects a SHA that is not 40 lowercase hex characters' {
        $paths = Build-TestGate -Response $script:capPull
        { Invoke-TestGate -Paths $paths -Sha 'HEAD' } | Should -Throw -ExpectedMessage "*parameter 'Sha'*"
        @(Get-TestGhCall -Paths $paths).Count | Should -Be 0
    }
}
