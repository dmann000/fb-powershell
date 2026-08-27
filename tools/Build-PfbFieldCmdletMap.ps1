#Requires -Version 7.0
<#
.SYNOPSIS
    Joins the cmdlet parameter inventory (tools/lib/PfbCmdletParamTools.ps1) against the
    prose value-enum data (tools/lib/PfbValueEnumTools.ps1) to recommend, per typed
    Public/ parameter that lacks a ValidateSet today, whether it should become a
    ValidateSet or an ArgumentCompleter.
.DESCRIPTION
    Data-extraction and reporting only -- does NOT add a ValidateSet or ArgumentCompleter
    to any Public/ cmdlet. See docs/superpowers/plans/2026-07-16-field-cmdlet-mapping.md
    for the full design rationale and the exact ValidateSet-recommendation rule.

    Resolves a candidate's wire name against three kinds of value-enum record (see
    tools/lib/PfbValueEnumTools.ps1): 'schema' (resource-hint filtered, a heuristic),
    'parameter' (a shared components.parameters dictionary name with no relationship to
    the owning resource, resolved only when every same-named definition agrees), and
    'inline-parameter' (an exact "<METHOD> <endpoint>#<wireName>" identity, resolvable
    only when tools/lib/PfbCmdletParamTools.ps1's AST inventory could determine exactly
    which endpoint this specific cmdlet parameter calls). An exact inline-parameter match
    takes priority -- it settles ambiguity the other two kinds cannot (the real
    Get-PfbArraySpace -Type case: two same-named-but-different-valued
    components.parameters definitions, 'Type' and 'Type_for_performance', disambiguated
    by knowing this cmdlet calls GET arrays/space specifically).
.PARAMETER SpecsDirectory
    Where cached spec JSON files live. Defaults to tools/specs relative to this script.
.PARAMETER PublicDirectory
    Where Public/ cmdlet files live. Defaults to Public/ relative to the repo root.
.PARAMETER OutputPath
    Where to write Reports/PfbFieldCmdletMap.json. Defaults there.
.PARAMETER ReportPath
    Where to write Reports/PfbFieldCmdletMapping.md. Defaults there.
#>
[CmdletBinding()]
param(
    [string]$SpecsDirectory,
    [string]$PublicDirectory,
    [string]$OutputPath,
    [string]$ReportPath
)

$ErrorActionPreference = 'Stop'

$scriptDir = $PSScriptRoot
. (Join-Path $scriptDir 'lib/PfbSpecTools.ps1')
. (Join-Path $scriptDir 'lib/PfbValueEnumTools.ps1')
. (Join-Path $scriptDir 'lib/PfbCmdletParamTools.ps1')

$repoRoot = Split-Path -Parent $scriptDir
if (-not $SpecsDirectory)  { $SpecsDirectory = Join-Path $scriptDir 'specs' }
if (-not $PublicDirectory) { $PublicDirectory = Join-Path $repoRoot 'Public' }
if (-not $OutputPath)      { $OutputPath = Join-Path (Join-Path $repoRoot 'Reports') 'PfbFieldCmdletMap.json' }
if (-not $ReportPath)      { $ReportPath = Join-Path (Join-Path $repoRoot 'Reports') 'PfbFieldCmdletMapping.md' }

$specFiles = Get-ChildItem -Path $SpecsDirectory -Filter 'fb*.json' -ErrorAction SilentlyContinue
if (-not $specFiles) {
    throw "No cached specs found in '$SpecsDirectory'. Run Update-PfbApiSpecs.ps1 first."
}

$specFiles = $specFiles | ForEach-Object {
    if ($_.BaseName -match '^fb(\d+)\.(\d+)$') {
        [PSCustomObject]@{ File = $_; Major = [int]$Matches[1]; Minor = [int]$Matches[2] }
    }
} | Where-Object { $_ } | Sort-Object Major, Minor

# Re-derive, per (schema/param) Key, the full per-version value-set history -- NOT just
# the "latest wins" summary Reports/PfbValueEnumMap.json stores -- so stability (did the
# value set ever change since first seen?) can be computed. Deliberately a separate,
# self-contained re-scan rather than modifying the prior phase's already-shipped output
# shape, keeping this task's diff additive-only.
$historyResult = Get-PfbValueEnumHistory -SpecsDirectory $SpecsDirectory
$history = $historyResult.History
$processedVersions = $historyResult.ProcessedVersions
$oldestVersion = $historyResult.OldestVersion

# --- Cmdlet parameter inventory, filtered to fields with no existing ValidateSet ---
$inventory = Get-PfbCmdletParameterInventory -PublicDirectory $PublicDirectory
$candidates = @($inventory | Where-Object { $_.Surface -eq 'Typed' -and -not $_.HasValidateSet })
$attributesOnly = @($inventory | Where-Object { $_.Surface -eq 'AttributesOnly' } | ForEach-Object { [ordered]@{ cmdlet = $_.Cmdlet; parameter = $_.Parameter } })
$typedUnresolved = @($inventory | Where-Object { $_.Surface -eq 'TypedUnresolved' } | ForEach-Object { [ordered]@{ cmdlet = $_.Cmdlet; parameter = $_.Parameter } })

# Non-applicable residual (issue #141 Task 4). Its own collection, NOT folded into
# typedUnresolved: that list is read as "the tool could not find this field's wire name", and
# neither of these rows is a standard-request field whose name went missing.
#
# What that does NOT license is the stronger claim that the parameter never reaches the wire.
# 'OutsideStandardRequest' is a statement about THIS RESOLVER'S REACH -- the declaring cmdlet
# issues no Invoke-PfbApiRequest call, so there is no standard payload to read a key out of --
# and several of these parameters demonstrably do reach the array by other means:
# Public/Connection/Connect-PfbArray.ps1:331 builds @{ username = $Username; password = ... }
# and POSTs it to /api/login at :351 via Invoke-WebRequest. Rendering these rows as "not a
# wire field" would be a confident false statement about six real cmdlets, which is the same
# class of error the never-guess contract exists to prevent, merely in prose instead of JSON.
#
# `surface` is carried per row because the two reasons are not interchangeable to a reader
# deciding what to do next -- 'NotWireParameter' is an audited request control with no query or
# body key and needs nothing done, while 'OutsideStandardRequest' says the whole cmdlet sits off
# the standard request path and is where a future reviewer would look first if that ever stopped
# being true.
$notApplicable = @($inventory | Where-Object { $_.Surface -in @('NotWireParameter', 'OutsideStandardRequest') } |
        ForEach-Object { [ordered]@{ cmdlet = $_.Cmdlet; parameter = $_.Parameter; surface = $_.Surface } })

# Every inventory row lands in exactly one of five buckets, and this asserts it rather than
# assuming it. Four are emitted below; the fifth (Typed WITH a ValidateSet) is deliberately
# emitted nowhere -- this report recommends ADDING a ValidateSet, and those parameters already
# have one. Without this check a Surface value added upstream and not taught to this script
# would simply disappear from the report, which is the quietest possible failure and exactly
# the one issue #141 exists to stop.
$typedWithValidateSet = @($inventory | Where-Object { $_.Surface -eq 'Typed' -and $_.HasValidateSet })
$partitioned = $candidates.Count + $typedWithValidateSet.Count + $attributesOnly.Count + $typedUnresolved.Count + $notApplicable.Count
if ($partitioned -ne $inventory.Count) {
    throw ("Inventory partition is incomplete: $($inventory.Count) rows in, $partitioned classified " +
        "(typed-no-validateset $($candidates.Count), typed-with-validateset $($typedWithValidateSet.Count), " +
        "attributesOnly $($attributesOnly.Count), typedUnresolved $($typedUnresolved.Count), notApplicable $($notApplicable.Count)). " +
        'A Surface value this script has not been taught would otherwise vanish from the report silently.')
}

$entries = foreach ($cand in $candidates) {
    $hint = Get-PfbResourceHint -CmdletName $cand.Cmdlet
    $resolution = Resolve-PfbFieldValueEnum -WireName $cand.WireName -ResourceHint $hint -Endpoint $cand.Endpoint -Method $cand.Method -History $history -OldestVersion $oldestVersion

    [ordered]@{
        cmdlet                   = $cand.Cmdlet
        parameter                = $cand.Parameter
        wireName                 = $cand.WireName
        status                   = $resolution.Status
        matchedKey               = $resolution.MatchedKey
        specValues                = $resolution.SpecValues
        stableSinceOldestVersion = $resolution.Stable
        recommendation           = $resolution.Recommendation
    }
}

$manifest = [ordered]@{
    schemaVersion  = 1
    generatedFrom  = $processedVersions
    entries        = $entries
    attributesOnly = $attributesOnly
    typedUnresolved = $typedUnresolved
    notApplicable   = $notApplicable
}

$outputDir = Split-Path -Parent $OutputPath
if (-not (Test-Path $outputDir)) { New-Item -ItemType Directory -Path $outputDir -Force | Out-Null }
$manifest | ConvertTo-Json -Depth 20 | Set-Content -Path $OutputPath -Encoding UTF8

$statusCounts = [ordered]@{}
foreach ($statusName in @('matched', 'collision', 'not-found-in-resource', 'no-spec-enum-found')) {
    $statusCounts[$statusName] = 0
}
foreach ($e in $entries) {
    if (-not $statusCounts.Contains($e.status)) { $statusCounts[$e.status] = 0 }
    $statusCounts[$e.status]++
}

$mdLines = [System.Collections.Generic.List[string]]::new()
$mdLines.Add('# Field-to-Cmdlet Mapping Report')
$mdLines.Add('')
$mdLines.Add("Generated by ``tools/Build-PfbFieldCmdletMap.ps1`` ($($processedVersions.Count) REST versions).")
$mdLines.Add('')
$mdLines.Add('Reporting only -- no `Public/` cmdlet is edited by this script. Every `matched` row below is a candidate for a follow-up decision, not an action already taken.')
$mdLines.Add('')
$mdLines.Add('## Summary')
$mdLines.Add('')
foreach ($key in $statusCounts.Keys) {
    $mdLines.Add("- $key`: $($statusCounts[$key])")
}
if ($statusCounts['matched'] -eq 0) {
    $mdLines.Add('')
    $mdLines.Add('No `matched` candidates this run -- this can be a genuinely correct result (most typed parameters without a `ValidateSet` are generic non-enum fields like filter/sort/limit/names/ids, not spec-documented enums) rather than a sign the tool found nothing useful. See the `collision`/`not-found-in-resource` rows below for what *is* actionable.')
}
$mdLines.Add('')
$mdLines.Add('| Cmdlet | Parameter | Wire name | Status | Spec values | Recommendation |')
$mdLines.Add('|---|---|---|---|---|---|')
foreach ($e in $entries) {
    if ($e.status -eq 'no-spec-enum-found') { continue }
    $mdLines.Add("| ``$($e.cmdlet)`` | ``-$($e.parameter)`` | $($e.wireName) | $($e.status) | $($e.specValues -join ', ') | $($e.recommendation) |")
}
$mdLines.Add('')
$mdLines.Add("## Attributes-only parameters (no typed field to attach either mechanism to): $($attributesOnly.Count)")
$mdLines.Add('')
foreach ($a in $attributesOnly) { $mdLines.Add("- ``$($a.cmdlet) -$($a.parameter)``") }
$mdLines.Add('')
$mdLines.Add("## Typed but unresolved wire name (needs manual inspection): $($typedUnresolved.Count)")
$mdLines.Add('')
foreach ($u in $typedUnresolved) { $mdLines.Add("- ``$($u.cmdlet) -$($u.parameter)``") }
$mdLines.Add('')
$mdLines.Add("## Outside this resolver's reach (no standard-request field to inspect): $($notApplicable.Count)")
$mdLines.Add('')
$mdLines.Add('Listed separately from the section above on purpose: neither is a standard-request field whose wire name went unresolved. `NotWireParameter` is an audited request control (`-Eradicate`, `-Force`) with no query or body key. `OutsideStandardRequest` means the declaring cmdlet issues no `Invoke-PfbApiRequest` call, so this resolver cannot see its payload -- it does **not** mean the parameter has no wire effect; `Connect-PfbArray -Username`/`-Password`, for example, reach `/api/login` through bespoke HTTP.')
$mdLines.Add('')
foreach ($n in $notApplicable) { $mdLines.Add("- ``$($n.cmdlet) -$($n.parameter)`` ($($n.surface))") }
$mdLines.Add('')

Set-Content -Path $ReportPath -Value ($mdLines -join "`n") -Encoding UTF8
Write-Host "Wrote $($entries.Count) entries to $OutputPath and $ReportPath" -ForegroundColor Green
