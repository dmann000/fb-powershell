#Requires -Version 7.0
<#
.SYNOPSIS
    Fetches every published FlashBlade REST API version's OpenAPI spec and caches it
    locally as pretty-printed JSON.
.DESCRIPTION
    Discovers the list of published versions from https://code.purestorage.com/swagger/,
    then for each one downloads its ReDoc reference page and extracts the embedded
    OpenAPI 3.0.1 document (see tools/lib/PfbSpecTools.ps1 for why this can't be a
    simple file download). Existing cached specs are skipped unless -Force is passed,
    so re-runs (including the scheduled CI job) only fetch newly-published versions.

    Output: tools/specs/fb<version>.json (one file per REST version), cached on disk under
    a gitignored directory (see tools/README.md for why) so Build-PfbCapabilityMap.ps1 runs
    offline/incrementally without re-fetching every time.
.PARAMETER OutputDirectory
    Where to write cached spec JSON files. Defaults to tools/specs relative to this
    script's location.
.PARAMETER Force
    Re-fetch and overwrite specs that are already cached.
.PARAMETER Versions
    Fetch only these specific version strings (e.g. '2.26','2.27') instead of the full
    discovered list. Useful for spot-checks and CI dry runs.
.EXAMPLE
    ./tools/Update-PfbApiSpecs.ps1
.EXAMPLE
    ./tools/Update-PfbApiSpecs.ps1 -Versions 2.26,2.27 -Force
#>
[CmdletBinding()]
param(
    [string]$OutputDirectory,

    [switch]$Force,

    [string[]]$Versions
)

$ErrorActionPreference = 'Stop'

$scriptDir = $PSScriptRoot
. (Join-Path $scriptDir 'lib/PfbSpecTools.ps1')

if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $scriptDir 'specs'
}
if (-not (Test-Path $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}

$indexUri = 'https://code.purestorage.com/swagger/'

if ($Versions) {
    $targetVersions = $Versions
}
else {
    Write-Host "Fetching version index from $indexUri..." -ForegroundColor Cyan
    $indexResponse = Invoke-WebRequest -Uri $indexUri -UseBasicParsing
    $targetVersions = Get-PfbSwaggerIndexVersions -IndexHtml $indexResponse.Content
    Write-Host "Discovered $($targetVersions.Count) published versions: $($targetVersions -join ', ')" -ForegroundColor Gray
}

$fetched = [System.Collections.Generic.List[string]]::new()
$skipped = [System.Collections.Generic.List[string]]::new()
$failed = [System.Collections.Generic.List[string]]::new()

foreach ($version in $targetVersions) {
    $outPath = Join-Path $OutputDirectory "fb$version.json"

    if ((Test-Path $outPath) -and -not $Force) {
        $skipped.Add($version)
        continue
    }

    $pageUri = "https://code.purestorage.com/swagger/redoc/fb$version-api-reference.html"
    Write-Host "Fetching $pageUri..." -ForegroundColor Cyan

    try {
        $page = Invoke-WebRequest -Uri $pageUri -UseBasicParsing
        $spec = ConvertFrom-PfbRedocHtml -Html $page.Content

        if (-not $spec.openapi) {
            throw "Extracted document has no 'openapi' field -- extraction likely failed silently."
        }

        # Re-serialize pretty-printed for easier local diffing/inspection of the cache.
        # Depth must cover the deepest schema nesting (allOf chains, nested component refs).
        $spec | ConvertTo-Json -Depth 64 | Set-Content -Path $outPath -Encoding UTF8
        Write-Host "  -> $outPath ($((Get-Item $outPath).Length / 1KB | ForEach-Object { '{0:N0} KB' -f $_ }))" -ForegroundColor Green
        $fetched.Add($version)
    }
    catch {
        Write-Warning "Failed to fetch/extract version '$version': $($_.Exception.Message)"
        $failed.Add($version)
    }
}

Write-Host ''
Write-Host "Fetched: $($fetched.Count)  Skipped (cached): $($skipped.Count)  Failed: $($failed.Count)" -ForegroundColor Cyan
if ($failed.Count -gt 0) {
    Write-Host "Failed versions: $($failed -join ', ')" -ForegroundColor Red
    exit 1
}
