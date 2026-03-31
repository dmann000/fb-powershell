#Requires -Version 5.1

# Module-scoped connection state
$script:PfbDefaultArray = $null
$script:PfbArrays = @{}

# Dot-source all private functions
$privatePath = Join-Path $PSScriptRoot 'Private'
if (Test-Path $privatePath) {
    Get-ChildItem -Path $privatePath -Filter '*.ps1' -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
        . $_.FullName
    }
}

# Dot-source all public functions
$publicPath = Join-Path $PSScriptRoot 'Public'
$publicFunctions = @()
if (Test-Path $publicPath) {
    $publicFiles = Get-ChildItem -Path $publicPath -Filter '*.ps1' -Recurse -ErrorAction SilentlyContinue
    foreach ($file in $publicFiles) {
        . $file.FullName
    }
    $publicFunctions = $publicFiles.BaseName
}

# Export only public functions
if ($publicFunctions.Count -gt 0) {
    Export-ModuleMember -Function $publicFunctions
}
