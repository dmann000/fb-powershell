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

    # The fake container paths must be PLATFORM-NATIVE, and both halves of that matter. A
    # hardcoded 'C:\repo\Tests' broke the ubuntu and macos legs two ways at once: Join-Path
    # throws DriveNotFoundException for a drive letter that does not exist, and even as a bare
    # literal, Split-Path -Leaf does not treat '\' as a separator off Windows -- so the gate
    # would key attribution on the whole string and every leaf lookup would silently miss.
    # Building from the temp path keeps the root real enough for Join-Path on every platform
    # while staying obviously fake; nothing here is ever created on disk.
    $script:fakeTestsDir = Join-Path (Join-Path ([System.IO.Path]::GetTempPath()) 'pfb-fake-repo') 'Tests'

    # One entry per test FILE, mirroring $Result.Containers. The .Item shape matters: on a real
    # run it is a FileInfo, and the gate reads .FullName off it, so the stand-in carries a
    # FullName rather than a bare string.
    function New-FakeContainer {
        param(
            [string]$File,
            [int]$Passed = 0, [int]$Failed = 0, [int]$Skipped = 0, [int]$NotRun = 0,
            [string]$Dir = $script:fakeTestsDir
        )
        return [pscustomobject]@{
            Item         = [pscustomobject]@{ FullName = (Join-Path $Dir $File) }
            PassedCount  = $Passed
            FailedCount  = $Failed
            SkippedCount = $Skipped
            NotRunCount  = $NotRun
        }
    }

    function New-FakeResult {
        param(
            [object[]]$Tests,
            [object[]]$Containers,
            [int]$Passed = 0, [int]$Failed = 0, [int]$Skipped = 0, [int]$NotRun = 0
        )
        return [pscustomobject]@{
            Tests        = $Tests
            Containers   = $Containers
            PassedCount  = $Passed
            FailedCount  = $Failed
            SkippedCount = $Skipped
            NotRunCount  = $NotRun
        }
    }

    # The two Describes every fake run needs in order to clear assertion 1, so that assertion
    # 2's own failures are the only thing under test.
    function New-HealthyDescribeTests {
        return @(
            (New-FakeTest -Path @('Block A', 'does a thing') -Result 'Passed'),
            (New-FakeTest -Path @('Block B', 'does another') -Result 'Passed')
        )
    }

    $script:baselineFile = Join-Path $TestDrive 'baseline.psd1'
    @'
@{
    pwsh7 = @{
        ExpectedSkips = @{
            'Gated.Tests.ps1' = 3
        }
        RequiredDescribes = @(
            'Block A'
            'Block B'
        )
    }
    winps51 = @{
        ExpectedSkips = @{
            'Gated.Tests.ps1' = 50
        }
        RequiredDescribes = @('Block A')
    }
}
'@ | Set-Content -Path $baselineFile -Encoding UTF8
}

Describe 'Assert-PfbTestCoverage (issue #63 coverage gate)' {

    It 'passes when every required Describe ran and every file matches its expected skip count' {
        $result = New-FakeResult -Passed 2 -Skipped 3 -Tests (New-HealthyDescribeTests) -Containers @(
            (New-FakeContainer -File 'Ungated.Tests.ps1' -Passed 2),
            (New-FakeContainer -File 'Gated.Tests.ps1' -Skipped 3)
        )
        { & $gateScript -Result $result -Edition pwsh7 -BaselinePath $baselineFile } | Should -Not -Throw
    }

    It 'FAILS when a required Describe contributed no executed tests at all' {
        # THE case assertion 1 exists for, and the one a skip count cannot see. A Describe
        # filtered out of the run, or guarded false at BeforeAll time, contributes NEITHER a
        # skip NOR a pass. Note the per-file numbers here are all correct: a skip-count-only
        # gate reads this run as perfectly healthy while an entire required block is absent.
        $result = New-FakeResult -Passed 1 -Skipped 3 -Tests @(
            (New-FakeTest -Path @('Block A', 'does a thing') -Result 'Passed')
        ) -Containers @(
            (New-FakeContainer -File 'Ungated.Tests.ps1' -Passed 1),
            (New-FakeContainer -File 'Gated.Tests.ps1' -Skipped 3)
        )
        { & $gateScript -Result $result -Edition pwsh7 -BaselinePath $baselineFile } |
            Should -Throw -ExpectedMessage '*coverage gate failed*'
    }

    It 'FAILS when a required Describe is present but every test in it skipped' {
        $result = New-FakeResult -Passed 1 -Skipped 4 -Tests @(
            (New-FakeTest -Path @('Block A', 'does a thing') -Result 'Passed'),
            (New-FakeTest -Path @('Block B', 'does another') -Result 'Skipped')
        ) -Containers @(
            (New-FakeContainer -File 'Ungated.Tests.ps1' -Passed 1 -Skipped 1),
            (New-FakeContainer -File 'Gated.Tests.ps1' -Skipped 3)
        )
        { & $gateScript -Result $result -Edition pwsh7 -BaselinePath $baselineFile } |
            Should -Throw -ExpectedMessage '*coverage gate failed*'
    }

    It 'FAILS when a declared file skips MORE than its expected count, and names that file' {
        $result = New-FakeResult -Passed 2 -Skipped 9 -Tests (New-HealthyDescribeTests) -Containers @(
            (New-FakeContainer -File 'Ungated.Tests.ps1' -Passed 2),
            (New-FakeContainer -File 'Gated.Tests.ps1' -Skipped 9)
        )
        { & $gateScript -Result $result -Edition pwsh7 -BaselinePath $baselineFile } |
            Should -Throw -ExpectedMessage '*coverage gate failed*'
    }

    It 'FAILS when a declared file skips FEWER than its expected count' {
        # The direction a CEILING structurally cannot see, and the reason issue #132 replaced
        # one. A file quietly losing skipped tests is movement nobody decided on: either those
        # tests now run (good, and the number should say so) or they stopped existing (bad).
        # Under the old global ceiling both readings passed silently, and the unrecorded drop
        # then became someone else's unattributable red once the total drifted back up.
        $result = New-FakeResult -Passed 2 -Skipped 1 -Tests (New-HealthyDescribeTests) -Containers @(
            (New-FakeContainer -File 'Ungated.Tests.ps1' -Passed 2),
            (New-FakeContainer -File 'Gated.Tests.ps1' -Skipped 1)
        )
        { & $gateScript -Result $result -Edition pwsh7 -BaselinePath $baselineFile } |
            Should -Throw -ExpectedMessage '*coverage gate failed*'
    }

    It 'FAILS when an UNDECLARED file skips anything at all' {
        # A new test file arriving with PS7-gated Describes. Its skips must be declared, so the
        # next reader can see whether the gating was deliberate.
        $result = New-FakeResult -Passed 2 -Skipped 5 -Tests (New-HealthyDescribeTests) -Containers @(
            (New-FakeContainer -File 'Ungated.Tests.ps1' -Passed 2),
            (New-FakeContainer -File 'Gated.Tests.ps1' -Skipped 3),
            (New-FakeContainer -File 'BrandNew.Tests.ps1' -Skipped 2)
        )
        { & $gateScript -Result $result -Edition pwsh7 -BaselinePath $baselineFile } |
            Should -Throw -ExpectedMessage '*coverage gate failed*'
    }

    It 'FAILS when a file runs EMPTY, contributing neither an executed nor a skipped test' {
        # The issue-#63 shape below the granularity RequiredDescribes can reach: a throwing
        # top-level BeforeAll, or a `#requires` the runner does not satisfy. Such a file still
        # appears in .Containers with every count zero, which is the only reason this is
        # detectable -- it contributes NO entries to .Tests at all.
        $result = New-FakeResult -Passed 2 -Skipped 3 -Tests (New-HealthyDescribeTests) -Containers @(
            (New-FakeContainer -File 'Ungated.Tests.ps1' -Passed 2),
            (New-FakeContainer -File 'Gated.Tests.ps1' -Skipped 3),
            (New-FakeContainer -File 'DiedInBeforeAll.Tests.ps1')
        )
        { & $gateScript -Result $result -Edition pwsh7 -BaselinePath $baselineFile } |
            Should -Throw -ExpectedMessage '*coverage gate failed*'
    }

    It 'FAILS when a declared file did not run at all, rather than treating it as a stale entry' {
        # A declared file dropping out of discovery is lost coverage. The tempting reading --
        # "the entry is stale, delete it" -- is the one that turns a regression into a tidy-up.
        $result = New-FakeResult -Passed 2 -Tests (New-HealthyDescribeTests) -Containers @(
            (New-FakeContainer -File 'Ungated.Tests.ps1' -Passed 2)
        )
        { & $gateScript -Result $result -Edition pwsh7 -BaselinePath $baselineFile } |
            Should -Throw -ExpectedMessage '*coverage gate failed*'
    }

    It 'counts NotRun toward a file''s number, not just Skipped' {
        # Pester reports a block skipped at discovery time as NotRun rather than Skipped.
        # Counting only one of the two would leave half the movement invisible. Here the two
        # sum to the expected 3, so this run must PASS -- which is what proves NotRun is being
        # counted rather than merely tolerated.
        $result = New-FakeResult -Passed 2 -Skipped 1 -NotRun 2 -Tests (New-HealthyDescribeTests) -Containers @(
            (New-FakeContainer -File 'Ungated.Tests.ps1' -Passed 2),
            (New-FakeContainer -File 'Gated.Tests.ps1' -Skipped 1 -NotRun 2)
        )
        { & $gateScript -Result $result -Edition pwsh7 -BaselinePath $baselineFile } | Should -Not -Throw
    }

    It 'FAILS when per-file attribution does not reconcile with the run total' {
        # Not a coverage assertion -- a check on the walk itself. If the containers do not
        # account for every skip the run reported, then every per-file verdict above was
        # judging a partial picture, and a green result would be meaningless.
        $result = New-FakeResult -Passed 2 -Skipped 40 -Tests (New-HealthyDescribeTests) -Containers @(
            (New-FakeContainer -File 'Ungated.Tests.ps1' -Passed 2),
            (New-FakeContainer -File 'Gated.Tests.ps1' -Skipped 3)
        )
        { & $gateScript -Result $result -Edition pwsh7 -BaselinePath $baselineFile } |
            Should -Throw -ExpectedMessage '*coverage gate failed*'
    }

    It 'FAILS loudly when the result carries no Containers at all, rather than passing vacuously' {
        # ANTI-VACUITY. An empty .Containers is the false-zero shape: nothing skipped anywhere,
        # every rail satisfied, gate green, gate useless.
        $result = New-FakeResult -Passed 2 -Tests (New-HealthyDescribeTests) -Containers @()
        { & $gateScript -Result $result -Edition pwsh7 -BaselinePath $baselineFile } |
            Should -Throw -ExpectedMessage '*coverage gate failed*'
    }

    It 'FAILS when two containers share a leaf name, since attribution by leaf is then unsound' {
        # Tests/ is flat today and no two *.Tests.ps1 files share a leaf, which is what makes
        # the leaf a safe key. If a subdirectory ever reintroduces a collision, one file's
        # numbers would mask another's -- so the gate says so instead of overwriting silently.
        $result = New-FakeResult -Passed 2 -Skipped 3 -Tests (New-HealthyDescribeTests) -Containers @(
            (New-FakeContainer -File 'Ungated.Tests.ps1' -Passed 2),
            (New-FakeContainer -File 'Gated.Tests.ps1' -Skipped 3),
            # Same leaf, different parent -- so -Dir, not a hardcoded literal, or the collision
            # this test exists to provoke never happens off Windows.
            (New-FakeContainer -File 'Gated.Tests.ps1' -Dir (Join-Path $script:fakeTestsDir 'Nested'))
        )
        { & $gateScript -Result $result -Edition pwsh7 -BaselinePath $baselineFile } |
            Should -Throw -ExpectedMessage '*coverage gate failed*'
    }

    It 'applies the per-edition block, so winps51 accepts a count pwsh7 rejects' {
        # The editions differ by roughly 300 skips by design: every tooling Describe is
        # PS7-gated. A single shared map would be either a permanent false red on 5.1 or
        # useless on 7.
        $result = New-FakeResult -Passed 1 -Skipped 50 -Tests @(
            (New-FakeTest -Path @('Block A', 'does a thing') -Result 'Passed')
        ) -Containers @(
            (New-FakeContainer -File 'Ungated.Tests.ps1' -Passed 1),
            (New-FakeContainer -File 'Gated.Tests.ps1' -Skipped 50)
        )
        { & $gateScript -Result $result -Edition winps51 -BaselinePath $baselineFile } | Should -Not -Throw
        { & $gateScript -Result $result -Edition pwsh7 -BaselinePath $baselineFile } |
            Should -Throw -ExpectedMessage '*coverage gate failed*'
    }

    It 'throws a clear error when the baseline file is missing rather than passing vacuously' {
        $result = New-FakeResult -Passed 1 -Tests @() -Containers @()
        { & $gateScript -Result $result -Edition pwsh7 -BaselinePath (Join-Path $TestDrive 'nope.psd1') } |
            Should -Throw -ExpectedMessage '*not found*'
    }

    It 'throws when an edition block has no ExpectedSkips map at all' {
        # A block carrying only RequiredDescribes would silently gate nothing on the skip axis.
        # That is the #63 shape applied to the gate's own configuration, so it is a hard throw
        # rather than a violation.
        $bad = Join-Path $TestDrive 'no-expected-skips.psd1'
        @'
@{
    pwsh7   = @{ RequiredDescribes = @('Block A') }
    winps51 = @{ RequiredDescribes = @('Block A') }
}
'@ | Set-Content -Path $bad -Encoding UTF8
        $result = New-FakeResult -Passed 1 -Tests @(
            (New-FakeTest -Path @('Block A', 'does a thing') -Result 'Passed')
        ) -Containers @((New-FakeContainer -File 'Ungated.Tests.ps1' -Passed 1))
        { & $gateScript -Result $result -Edition pwsh7 -BaselinePath $bad } |
            Should -Throw -ExpectedMessage '*ExpectedSkips*'
    }
}

Describe 'coverage-baseline.psd1 (the real one)' {
    It 'parses, and defines both editions with a non-empty skip map and a non-empty allowlist' {
        $real = Import-PowerShellDataFile -Path (Join-Path $repoRoot 'Tests/coverage-baseline.psd1')
        foreach ($edition in @('pwsh7', 'winps51')) {
            $real[$edition] | Should -Not -BeNullOrEmpty -Because "$edition must have a baseline block"
            $real[$edition].ExpectedSkips | Should -Not -BeNullOrEmpty -Because "$edition must declare a per-file expected-skip map (issue #132); a block without one gates nothing on the skip axis"
            @($real[$edition].RequiredDescribes).Count | Should -BeGreaterThan 0 -Because 'an empty allowlist is a gate that checks nothing'
        }
    }

    It 'declares no MaxSkipped, in either edition' {
        # Issue #132 removed the global ceiling because its headroom converted an attributable
        # red into an unattributable one. A key left or reinstated here reads as configuration
        # the gate honours, and nothing does -- so it would be a silent no-op that looks like
        # a second layer of protection. Fail rather than ignore it.
        $real = Import-PowerShellDataFile -Path (Join-Path $repoRoot 'Tests/coverage-baseline.psd1')
        foreach ($edition in @('pwsh7', 'winps51')) {
            $real[$edition].ContainsKey('MaxSkipped') |
                Should -BeFalse -Because "the $edition block still declares MaxSkipped, which the gate no longer reads (issue #132). Per-file ExpectedSkips replaced it; a leftover key is a no-op masquerading as a gate."
        }
    }

    It 'names only test files that actually exist in Tests/' {
        # The static half of the gate's own runtime check. A renamed or deleted test file
        # leaving a stale entry behind would red CI for a reason that reads as mysterious, and
        # this catches it locally, on a scoped run, before it costs a CI cycle.
        $real = Import-PowerShellDataFile -Path (Join-Path $repoRoot 'Tests/coverage-baseline.psd1')
        foreach ($edition in @('pwsh7', 'winps51')) {
            foreach ($file in @($real[$edition].ExpectedSkips.Keys)) {
                Test-Path -Path (Join-Path $repoRoot (Join-Path 'Tests' $file)) |
                    Should -BeTrue -Because "the $edition ExpectedSkips map names a test file that does not exist: '$file'"
            }
        }
    }

    It 'declares only positive counts, since a zero entry is indistinguishable from omitting it' {
        $real = Import-PowerShellDataFile -Path (Join-Path $repoRoot 'Tests/coverage-baseline.psd1')
        foreach ($edition in @('pwsh7', 'winps51')) {
            foreach ($file in @($real[$edition].ExpectedSkips.Keys)) {
                [int]$real[$edition].ExpectedSkips[$file] |
                    Should -BeGreaterThan 0 -Because "the $edition entry for '$file' is not positive; an undeclared file is already required to skip nothing, so a zero entry only adds a line to maintain"
            }
        }
    }

    It 'registers the ungated value-enum citation guard in BOTH editions' {
        # The reverse direction of the check below, for one block that needs it. The
        # citation guard in Build-PfbValueEnumMap.Tests.ps1 carries no -Skip and reads only
        # committed .ps1 files, so it must contribute executed tests on every leg. If it is
        # filtered out, renamed, or its BeforeAll starts throwing silently, it contributes
        # neither a pass nor a skip -- a skip count cannot see that, and the build stays green
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
