<#
.SYNOPSIS
    Produces the Everpure-branded 'EverpureFBModule' package from the built module and
    (optionally) publishes it to the PowerShell Gallery.

.DESCRIPTION
    The source module keeps its name (PureStorageFlashBladePowerShell) so existing GitHub /
    Import-Module consumers are unaffected. This script takes the build/ output and emits a
    parallel build/EverpureFBModule/ package with:
      - files renamed to EverpureFBModule.psd1 / .psm1
      - RootModule + a stable GUID for the new package identity
      - Author / CompanyName / Copyright rebranded to Everpure, Inc.
      - ProjectUri / LicenseUri pointed at the public repo

    Without -Publish it stops after building + validating the package (a dry run).
    With -Publish -ApiKey <key> it pushes to the Gallery.

.PARAMETER Publish
    Actually publish to the PowerShell Gallery. Omit for a dry run (build + validate only).

.PARAMETER ApiKey
    PowerShell Gallery API key (required with -Publish). Do NOT hard-code or commit this.

.EXAMPLE
    .\scripts\Publish-Gallery.ps1            # dry run: build + brand + Test-ModuleManifest

.EXAMPLE
    .\scripts\Publish-Gallery.ps1 -Publish -ApiKey $env:PSGALLERY_KEY
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [switch]$Publish,
    [string]$ApiKey
)

$ErrorActionPreference = 'Stop'
$repoRoot   = Split-Path -Parent $PSScriptRoot
$packageName = 'EverpureFBModule'
$stableGuid  = 'dae38a9b-9885-40ea-a3e5-f7405038ab99'
$projectUri  = 'https://github.com/PureStorage-OpenConnect/flashblade-powershell'
$licenseUri  = 'https://github.com/PureStorage-OpenConnect/flashblade-powershell/blob/main/LICENSE'

# 1. Build the module normally.
& (Join-Path $PSScriptRoot 'build.ps1')

$srcName = 'PureStorageFlashBladePowerShell'
$srcDir  = Join-Path $repoRoot "build/$srcName"
if (-not (Test-Path (Join-Path $srcDir "$srcName.psd1"))) {
    throw "Built module not found at $srcDir. Did build.ps1 succeed?"
}

# 2. Copy to a branded package folder.
$dstDir = Join-Path $repoRoot "build/$packageName"
if (Test-Path $dstDir) { Remove-Item $dstDir -Recurse -Force }
New-Item -ItemType Directory -Path $dstDir | Out-Null
Copy-Item (Join-Path $srcDir "$srcName.psm1") (Join-Path $dstDir "$packageName.psm1")
Copy-Item (Join-Path $srcDir 'LICENSE')       (Join-Path $dstDir 'LICENSE') -ErrorAction SilentlyContinue
# Data/ holds the runtime capability + version maps (read from disk relative to the
# module root). build.ps1 copies it into the source package; carry it into the branded
# package too, or the API version-awareness check silently no-ops on every Gallery install.
$dataDir = Join-Path $srcDir 'Data'
if (Test-Path $dataDir) { Copy-Item $dataDir (Join-Path $dstDir 'Data') -Recurse }

# 3. Re-brand the manifest.
$psd1 = Get-Content (Join-Path $srcDir "$srcName.psd1") -Raw
$psd1 = $psd1 -replace "RootModule\s*=\s*'$srcName\.psm1'", "RootModule        = '$packageName.psm1'"
$psd1 = $psd1 -replace "GUID\s*=\s*'[0-9a-fA-F-]+'",         "GUID              = '$stableGuid'"
$psd1 = $psd1 -replace 'Pure Storage, Inc\.', 'Don Mann, Justin Emerson, Mike Nelson'
$psd1 = $psd1 -replace 'Pure Storage FlashBlade REST 2\.x PowerShell Toolkit', 'FlashBlade REST 2.x PowerShell Toolkit (EverpureFBModule; community module by Don Mann, Justin Emerson, Mike Nelson)'
$psd1 = $psd1 -replace [regex]::Escape('https://github.com/PureStorage-OpenConnect/flashblade-powershell-toolkit/blob/master/LICENSE'), $licenseUri
$psd1 = $psd1 -replace [regex]::Escape('https://github.com/PureStorage-OpenConnect/flashblade-powershell-toolkit'), $projectUri
Set-Content -Path (Join-Path $dstDir "$packageName.psd1") -Value $psd1 -Encoding UTF8

# 4. Validate.
$m = Test-ModuleManifest -Path (Join-Path $dstDir "$packageName.psd1")
Write-Host ""
Write-Host "Branded package ready: $dstDir" -ForegroundColor Green
Write-Host ("  Name    : {0}" -f $m.Name)
Write-Host ("  Version : {0}" -f $m.Version)
Write-Host ("  Author  : {0}" -f $m.Author)
Write-Host ("  GUID    : {0}" -f $m.Guid)
Write-Host ("  Exports : {0} functions" -f $m.ExportedFunctions.Count)

# 5. Publish (guarded).
if ($Publish) {
    if (-not $ApiKey) { throw "-ApiKey is required with -Publish." }
    if ($PSCmdlet.ShouldProcess("PowerShell Gallery", "Publish $packageName v$($m.Version)")) {
        Publish-Module -Path $dstDir -NuGetApiKey $ApiKey -Repository PSGallery
        Write-Host "Published $packageName v$($m.Version) to the PowerShell Gallery." -ForegroundColor Green
        Write-Host "NEXT: add co-owners (Justin Emerson, Mike Nelson) via the Gallery 'Manage Owners' page." -ForegroundColor Yellow
    }
}
else {
    Write-Host ""
    Write-Host "DRY RUN - not published. Re-run with -Publish and an -ApiKey to push to the Gallery." -ForegroundColor Yellow
}
