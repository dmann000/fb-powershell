<#
.SYNOPSIS
    Fails the build when tools/specs/ did not materialise.
.DESCRIPTION
    Issue #63: tools/specs/ is a ~50MB cache of raw OpenAPI specs, gitignored (.gitignore:36
    and again .gitignore:46) because it is a build input rather than source. On a bare runner
    it is therefore absent, and every tooling test that depends on it skipped gracefully while
    the job reported success -- roughly 23% of the suite, invisible in the run summary.

    The prepare-specs job restores the cache and tops it up from the published spec index.
    This asserts that actually worked, so a restore-miss combined with a fetch failure is a
    red build rather than a quietly hollow test run. Without it the job would "succeed" and
    hand the test legs an empty directory, reproducing the exact defect being fixed.

    Lives in scripts/ rather than tools/ deliberately: .gitignore:46 ignores tools/ wholesale
    ("Not yet decided whether this should be tracked -- excluded for now"). The existing
    tools/*.ps1 files are tracked only because they predate that rule, so a NEW file added
    there would be silently untracked. scripts/ is unignored and already holds the scripts the
    workflows call (see scripts/Publish-Gallery.ps1, used by publish-to-gallery.yml).
.PARAMETER SpecsDirectory
    Defaults to tools/specs relative to the repo root.
.PARAMETER MinimumCount
    A floor, not a pin. 20 rather than the 29 currently published, on purpose: this asserts
    "the mechanism worked", and the real count grows with every REST release -- pinning it
    would turn each new publication into an unrelated red build.
#>
[CmdletBinding()]
param(
    [string]$SpecsDirectory,
    [int]$MinimumCount = 20
)

$ErrorActionPreference = 'Stop'

if (-not $SpecsDirectory) {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $SpecsDirectory = Join-Path $repoRoot 'tools/specs'
}

$specs = @(Get-ChildItem -Path $SpecsDirectory -Filter 'fb*.json' -ErrorAction SilentlyContinue)
Write-Host "$SpecsDirectory contains $($specs.Count) spec file(s)."

if ($env:GITHUB_STEP_SUMMARY) {
    "Restored **$($specs.Count)** OpenAPI spec files to ``tools/specs/``." |
        Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append
}
if ($env:GITHUB_OUTPUT) {
    "spec_count=$($specs.Count)" | Out-File -FilePath $env:GITHUB_OUTPUT -Append
}

if ($specs.Count -lt $MinimumCount) {
    throw "Expected at least $MinimumCount fb*.json spec files in $SpecsDirectory, found $($specs.Count). The cache did not restore and the fetch did not succeed -- failing loudly rather than letting the tooling tests skip (issue #63)."
}
