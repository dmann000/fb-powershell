<#
.SYNOPSIS
    Fails the build when a Pester run silently lost coverage. Issue #63.
.DESCRIPTION
    The tooling tests gate themselves on tools/specs/, a gitignored build cache. On a bare
    runner they all reported "skipped", the job reported "success", and the coverage loss was
    invisible in the run summary. Restoring the cache fixes today's hole; this script is what
    makes the NEXT one a red build instead of a silent one.

    Two independent assertions, because either alone has a gap:

      1. Required-Describe allowlist -- catches a NAMED Describe that vanishes from the result
         tree entirely. These blocks skip GRACEFULLY: when their guard evaluates false at
         BeforeAll time, or the file is filtered out of a run, they contribute NEITHER a skip
         NOR a pass. A skip count cannot see that, and a green summary is then
         indistinguishable from a silently-absent assertion -- the same failure shape as #63,
         one level down.
      2. Per-file skip attribution (issue #132) -- an EXACT expected skip count per test file,
         plus three rails around it: no file may run empty, no undeclared file may skip, and
         a declared file that stops running at all is a violation rather than a tidy-up.

    Assertion 2 replaced a single global MaxSkipped ceiling per edition. The ceiling's headroom
    turned out to be the defect and not the mitigation -- see the long note at assertion 2 and
    issue #132 -- so the numbers here are pinned, and movement is attributed to a file.

    Takes a result OBJECT rather than running Pester itself, so it is testable with a
    hand-built stand-in and needs neither a real suite run nor the spec cache.

    Lives in scripts/, not tools/: .gitignore:46 ignores tools/ wholesale, so a new file there
    would be silently untracked.

    5.1 CONSTRAINT: this runs under Windows PowerShell 5.1 as well as pwsh 7. No ternaries,
    no ??, no ConvertFrom-Json -Depth.

    Result shape verified against Pester 6.0.0 and 6.0.1 on both editions: $Result.Tests is a
    flat list, each entry has .Path (a List whose [0] is the top-level Describe name) and a
    .Result string; the run carries PassedCount/FailedCount/SkippedCount/NotRunCount.
    $Result.Containers is one entry per test FILE, each with .Item (a FileInfo, so .FullName)
    and its own PassedCount/FailedCount/SkippedCount/NotRunCount.

    The two collections disagree in a way assertion 2 depends on: a file killed by `#requires`
    contributes NOTHING to .Tests but still appears in .Containers with all four counts zero.
    Probed directly on both editions rather than assumed.
.PARAMETER Result
    The object returned by Invoke-Pester -PassThru.
.PARAMETER Edition
    Which baseline block to apply: 'pwsh7' or 'winps51'. This selects the BASELINE, not the
    interpreter -- the interpreter is whichever host is already running this script.
.PARAMETER BaselinePath
    Defaults to Tests/coverage-baseline.psd1 relative to the repo root.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][object]$Result,
    [Parameter(Mandatory)][ValidateSet('pwsh7', 'winps51')][string]$Edition,
    [string]$BaselinePath
)

$ErrorActionPreference = 'Stop'

if (-not $BaselinePath) {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $BaselinePath = Join-Path $repoRoot 'Tests/coverage-baseline.psd1'
}
if (-not (Test-Path $BaselinePath)) {
    throw "Coverage baseline not found at $BaselinePath."
}

$baseline = Import-PowerShellDataFile -Path $BaselinePath
$editionBaseline = $baseline[$Edition]
if (-not $editionBaseline) {
    throw "Coverage baseline has no '$Edition' block. Present: $($baseline.Keys -join ', ')."
}

$allTests = @($Result.Tests)
$violations = New-Object System.Collections.Generic.List[string]
$summaryLines = New-Object System.Collections.Generic.List[string]

$summaryLines.Add("### Test coverage gate -- $Edition")
$summaryLines.Add('')

# --- Assertion 1: required Describes actually executed -------------------------------------
$summaryLines.Add('| Required top-level Describe | Ran | Skipped |')
$summaryLines.Add('|---|---:|---:|')

foreach ($required in @($editionBaseline.RequiredDescribes)) {
    $blockTests = @($allTests | Where-Object { @($_.Path).Count -gt 0 -and $_.Path[0] -eq $required })
    $ran = @($blockTests | Where-Object { $_.Result -eq 'Passed' -or $_.Result -eq 'Failed' }).Count
    $skipped = @($blockTests | Where-Object { $_.Result -eq 'Skipped' -or $_.Result -eq 'NotRun' }).Count

    $marker = 'OK'
    if ($ran -lt 1) {
        $marker = 'MISSING'
        $violations.Add("Required Describe contributed $ran executed tests (and $skipped skipped/not-run): '$required'")
    }
    $summaryLines.Add("| ``$required`` | $ran ($marker) | $skipped |")
}

# --- Assertion 2: per-file skip attribution (issue #132) -----------------------------------
# Replaces the global MaxSkipped ceiling. That ceiling carried deliberate headroom, and the
# headroom was the defect rather than the mitigation: it silently absorbed skip movement until
# some later, unrelated PR crossed the line, and then billed that PR for the whole accumulated
# delta with no signal saying which part was its own. It happened exactly once and the
# arithmetic was exact -- a 5.1 run measured 292 against a ceiling of 268, and 6 of the +40
# belonged to #120 two days earlier, which had passed on slack. See issue #132.
#
# Per-file numbers are EXACT, not ceilings. Any movement -- up or down -- reds the PR that
# caused it and names the file, which is the whole point. A file that legitimately gains or
# loses skipped tests updates its own line in the same diff.
#
# Attribution comes from $Result.Containers, NOT from $Result.Tests, and the difference is
# load-bearing: a file whose `#requires` stops it before discovery contributes NO entries to
# .Tests at all, but still appears in .Containers with every count at zero. That is the
# issue-#63 shape, and .Containers is the only place it is visible. Verified on Pester 6.0.1
# under pwsh 7 and 6.0.0 under Windows PowerShell 5.1.
$expectedSkips = $editionBaseline.ExpectedSkips
if ($null -eq $expectedSkips) {
    throw "Coverage baseline block '$Edition' has no ExpectedSkips map. Issue #132 replaced MaxSkipped with a per-file map; a block carrying neither gates nothing."
}

$containers = @($Result.Containers)

# ANTI-VACUITY, before anything reads the walk. Without this, an empty or absent .Containers
# makes every 'declared file is missing' check fire at once -- a wall of confusing reds whose
# real cause is that the walk found nothing. Fail once, saying so.
if ($containers.Count -lt 1) {
    $violations.Add("The Pester result carries no Containers, so per-file skip attribution could not run at all. Every assertion below would be meaningless. Check the Pester version and that Run.PassThru was set.")
}

# Flatten to leaf file name -> counts. Tests/ is flat and no two *.Tests.ps1 files share a
# leaf name (checked: 199 files, 0 duplicates), so the leaf is a safe key and keeps the
# baseline free of runner-specific absolute paths.
$observed = @{}
$attributedSkips = 0
foreach ($container in $containers) {
    $name = ''
    if ($container.Item) {
        if ($container.Item.FullName) { $name = Split-Path -Leaf $container.Item.FullName }
        else { $name = Split-Path -Leaf ([string]$container.Item) }
    }
    if (-not $name) { continue }

    $executed = [int]$container.PassedCount + [int]$container.FailedCount
    $skipped = [int]$container.SkippedCount + [int]$container.NotRunCount
    $attributedSkips = $attributedSkips + $skipped

    if ($observed.ContainsKey($name)) {
        # Same leaf twice means the leaf-name key is no longer unique, which would let one
        # file's numbers mask another's. Say so rather than silently overwriting.
        $violations.Add("Two containers share the leaf name '$name', so per-file attribution by leaf name is no longer sound. Key the baseline by repo-relative path instead.")
        continue
    }
    $observed[$name] = @{ Executed = $executed; Skipped = $skipped }
}

# --- 2a: no container ran empty ------------------------------------------------------------
# The issue-#63 shape, one level below RequiredDescribes. That allowlist catches a named
# Describe vanishing, but only for the blocks someone remembered to list. This catches ANY
# test file that contributed neither an executed nor a skipped test -- a throwing top-level
# BeforeAll, or a `#requires` the runner does not satisfy. Green and non-vacuous today: all
# 199 files contribute something on all four CI legs.
foreach ($name in ($observed.Keys | Sort-Object)) {
    if ($observed[$name].Executed -lt 1 -and $observed[$name].Skipped -lt 1) {
        $violations.Add("Test file '$name' contributed no tests at all -- neither executed nor skipped. Its BeforeAll threw, or a #requires stopped it before discovery. This is the issue-#63 shape: the run stays green while the file's assertions silently do not exist.")
    }
}

# --- 2b: declared files match exactly, and are still present -------------------------------
$summaryLines.Add('')
$summaryLines.Add('| Test file | Skipped | Expected | |')
$summaryLines.Add('|---|---:|---:|---|')

foreach ($name in (@($expectedSkips.Keys) | Sort-Object)) {
    $expected = [int]$expectedSkips[$name]
    if (-not $observed.ContainsKey($name)) {
        $violations.Add("ExpectedSkips declares '$name' = $expected, but no such test file ran. Either the file was renamed or deleted and this entry is stale, or it dropped out of discovery -- which is lost coverage, not a tidy-up.")
        $summaryLines.Add("| ``$name`` | -- | $expected | ABSENT |")
        continue
    }
    $actual = $observed[$name].Skipped
    $marker = 'OK'
    if ($actual -ne $expected) {
        $marker = 'MOVED'
        $delta = $actual - $expected
        $sign = '+'
        if ($delta -lt 0) { $sign = '' }
        $violations.Add("'$name' skipped $actual tests, expected exactly $expected ($sign$delta). If that movement is correct -- a PS7-gated Describe added or removed -- update this file's entry in Tests/coverage-baseline.psd1 in the same diff. If it is not, coverage moved without anyone deciding to move it.")
    }
    $summaryLines.Add("| ``$name`` | $actual | $expected | $marker |")
}

# --- 2c: nothing skips that has not declared it --------------------------------------------
foreach ($name in ($observed.Keys | Sort-Object)) {
    if ($observed[$name].Skipped -lt 1) { continue }
    if ($expectedSkips.ContainsKey($name)) { continue }
    $violations.Add("'$name' skipped $($observed[$name].Skipped) tests but is not declared in the $Edition ExpectedSkips map. A new file that skips must say so, and say why in the comment beside it.")
    $summaryLines.Add("| ``$name`` | $($observed[$name].Skipped) | (undeclared) | UNDECLARED |")
}

# --- 2d: the walk saw every skip the run reported ------------------------------------------
# Reconciliation, not a coverage assertion. If per-container skips do not sum to the run's own
# total, the walk missed a container and 2a-2c were all judging an incomplete picture.
$skippedTotal = [int]$Result.SkippedCount + [int]$Result.NotRunCount
if ($containers.Count -ge 1 -and $attributedSkips -ne $skippedTotal) {
    $violations.Add("Per-file attribution accounts for $attributedSkips skipped/not-run tests, but the run reports $skippedTotal. The container walk is incomplete, so every per-file verdict above is judging a partial picture.")
}

$summaryLines.Add('')
$summaryLines.Add("Skipped + not-run: **$skippedTotal**, attributed across $($observed.Count) files. Passed: $($Result.PassedCount). Failed: $($Result.FailedCount).")

if ($env:GITHUB_STEP_SUMMARY) {
    ($summaryLines -join [Environment]::NewLine) | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append
}
foreach ($line in $summaryLines) { Write-Host $line }

if ($violations.Count -gt 0) {
    Write-Host ''
    Write-Host 'COVERAGE GATE FAILED (issue #63):'
    foreach ($v in $violations) { Write-Host "  - $v" }
    throw "Test coverage gate failed with $($violations.Count) violation(s). See above."
}

Write-Host "Coverage gate passed for $Edition."
