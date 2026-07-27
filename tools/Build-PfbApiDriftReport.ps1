#Requires -Version 7.0
<#
.SYNOPSIS
    Builds the combined "API drift" report: uncovered endpoints, parameter gaps on
    endpoints an existing cmdlet already calls, drift on ValidateSets that already
    exist, and new ValidateSet candidates.
.DESCRIPTION
    Composes Data/PfbCapabilityMap.json, the AST-based cmdlet-parameter inventory
    (tools/lib/PfbCmdletParamTools.ps1), and Reports/PfbFieldCmdletMap.json rather than
    re-deriving spec parsing for categories 1/2/4. Category 3 (ValidateSet drift) does
    re-scan tools/specs/ via Get-PfbValueEnumHistory (tools/lib/PfbValueEnumTools.ps1) --
    see docs/superpowers/plans/2026-07-17-api-drift-report-plan.md's "Deviation from the
    design spec" note for why that one category needs it.

    Reporting only -- does NOT add a ValidateSet, ArgumentCompleter, or typed parameter
    to any Public/ cmdlet.
.PARAMETER SpecsDirectory
    Where cached spec JSON files live. Defaults to tools/specs relative to this script.
.PARAMETER PublicDirectory
    Where Public/ cmdlet files live. Defaults to Public/ relative to the repo root.
.PARAMETER PrivateDirectory
    Where Private/ helper files live. Defaults to Private/ relative to the repo root.
.PARAMETER CapabilityMapPath
    Path to the capability-map JSON. Defaults to Data/PfbCapabilityMap.json.
.PARAMETER FieldCmdletMapPath
    Path to the field-cmdlet-map JSON. Defaults to Reports/PfbFieldCmdletMap.json.
.PARAMETER OutputPath
    Where to write Reports/PfbApiDriftReport.json. Defaults there.
.PARAMETER ReportPath
    Where to write Reports/PfbApiDriftReport.md. Defaults there.
.PARAMETER SinceVersion
    Optional REST version (e.g. '2.26'). When given, uncoveredEndpoints and
    parameterGaps are filtered down to only items introduced strictly after this
    version -- e.g. -SinceVersion '2.26' isolates exactly what 2.27 added, instead of
    the full accumulated backlog since 2.0. validateSetDrift and newValidateSetCandidates
    are not filtered: the capability map doesn't track a per-value introduced-version for
    either category, only per-field/per-endpoint, so there's no "since" signal to filter
    on there yet.
#>
[CmdletBinding()]
param(
    [string]$SpecsDirectory,
    [string]$PublicDirectory,
    [string]$PrivateDirectory,
    [string]$CapabilityMapPath,
    [string]$FieldCmdletMapPath,
    [string]$OutputPath,
    [string]$ReportPath,
    [string]$SinceVersion
)

$ErrorActionPreference = 'Stop'

$scriptDir = $PSScriptRoot
. (Join-Path $scriptDir 'lib/PfbSpecTools.ps1')
. (Join-Path $scriptDir 'lib/PfbValueEnumTools.ps1')
. (Join-Path $scriptDir 'lib/PfbCmdletParamTools.ps1')
. (Join-Path $scriptDir 'lib/PfbApiDriftTools.ps1')

$repoRoot = Split-Path -Parent $scriptDir
if (-not $SpecsDirectory)      { $SpecsDirectory = Join-Path $scriptDir 'specs' }
if (-not $PublicDirectory)     { $PublicDirectory = Join-Path $repoRoot 'Public' }
if (-not $PrivateDirectory)    { $PrivateDirectory = Join-Path $repoRoot 'Private' }
if (-not $CapabilityMapPath)   { $CapabilityMapPath = Join-Path (Join-Path $repoRoot 'Data') 'PfbCapabilityMap.json' }
if (-not $FieldCmdletMapPath)  { $FieldCmdletMapPath = Join-Path (Join-Path $repoRoot 'Reports') 'PfbFieldCmdletMap.json' }
if (-not $OutputPath)          { $OutputPath = Join-Path (Join-Path $repoRoot 'Reports') 'PfbApiDriftReport.json' }
if (-not $ReportPath)          { $ReportPath = Join-Path (Join-Path $repoRoot 'Reports') 'PfbApiDriftReport.md' }

if (-not (Test-Path $CapabilityMapPath))  { throw "Capability map not found at '$CapabilityMapPath'. Run Build-PfbCapabilityMap.ps1 first." }
if (-not (Test-Path $FieldCmdletMapPath)) { throw "Field-cmdlet map not found at '$FieldCmdletMapPath'. Run Build-PfbFieldCmdletMap.ps1 first." }

$capabilityMap = Get-Content -Path $CapabilityMapPath -Raw | ConvertFrom-Json -Depth 20
$fieldCmdletMap = Get-Content -Path $FieldCmdletMapPath -Raw | ConvertFrom-Json -Depth 20

$inventory = Get-PfbCmdletParameterInventory -PublicDirectory $PublicDirectory
$calledEndpoints = Get-PfbModuleCalledEndpoints -PublicDirectory $PublicDirectory -PrivateDirectory $PrivateDirectory

# "Newest spec" for read-only/phantom resolution is pinned to the capability map's OWN
# analysed set ($capabilityMap.generatedFrom[-1]), never whatever file happens to be
# newest under -SpecsDirectory -- the two diverge as soon as specs are refreshed without
# rebuilding the map (see this repo's drift-report-actionable plan, Task 7's
# generatedFrom item, for the verified case: specs at 2.28, map at 2.27). Only this ONE
# spec is re-parsed here, purely to give Get-PfbParameterCoverageGaps the CURRENT
# (phantom-free) parameter/body-property set per endpoint -- see that function's
# -CurrentSpecCapabilities help for why the capability map's own accumulated
# parameters/bodyProperties dictionaries can't answer that question by themselves.
$newestAnalysedVersion = $capabilityMap.generatedFrom | Select-Object -Last 1
$currentSpecCapabilities = @()
if ($newestAnalysedVersion) {
    $newestSpecPath = Join-Path $SpecsDirectory "fb$newestAnalysedVersion.json"
    if (-not (Test-Path $newestSpecPath)) {
        throw "Newest analysed spec 'fb$newestAnalysedVersion.json' (per capability map's generatedFrom) not found under '$SpecsDirectory'. Run Update-PfbApiSpecs.ps1 first, or rebuild the capability map against the specs on disk."
    }
    $newestSpec = Get-Content -Path $newestSpecPath -Raw | ConvertFrom-Json -Depth 64
    $currentSpecCapabilities = @(Get-PfbSpecCapabilities -Spec $newestSpec)
}

# --- Category 1 ---
# The outer @(...) wraps the WHOLE pipeline (input AND ForEach-Object projection), not
# just the input side -- assigning a pipeline's output straight to a variable silently
# unwraps a single-item result to a bare scalar/hashtable in PowerShell (confirmed live:
# @(1) | ForEach-Object { [ordered]@{a=1} } assigns a bare OrderedDictionary, not a
# one-element array). Wrapping only the input (e.g. "@(Get-Foo) | ForEach-Object {...}")
# does NOT protect the assignment -- the collapse happens on the pipeline's OUTPUT, so
# the @(...) must enclose the entire right-hand side. Without this, a category with
# exactly one row serializes as a bare JSON object instead of a one-element JSON array,
# silently breaking the manifest's documented array-typed schema for that category.
$uncoveredEndpoints = @(Get-PfbEndpointCoverageGaps -CapabilityMap $capabilityMap -CalledEndpoints $calledEndpoints -BespokeAllowlist $script:PfbBespokeAuthEndpoints -SinceVersion $SinceVersion |
    ForEach-Object { [ordered]@{ endpoint = $_.Endpoint; minVersion = $_.MinVersion } })

# --- Category 2 ---
# No more notVerifiedEndpoints bucket: Get-PfbParameterCoverageGaps always computes
# gaps now and carries per-parameter confidence on each row instead (design decision 5).
$parameterGaps = @(Get-PfbParameterCoverageGaps -CapabilityMap $capabilityMap -CmdletInventory $inventory -CalledEndpoints $calledEndpoints -SinceVersion $SinceVersion -ExcludedFields $script:PfbNonActionableParameters -CurrentSpecCapabilities $currentSpecCapabilities |
    ForEach-Object {
        [ordered]@{
            endpoint                = $_.Endpoint
            cmdlets                 = @($_.Cmdlets)
            missingQueryParameters   = @($_.MissingQueryParameters)
            missingBodyProperties    = @($_.MissingBodyProperties)
            readOnlyFields           = @($_.ReadOnlyFields)
            confidence               = [ordered]@{
                level                = $_.Confidence.Level
                unresolvedParameters = @($_.Confidence.UnresolvedParameters | ForEach-Object {
                        [ordered]@{ parameter = $_.Parameter; surface = $_.Surface; file = $_.File; line = $_.Line }
                    })
                escapeHatchOnly      = @($_.Confidence.EscapeHatchOnly)
                caveat               = $_.Confidence.Caveat
            }
        }
    })

# --- Category 3 ---
$historyResult = Get-PfbValueEnumHistory -SpecsDirectory $SpecsDirectory
$validateSetDrift = @(Get-PfbValidateSetDrift -CmdletInventory $inventory -History $historyResult.History -OldestVersion $historyResult.OldestVersion |
    ForEach-Object {
        [ordered]@{
            cmdlet             = $_.Cmdlet
            parameter          = $_.Parameter
            currentValidateSet = @($_.CurrentValidateSet)
            specValues         = @($_.SpecValues)
            missingValues      = @($_.MissingValues)
            staleValues        = @($_.StaleValues)
        }
    })

# --- Category 4: pass Build-PfbFieldCmdletMap.ps1's 'matched' entries straight through ---
$newValidateSetCandidates = @($fieldCmdletMap.entries | Where-Object { $_.status -eq 'matched' } |
    ForEach-Object { [ordered]@{ cmdlet = $_.cmdlet; parameter = $_.parameter; wireName = $_.wireName; specValues = $_.specValues; recommendation = $_.recommendation } })

$manifest = [ordered]@{
    schemaVersion             = 1
    generatedFrom             = $historyResult.ProcessedVersions
    sinceVersion              = if ($SinceVersion) { $SinceVersion } else { $null }
    uncoveredEndpoints        = $uncoveredEndpoints
    parameterGaps             = $parameterGaps
    validateSetDrift          = $validateSetDrift
    newValidateSetCandidates  = $newValidateSetCandidates
}

$outputDir = Split-Path -Parent $OutputPath
if (-not (Test-Path $outputDir)) { New-Item -ItemType Directory -Path $outputDir -Force | Out-Null }
$manifest | ConvertTo-Json -Depth 20 | Set-Content -Path $OutputPath -Encoding UTF8

$mdLines = [System.Collections.Generic.List[string]]::new()
$mdLines.Add('# API Drift Report')
$mdLines.Add('')
$mdLines.Add("Generated by ``tools/Build-PfbApiDriftReport.ps1`` ($($historyResult.ProcessedVersions.Count) REST versions).")
$mdLines.Add('')
$mdLines.Add('Reporting only -- no `Public/` cmdlet is edited by this script.')
$mdLines.Add('')
if ($SinceVersion) {
    $mdLines.Add("Uncovered endpoints and parameter gaps are filtered to items introduced after REST $SinceVersion. ValidateSet drift and new ValidateSet candidates are not filtered (no per-value introduced-version data to filter on).")
    $mdLines.Add('')
}
$partialConfidenceCount = @($parameterGaps | Where-Object { $_.confidence.level -eq 'partial' }).Count

$mdLines.Add('## Summary')
$mdLines.Add('')
$mdLines.Add("- Uncovered endpoints: $($uncoveredEndpoints.Count)")
$mdLines.Add("- Endpoints with parameter gaps: $($parameterGaps.Count)")
$mdLines.Add("- Missing query parameters: $((@($parameterGaps.missingQueryParameters) | Measure-Object).Count)")
$mdLines.Add("- Missing body properties (addable): $((@($parameterGaps.missingBodyProperties) | Measure-Object).Count)")
$mdLines.Add("- Read-only body fields (not addable): $((@($parameterGaps.readOnlyFields) | Measure-Object).Count)")
$mdLines.Add("- Partial-confidence endpoints (has attributes/unresolved surface -- see each row's ``confidence``): $partialConfidenceCount")
$mdLines.Add("- ValidateSet drift: $($validateSetDrift.Count)")
$mdLines.Add("- New ValidateSet candidates: $($newValidateSetCandidates.Count)")

if ($uncoveredEndpoints.Count -gt 0) {
    $mdLines.Add(''); $mdLines.Add('## Uncovered endpoints'); $mdLines.Add('')
    $mdLines.Add('| Endpoint | Introduced in |'); $mdLines.Add('|---|---|')
    foreach ($e in $uncoveredEndpoints) { $mdLines.Add("| ``$($e.endpoint)`` | $($e.minVersion) |") }
}
if ($parameterGaps.Count -gt 0) {
    $mdLines.Add(''); $mdLines.Add('## Parameter gaps'); $mdLines.Add('')
    $mdLines.Add('| Endpoint | Cmdlets | Missing query parameters | Missing body properties | Read-only fields | Confidence |'); $mdLines.Add('|---|---|---|---|---|---|')
    foreach ($g in $parameterGaps) { $mdLines.Add("| ``$($g.endpoint)`` | $($g.cmdlets -join ', ') | $($g.missingQueryParameters -join ', ') | $($g.missingBodyProperties -join ', ') | $($g.readOnlyFields -join ', ') | $($g.confidence.level) |") }
}
if ($validateSetDrift.Count -gt 0) {
    $mdLines.Add(''); $mdLines.Add('## ValidateSet drift'); $mdLines.Add('')
    $mdLines.Add('| Cmdlet | Parameter | Missing values | Stale values |'); $mdLines.Add('|---|---|---|---|')
    foreach ($d in $validateSetDrift) { $mdLines.Add("| ``$($d.cmdlet)`` | ``-$($d.parameter)`` | $($d.missingValues -join ', ') | $($d.staleValues -join ', ') |") }
}
if ($newValidateSetCandidates.Count -gt 0) {
    $mdLines.Add(''); $mdLines.Add('## New ValidateSet candidates'); $mdLines.Add('')
    $mdLines.Add('| Cmdlet | Parameter | Spec values |'); $mdLines.Add('|---|---|---|')
    foreach ($c in $newValidateSetCandidates) { $mdLines.Add("| ``$($c.cmdlet)`` | ``-$($c.parameter)`` | $($c.specValues -join ', ') |") }
}
$mdLines.Add('')

Set-Content -Path $ReportPath -Value ($mdLines -join "`n") -Encoding UTF8
Write-Host "Wrote API drift report to $OutputPath and $ReportPath" -ForegroundColor Green
