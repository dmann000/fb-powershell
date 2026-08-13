#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Unit tests for scripts/Assert-PfbTestCoverage.ps1 -- the issue-#63 coverage gate.
.DESCRIPTION
    The gate is what turns the NEXT silent coverage hole into a red build, so a vacuous gate
    would be worse than no gate: it would look like protection while providing none. That is
    the same failure shape as issue #63 itself, so these tests exist to prove the gate actually
    fails when it should.

    The gate takes a result OBJECT rather than running Pester, so a hand-built stand-in
    exercises it fully -- no real suite run, no dependency on the spec cache, and no risk of
    invoking the aggregate suite (which exceeds the 600s tool-call cap; see the
    run-pester-tests skill).

    UNGATED, like the other #63 guards: the gate runs on both editions, so its tests must too.

    5.1 CONSTRAINT: no ternaries, no ??, no ConvertFrom-Json -Depth.
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:gateScript = Join-Path $repoRoot 'scripts/Assert-PfbTestCoverage.ps1'

    function New-FakeTest {
        param([string[]]$Path, [string]$Result)
        return [pscustomobject]@{ Path = $Path; Result = $Result }
    }

    function New-FakeResult {
        param([object[]]$Tests, [int]$Passed = 0, [int]$Failed = 0, [int]$Skipped = 0, [int]$NotRun = 0)
        return [pscustomobject]@{
            Tests        = $Tests
            PassedCount  = $Passed
            FailedCount  = $Failed
            SkippedCount = $Skipped
            NotRunCount  = $NotRun
        }
    }

    $script:baselineFile = Join-Path $TestDrive 'baseline.psd1'
    @'
@{
    pwsh7 = @{
        MaxSkipped = 5
        RequiredDescribes = @(
            'Block A'
            'Block B'
        )
    }
    winps51 = @{
        MaxSkipped = 100
        RequiredDescribes = @('Block A')
    }
}
'@ | Set-Content -Path $baselineFile -Encoding UTF8
}

Describe 'Assert-PfbTestCoverage (issue #63 coverage gate)' {
    It 'passes when every required Describe ran and the skip count is under the ceiling' {
        $result = New-FakeResult -Passed 2 -Skipped 1 -Tests @(
            (New-FakeTest -Path @('Block A', 'does a thing') -Result 'Passed'),
            (New-FakeTest -Path @('Block B', 'does another') -Result 'Passed')
        )
        { & $gateScript -Result $result -Edition pwsh7 -BaselinePath $baselineFile } | Should -Not -Throw
    }

    It 'FAILS when a required Describe contributed no executed tests at all' {
        # THE case this gate exists for, and the one a skip ceiling cannot see. A Describe
        # filtered out of the run, or guarded false at BeforeAll time, contributes NEITHER a
        # skip NOR a pass. Note SkippedCount is 0 here: a ceiling-only gate reads this run as
        # perfectly healthy while an entire required block is silently absent.
        $result = New-FakeResult -Passed 1 -Skipped 0 -Tests @(
            (New-FakeTest -Path @('Block A', 'does a thing') -Result 'Passed')
        )
        { & $gateScript -Result $result -Edition pwsh7 -BaselinePath $baselineFile } |
            Should -Throw -ExpectedMessage '*coverage gate failed*'
    }

    It 'FAILS when a required Describe is present but every test in it skipped' {
        $result = New-FakeResult -Passed 1 -Skipped 1 -Tests @(
            (New-FakeTest -Path @('Block A', 'does a thing') -Result 'Passed'),
            (New-FakeTest -Path @('Block B', 'does another') -Result 'Skipped')
        )
        { & $gateScript -Result $result -Edition pwsh7 -BaselinePath $baselineFile } |
            Should -Throw -ExpectedMessage '*coverage gate failed*'
    }

    It 'FAILS when the skip count exceeds the ceiling, even with every required Describe green' {
        $result = New-FakeResult -Passed 2 -Skipped 6 -Tests @(
            (New-FakeTest -Path @('Block A', 'does a thing') -Result 'Passed'),
            (New-FakeTest -Path @('Block B', 'does another') -Result 'Passed')
        )
        { & $gateScript -Result $result -Edition pwsh7 -BaselinePath $baselineFile } |
            Should -Throw -ExpectedMessage '*coverage gate failed*'
    }

    It 'counts NotRun toward the skip ceiling, not just Skipped' {
        # Pester reports a block skipped at discovery time as NotRun rather than Skipped.
        # Counting only one of the two would leave half the regression invisible.
        $result = New-FakeResult -Passed 2 -Skipped 3 -NotRun 3 -Tests @(
            (New-FakeTest -Path @('Block A', 'does a thing') -Result 'Passed'),
            (New-FakeTest -Path @('Block B', 'does another') -Result 'Passed')
        )
        { & $gateScript -Result $result -Edition pwsh7 -BaselinePath $baselineFile } |
            Should -Throw -ExpectedMessage '*coverage gate failed*'
    }

    It 'applies the per-edition block, so winps51 tolerates what pwsh7 rejects' {
        # The editions differ by roughly 200 skips by design: every tooling Describe is
        # PS7-gated. A single shared ceiling would be either a permanent false red on 5.1 or
        # useless on 7.
        $result = New-FakeResult -Passed 1 -Skipped 50 -Tests @(
            (New-FakeTest -Path @('Block A', 'does a thing') -Result 'Passed')
        )
        { & $gateScript -Result $result -Edition winps51 -BaselinePath $baselineFile } | Should -Not -Throw
        { & $gateScript -Result $result -Edition pwsh7 -BaselinePath $baselineFile } |
            Should -Throw -ExpectedMessage '*coverage gate failed*'
    }

    It 'throws a clear error when the baseline file is missing rather than passing vacuously' {
        $result = New-FakeResult -Passed 1 -Tests @()
        { & $gateScript -Result $result -Edition pwsh7 -BaselinePath (Join-Path $TestDrive 'nope.psd1') } |
            Should -Throw -ExpectedMessage '*not found*'
    }
}

Describe 'coverage-baseline.psd1 (the real one)' {
    It 'parses, and defines both editions with a ceiling and a non-empty allowlist' {
        $real = Import-PowerShellDataFile -Path (Join-Path $repoRoot 'Tests/coverage-baseline.psd1')
        foreach ($edition in @('pwsh7', 'winps51')) {
            $real[$edition] | Should -Not -BeNullOrEmpty -Because "$edition must have a baseline block"
            $real[$edition].MaxSkipped | Should -BeGreaterOrEqual 0
            @($real[$edition].RequiredDescribes).Count | Should -BeGreaterThan 0 -Because 'an empty allowlist is a gate that checks nothing'
        }
    }

    It 'registers the ungated value-enum citation guard in BOTH editions' {
        # The reverse direction of the check below, for one block that needs it. The
        # citation guard in Build-PfbValueEnumMap.Tests.ps1 carries no -Skip and reads only
        # committed .ps1 files, so it must contribute executed tests on every leg. If it is
        # filtered out, renamed, or its BeforeAll starts throwing silently, it contributes
        # neither a pass nor a skip -- MaxSkipped cannot see that, and the build stays green
        # with the guard gone. Only RequiredDescribes catches it, so the entry is part of the
        # guard, not bookkeeping.
        $real = Import-PowerShellDataFile -Path (Join-Path $repoRoot 'Tests/coverage-baseline.psd1')
        $name = 'Build-PfbValueEnumMap: hand-written ValidateSet citations'
        foreach ($edition in @('pwsh7', 'winps51')) {
            @($real[$edition].RequiredDescribes) -contains $name |
                Should -BeTrue -Because "the $edition allowlist must require the ungated Describe '$name'"
        }
    }

    It 'names only Describe blocks that actually exist in Tests/' {
        # A typo in an allowlist entry, or a Describe someone renamed, would red the build
        # forever for the wrong reason. Catch both here rather than in CI.
        $allSource = (Get-ChildItem -Path (Join-Path $repoRoot 'Tests') -Filter '*.Tests.ps1' |
            ForEach-Object { Get-Content -Path $_.FullName -Raw }) -join "`n"
        $real = Import-PowerShellDataFile -Path (Join-Path $repoRoot 'Tests/coverage-baseline.psd1')
        foreach ($edition in @('pwsh7', 'winps51')) {
            foreach ($name in @($real[$edition].RequiredDescribes)) {
                # .Contains, not -like: a wildcard pattern treats ` as an escape character, and
                # these Describe names contain characters -like would misread.
                $allSource.Contains($name) | Should -BeTrue -Because "the $edition allowlist names a Describe that no test file defines: '$name'"
            }
        }
    }
}
