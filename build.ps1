<#
.SYNOPSIS
    Builds the PureStorageFlashBladePowerShell module for release.
.DESCRIPTION
    Concatenates all Private/ and Public/ .ps1 files into a single monolithic .psm1,
    then copies the .psd1 and LICENSE into an output folder ready for publishing.
.PARAMETER OutputPath
    Path to the output directory. Defaults to ./build/PureStorageFlashBladePowerShell
#>
[CmdletBinding()]
param(
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$moduleName = 'PureStorageFlashBladePowerShell'

# Resolve script root (works for both -File and dot-sourcing)
$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $scriptRoot) { $scriptRoot = (Get-Location).Path }

if (-not $OutputPath) {
    $OutputPath = Join-Path (Join-Path $scriptRoot 'build') $moduleName
}

Write-Host "Building $moduleName..." -ForegroundColor Cyan

# Clean output directory
if (Test-Path $OutputPath) {
    Remove-Item $OutputPath -Recurse -Force
}
New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null

# --- Build the monolithic .psm1 ---
$psm1Builder = [System.Text.StringBuilder]::new()

# Header
[void]$psm1Builder.AppendLine('#Requires -Version 5.1')
[void]$psm1Builder.AppendLine('')
[void]$psm1Builder.AppendLine('# =============================================================================')
[void]$psm1Builder.AppendLine("# $moduleName")
[void]$psm1Builder.AppendLine('# Pure Storage FlashBlade REST 2.x PowerShell Toolkit')
[void]$psm1Builder.AppendLine("# Built: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') UTC")
[void]$psm1Builder.AppendLine('# =============================================================================')
[void]$psm1Builder.AppendLine('')

# Module-scoped state
[void]$psm1Builder.AppendLine('# Module-scoped connection state')
[void]$psm1Builder.AppendLine('$script:PfbDefaultArray = $null')
[void]$psm1Builder.AppendLine('$script:PfbArrays = @{}')
[void]$psm1Builder.AppendLine('')

# Private functions
$privatePath = Join-Path $scriptRoot 'Private'
$privateFiles = Get-ChildItem -Path $privatePath -Filter '*.ps1' -Recurse | Sort-Object Name
Write-Host "  Private functions: $($privateFiles.Count)" -ForegroundColor Gray

[void]$psm1Builder.AppendLine('# =============================================================================')
[void]$psm1Builder.AppendLine('# Private Functions')
[void]$psm1Builder.AppendLine('# =============================================================================')
[void]$psm1Builder.AppendLine('')

foreach ($file in $privateFiles) {
    [void]$psm1Builder.AppendLine("# --- $($file.Name) ---")
    $content = Get-Content -Path $file.FullName -Raw
    [void]$psm1Builder.AppendLine($content.TrimEnd())
    [void]$psm1Builder.AppendLine('')
}

# Public functions
$publicPath = Join-Path $scriptRoot 'Public'
$publicFiles = Get-ChildItem -Path $publicPath -Filter '*.ps1' -Recurse | Sort-Object FullName
Write-Host "  Public functions:  $($publicFiles.Count)" -ForegroundColor Gray

[void]$psm1Builder.AppendLine('# =============================================================================')
[void]$psm1Builder.AppendLine('# Public Functions')
[void]$psm1Builder.AppendLine('# =============================================================================')
[void]$psm1Builder.AppendLine('')

foreach ($file in $publicFiles) {
    $relativePath = $file.FullName.Replace($publicPath, '').TrimStart('\', '/')
    [void]$psm1Builder.AppendLine("# --- $relativePath ---")
    $content = Get-Content -Path $file.FullName -Raw
    [void]$psm1Builder.AppendLine($content.TrimEnd())
    [void]$psm1Builder.AppendLine('')
}

# Export statement
[void]$psm1Builder.AppendLine('# =============================================================================')
[void]$psm1Builder.AppendLine('# Exports')
[void]$psm1Builder.AppendLine('# =============================================================================')
$exportNames = $publicFiles | ForEach-Object { $_.BaseName }
$exportList = ($exportNames | ForEach-Object { "'$_'" }) -join ",`n    "
[void]$psm1Builder.AppendLine("Export-ModuleMember -Function @(`n    $exportList`n)")

# Write .psm1
$psm1Path = Join-Path $OutputPath "$moduleName.psm1"
Set-Content -Path $psm1Path -Value $psm1Builder.ToString() -Encoding UTF8 -NoNewline
$lineCount = ($psm1Builder.ToString() -split "`n").Count
Write-Host "  Generated $psm1Path ($lineCount lines)" -ForegroundColor Green

# --- Copy .psd1 ---
$psd1Source = Join-Path $scriptRoot "$moduleName.psd1"
Copy-Item -Path $psd1Source -Destination $OutputPath
Write-Host "  Copied $moduleName.psd1" -ForegroundColor Green

# --- Copy LICENSE ---
$licenseSource = Join-Path $scriptRoot 'LICENSE'
if (Test-Path $licenseSource) {
    Copy-Item -Path $licenseSource -Destination $OutputPath
    Write-Host "  Copied LICENSE" -ForegroundColor Green
}

# --- Summary ---
Write-Host ''
Write-Host "Build complete!" -ForegroundColor Green
Write-Host "Output: $OutputPath" -ForegroundColor Cyan
Write-Host ''
Get-ChildItem $OutputPath | ForEach-Object {
    $size = if ($_.Length) { "{0:N0} KB" -f ($_.Length / 1KB) } else { 'dir' }
    Write-Host ("  {0,-50} {1}" -f $_.Name, $size) -ForegroundColor Gray
}

