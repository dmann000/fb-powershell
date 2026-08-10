<#
.SYNOPSIS
    Fails the build when a Pester run silently lost coverage. Issue #63.
.DESCRIPTION
    The tooling tests gate themselves on tools/specs/, a gitignored build cache. On a bare
    runner they all reported "skipped", the job reported "success", and the coverage loss was
    invisible in the run summary. Restoring the cache fixes today's hole; this script is what
    makes the NEXT one a red build instead of a silent one.

    Two independent assertions, because either alone has a gap:

      1. Skip ceiling -- catches a Describe that starts reporting skips.
      2. Required-Describe allowlist -- catches a Describe that vanishes from the result tree
         entirely. These blocks skip GRACEFULLY: when their guard evaluates false at BeforeAll
         time, or the file is filtered out of a run, they contribute NEITHER a skip NOR a pass.
         A skip ceiling cannot see that, and a green summary is then indistinguishable from a
         silently-absent assertion -- the same failure shape as #63, one level down.

    Takes a result OBJECT rather than running Pester itself, so it is testable with a
    hand-built stand-in and needs neither a real suite run nor the spec cache.

    Lives in scripts/, not tools/: .gitignore:46 ignores tools/ wholesale, so a new file there
    would be silently untracked.

    5.1 CONSTRAINT: this runs under Windows PowerShell 5.1 as well as pwsh 7. No ternaries,
    no ??, no ConvertFrom-Json -Depth.

    Result shape verified against Pester 6.0.0 and 6.0.1 on both editions: $Result.Tests is a
    flat list, each entry has .Path (a List whose [0] is the top-level Describe name) and a
    .Result string; the run carries PassedCount/FailedCount/SkippedCount/NotRunCount.
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

# --- Assertion 2: skip ceiling -------------------------------------------------------------
$skippedTotal = [int]$Result.SkippedCount + [int]$Result.NotRunCount
$ceiling = [int]$editionBaseline.MaxSkipped

$summaryLines.Add('')
$summaryLines.Add("Skipped + not-run: **$skippedTotal** (ceiling $ceiling). Passed: $($Result.PassedCount). Failed: $($Result.FailedCount).")

if ($skippedTotal -gt $ceiling) {
    $violations.Add("Skipped + not-run count $skippedTotal exceeds the $Edition ceiling of $ceiling. Either coverage regressed, or the ceiling in Tests/coverage-baseline.psd1 needs a deliberate, reviewed raise.")
}

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
