#Requires -Version 7.0
<#
.SYNOPSIS
    Builds the committed report of cmdlet query keys that their endpoint does not declare.
.DESCRIPTION
    Compares the AST-based cmdlet parameter inventory with the query parameters declared by
    the pinned REST API spec. A dead key is silently discarded by the array, so a GET can return
    an unfiltered collection and a write can arrive without its selector. This script reports the
    finding without modifying any Public/ cmdlet.
.PARAMETER SpecsDirectory
    Where cached spec JSON files live. Defaults to tools/specs relative to this script.
.PARAMETER PublicDirectory
    Where Public/ cmdlet files live. Defaults to Public/ relative to the repo root.
.PARAMETER CapabilityMapPath
    Path to the capability-map JSON. Defaults to Data/PfbCapabilityMap.json.
.PARAMETER OutputPath
    Where to write Reports/PfbDeadKeyReport.json. Defaults there.
#>
[CmdletBinding()]
param(
    [string]$SpecsDirectory,
    [string]$PublicDirectory,
    [string]$CapabilityMapPath,
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

$scriptDir = $PSScriptRoot
. (Join-Path $scriptDir 'lib/PfbSpecTools.ps1')
. (Join-Path $scriptDir 'lib/PfbCmdletParamTools.ps1')

$repoRoot = Split-Path -Parent $scriptDir
if (-not $SpecsDirectory)    { $SpecsDirectory = Join-Path $scriptDir 'specs' }
if (-not $PublicDirectory)   { $PublicDirectory = Join-Path $repoRoot 'Public' }
if (-not $CapabilityMapPath) { $CapabilityMapPath = Join-Path (Join-Path $repoRoot 'Data') 'PfbCapabilityMap.json' }
if (-not $OutputPath)        { $OutputPath = Join-Path (Join-Path $repoRoot 'Reports') 'PfbDeadKeyReport.json' }

if (-not (Test-Path -LiteralPath $CapabilityMapPath)) {
    throw "Capability map not found at '$CapabilityMapPath'. Run Build-PfbCapabilityMap.ps1 first."
}

$capabilityMap = Get-Content -Path $CapabilityMapPath -Raw | ConvertFrom-Json -Depth 20
$specVersion = $capabilityMap.generatedFrom | Select-Object -Last 1
if (-not $specVersion) {
    throw "Capability map at '$CapabilityMapPath' has no generatedFrom versions."
}

$specPath = Join-Path $SpecsDirectory "fb$specVersion.json"
if (-not (Test-Path -LiteralPath $specPath)) {
    throw "Pinned analysed spec 'fb$specVersion.json' (per capability map's generatedFrom) not found under '$SpecsDirectory'. Run Update-PfbApiSpecs.ps1 first, or rebuild the capability map against the specs on disk."
}

$spec = Get-Content -Path $specPath -Raw | ConvertFrom-Json -Depth 64
$inventory = @(Get-PfbCmdletParameterInventory -PublicDirectory $PublicDirectory)

# Task 4 mirrors this exact helper verbatim. It sorts records, not a joined key, using an
# explicit ordinal comparison on Cmdlet then Parameter. Ordinal is stable between PS7 and
# Windows PowerShell 5.1; Sort-Object -Culture '' is invariant linguistic and is not.
function Sort-PfbDeadKeyRecords {
    param(
        [Parameter(Mandatory)]
        [object[]]$Records
    )

    $sorted = [System.Collections.Generic.List[object]]::new()
    foreach ($record in $Records) { $sorted.Add($record) }
    $sorted.Sort([System.Comparison[object]]{
        param($left, $right)
        $comparison = [string]::Compare(
            [string]$left.Cmdlet,
            [string]$right.Cmdlet,
            [System.StringComparison]::Ordinal)
        if ($comparison -ne 0) { return $comparison }
        return [string]::Compare(
            [string]$left.Parameter,
            [string]$right.Parameter,
            [System.StringComparison]::Ordinal)
    })
    return @($sorted)
}

function Test-PfbDeadKeySelectorName {
    param(
        [Parameter(Mandatory)]
        [string]$WireName
    )

    # Exact anchors are intentional. In particular, do not use a suffix regex that would
    # classify usernames, grids, ids_or_names, or context_names as selectors.
    if ($WireName -in @('names', 'ids', 'name', 'id')) { return $true }
    if ($WireName -in @('context_names', 'ids_or_names')) { return $false }
    return $WireName.EndsWith('_names', [System.StringComparison]::Ordinal) -or
        $WireName.EndsWith('_ids', [System.StringComparison]::Ordinal)
}

function Get-PfbDeadKeySeverity {
    param(
        [Parameter(Mandatory)]
        [string]$Method
    )

    switch ($Method.ToUpperInvariant()) {
        'DELETE' { return 'DESTRUCTIVE' }
        'PATCH'  { return 'DESTRUCTIVE' }
        'PUT'    { return 'DESTRUCTIVE' }
        'POST'   { return 'CREATE' }
        'GET'    { return 'WRONG-RESULTS' }
        default  { return 'UNKNOWN' }
    }
}

$skipReasons = [ordered]@{
    'wire name unresolved'          = 0
    'body property'                 = 0
    'endpoint/method ambiguous'     = 0
    'endpoint/verb absent from spec' = 0
}
$okRecords = [System.Collections.Generic.List[object]]::new()
$deadKeyRecords = [System.Collections.Generic.List[object]]::new()
$evaluatedRecords = [System.Collections.Generic.List[object]]::new()

foreach ($record in $inventory) {
    if ($null -eq $record.WireName) {
        $skipReasons['wire name unresolved']++
        continue
    }
    if ($record.WireSurface -eq 'Body') {
        $skipReasons['body property']++
        continue
    }
    if ([string]::IsNullOrEmpty([string]$record.Endpoint) -or
        [string]::IsNullOrEmpty([string]$record.Method)) {
        $skipReasons['endpoint/method ambiguous']++
        continue
    }

    $declared = Get-PfbDeclaredQueryKey -Spec $spec -Endpoint $record.Endpoint -Method $record.Method -Version $specVersion
    if ($null -eq $declared) {
        $skipReasons['endpoint/verb absent from spec']++
        continue
    }

    $method = ([string]$record.Method).ToUpperInvariant()
    $wireName = [string]$record.WireName
    $status = if (@($declared) -contains $wireName) { 'OK' } else { 'DEAD KEY' }
    $evaluated = [PSCustomObject]@{
        Cmdlet        = $record.Cmdlet
        Parameter     = $record.Parameter
        WireName      = $wireName
        Method        = $method
        Endpoint      = $record.Endpoint
        Status        = $status
        SelectorShaped = Test-PfbDeadKeySelectorName -WireName $wireName
    }
    $evaluatedRecords.Add($evaluated)

    if ($status -eq 'OK') {
        $okRecords.Add($evaluated)
        continue
    }

    $deadKeyRecords.Add([PSCustomObject]@{
        Cmdlet    = $record.Cmdlet
        Parameter = $record.Parameter
        Severity  = Get-PfbDeadKeySeverity -Method $method
        WireKey   = $wireName
        Method    = $method
        Endpoint  = $record.Endpoint
        Declared  = @($declared)
    })
}

# Group evaluated selector records only. A skipped selector is unevaluable, not evidence that
# every selector is dead. Thus a group is emitted only when it has at least one selector and all
# of its selector-shaped keys were evaluated and classified as DEAD KEY.
$noSurvivingSelectorRecords = [System.Collections.Generic.List[object]]::new()
$selectorGroups = @($evaluatedRecords | Where-Object SelectorShaped | Group-Object Cmdlet, Method, Endpoint)
foreach ($group in $selectorGroups) {
    if (@($group.Group | Where-Object Status -ne 'DEAD KEY').Count -eq 0) {
        $first = $group.Group | Select-Object -First 1
        $noSurvivingSelectorRecords.Add([PSCustomObject]@{
            Cmdlet    = $first.Cmdlet
            Parameter = "$($first.Method) $($first.Endpoint)"
            Method    = $first.Method
            Endpoint  = $first.Endpoint
        })
    }
}

$sortedDeadKeys = @(Sort-PfbDeadKeyRecords -Records @($deadKeyRecords) |
    ForEach-Object {
        [ordered]@{
            severity  = $_.Severity
            cmdlet    = $_.Cmdlet
            parameter = $_.Parameter
            wireKey   = $_.WireKey
            method    = $_.Method
            endpoint  = $_.Endpoint
            declared  = @($_.Declared)
        }
    })
$sortedNoSurvivingSelector = @(Sort-PfbDeadKeyRecords -Records @($noSurvivingSelectorRecords) |
    ForEach-Object {
        [ordered]@{
            cmdlet   = $_.Cmdlet
            method   = $_.Method
            endpoint = $_.Endpoint
        }
    })

$manifest = [ordered]@{
    specVersion = [string]$specVersion
    counts      = [ordered]@{
        parametersInventoried = $inventory.Count
        keysEvaluated         = $evaluatedRecords.Count
        ok                    = $okRecords.Count
        deadKey               = $deadKeyRecords.Count
        skipReasons           = $skipReasons
    }
    deadKeys = $sortedDeadKeys
    noSurvivingSelector = $sortedNoSurvivingSelector
}

$outputDir = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}
$manifest | ConvertTo-Json -Depth 20 | Set-Content -Path $OutputPath -Encoding UTF8
Write-Host "Wrote $($deadKeyRecords.Count) dead keys from $($inventory.Count) inventoried parameters to $OutputPath" -ForegroundColor Green
