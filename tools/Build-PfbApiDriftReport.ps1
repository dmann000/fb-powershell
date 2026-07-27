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

.NOTES
    Task 5 (enrichment + enum join) record shape for `parameterGaps[].missingBodyProperties`:

    - **Only enriched on a 'high'-confidence endpoint** (`confidence.level -eq 'high'`).
      On a 'partial'-confidence endpoint the entries stay bare strings, exactly as before --
      see the comment above `Get-PfbBodyPropertyEnrichment` in tools/lib/PfbApiDriftTools.ps1
      for why (short version: a partial-confidence endpoint's list can contain false
      positives, and attaching a fully-worked-out type/synopsis/enum/target to a field that
      might not even be a real gap would overstate a confidence the endpoint's own
      `confidence.caveat` is explicitly telling the reader not to have -- NOT a suppression,
      every field name still appears unchanged either way). This gating is also what makes
      this task's pinned acceptance numbers (33 matched / 43 not-found-in-resource / 326
      no-spec-enum-found, over 402 addable gaps) reproducible: they hold only over the
      'high'-confidence population (402), not over all addable gaps regardless of
      confidence (605) -- verified 2026-07-26.
    - **`missingQueryParameters` and `readOnlyFields` are deliberately NEVER enriched this
      way, regardless of confidence** -- `readOnlyFields` are not addable at all (there is
      nothing actionable to enrich), and query-parameter gaps stay bare name strings on
      purpose: ~896 query-gap records would roughly double this artifact's size for no
      current consumer (nothing downstream reads enriched query-gap detail today). This is a
      deliberate, documented asymmetry, not an inconsistency -- revisit only if a consumer
      for enriched query-gap detail actually appears.
    - Enriched shape: `{ name, type, format, specRequired, synopsis, suggestedPowerShellType,
      enumValues, enumStatus, target }`.
        - `type`/`format` are the raw OpenAPI values from the newest ANALYSED spec (may be
          `$null` when the property's own schema node carries no `type` -- e.g. the property
          is itself an unresolved `$ref`, per Get-PfbSchemaPropertyDetails's PIN).
        - `specRequired` is `Required` from Get-PfbSchemaPropertyDetails -- **this is
          informational metadata about the OpenAPI spec's own `required:` array, and must
          NEVER be treated as an instruction to make the corresponding PowerShell parameter
          `[Parameter(Mandatory)]`.** This repo has a recorded hazard: a `Mandatory`
          parameter tested via `Should -Throw` hangs the terminal on PowerShell's own
          "Supply values for parameters" interactive prompt -- the convention here is an
          optional parameter with an explicit `throw`. A human adding a parameter for a
          `specRequired: true` field should keep it optional and validate/throw in the
          function body, exactly like every other parameter in this module.
        - `suggestedPowerShellType` comes from a fixed table (`int64`->`[long]`,
          `int32`/`uint32`/no-format->`[int]`, `number`->`[double]`, `string`->`[string]`,
          `boolean`->`[bool]`, `array`->`[<element>[]]`, anything else->`[object]`) -- see
          `Get-PfbSuggestedPowerShellType` in tools/lib/PfbApiDriftTools.ps1. It exists
          specifically because the `int64`-vs-`int32` distinction is real and silent: 37 of
          the 402 real high-confidence addable fields are `type: integer, format: int64`,
          and eyeballing bare `"type": "integer"` while ignoring `format` would silently
          truncate every one of them by writing `[int]`. The raw `type`/`format` are ALWAYS
          emitted alongside so a human can override this suggestion.
        - `enumValues`/`enumStatus` come from `Resolve-PfbFieldValueEnum` (never a bare
          wire-name lookup), keyed by the field's own `OwnerSchema` as `-ResourceHint` (NOT
          the older cmdlet-name-derived `Get-PfbResourceHint`, which only reaches 14 of 33
          real matches). `enumStatus` is always one of that function's own literal values
          (`matched`/`collision`/`not-found-in-resource`/`no-spec-enum-found`) -- never
          silently coerced to `null`. `enumValues` is always an array (empty unless
          `enumStatus` is `matched`).
        - `target` carries insertion-point COORDINATES ONLY -- `{ file, paramBlockLine,
          payloadVariable, assignmentStyle, hasAttributes }` -- never a diff/patch (decision
          12): a patch goes stale the moment the file is next touched and cannot see
          mutual-exclusivity/parameter-set constraints a human editing by hand must respect.
          `file` is a repo-relative path (forward slashes). See
          `Get-PfbCmdletBodyInsertionTarget` in tools/lib/PfbCmdletParamTools.ps1 for exactly
          how `paramBlockLine`/`payloadVariable`/`assignmentStyle`/`hasAttributes` are
          derived, and this script's own `Get-PfbGapTarget` helper for how the ONE primary
          cmdlet is picked when an endpoint has more than one (alphabetically first, for
          determinism -- a human should still check for sibling cmdlets on the same
          endpoint).
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

# Endpoint key ("<METHOD> /<path>") -> the newest-analysed-spec BodyPropertyDetails record
# set for that endpoint, reused by Task 5's enrichment below (Get-PfbParameterCoverageGaps
# builds an equivalent dictionary internally for its OWN phantom-filtering purposes, but
# does not expose BodyPropertyDetails on its output -- this is a second, small, INTENTIONAL
# lookup built directly from $currentSpecCapabilities already computed above, not a second
# spec parse).
$currentByEndpoint = [System.Collections.Generic.Dictionary[string, object]]::new()
foreach ($cap in $currentSpecCapabilities) { $currentByEndpoint["$($cap.Method) $($cap.Path)"] = $cap }

# Value-enum history, computed ONCE and reused by two logically SEPARATE report
# categories: category 3 (Get-PfbValidateSetDrift, existing-ValidateSet drift -- unrelated
# to this task) below, and Task 5's own MissingBodyProperties enum-join enrichment inside
# category 2's own assembly further down. Moved up from its old position (immediately
# before category 3) so category 2 can consume it too, per this task's brief: "reuse the
# same $historyResult.History/$historyResult.OldestVersion rather than recomputing it."
$historyResult = Get-PfbValueEnumHistory -SpecsDirectory $SpecsDirectory

# Cmdlet name -> the absolute .ps1 file it's defined in, sourced from
# Get-PfbModuleCalledEndpoints's own scan (every Public/Private *.ps1 already parsed once
# for its literal Invoke-PfbApiRequest -Method/-Endpoint) rather than re-scanning
# -PublicDirectory again per gap -- avoids re-parsing potentially hundreds of files once
# per addable body-property gap (402 on the real tree).
$cmdletFile = [System.Collections.Generic.Dictionary[string, string]]::new()
foreach ($c in $calledEndpoints) {
    if ($c.Resolved -and -not $cmdletFile.ContainsKey($c.Cmdlet)) { $cmdletFile[$c.Cmdlet] = $c.File }
}

# File path -> Dictionary[cmdletName, FunctionDefinitionAst], parsed LAZILY and cached per
# FILE (not per cmdlet), so a file defining more than one function is only ever parsed once
# even if more than one of its cmdlets needs a target this run.
$fileFunctionAsts = [System.Collections.Generic.Dictionary[string, object]]::new()
function Get-PfbCmdletFunctionAst {
    <#
    .SYNOPSIS
        Returns -Cmdlet's own FunctionDefinitionAst, parsing (and caching) its file on
        first use. $null if -Cmdlet isn't in $cmdletFile or its file defines no function of
        that exact name.
    #>
    param([string]$Cmdlet)
    if (-not $cmdletFile.ContainsKey($Cmdlet)) { return $null }
    $file = $cmdletFile[$Cmdlet]
    if (-not $fileFunctionAsts.ContainsKey($file)) {
        $tokens = $null; $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$parseErrors)
        $funcs = [System.Collections.Generic.Dictionary[string, object]]::new()
        foreach ($f in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
            if (-not $funcs.ContainsKey($f.Name)) { $funcs[$f.Name] = $f }
        }
        $fileFunctionAsts[$file] = $funcs
    }
    $funcsForFile = $fileFunctionAsts[$file]
    if ($funcsForFile.ContainsKey($Cmdlet)) { return $funcsForFile[$Cmdlet] }
    return $null
}

function Get-PfbGapTarget {
    <#
    .SYNOPSIS
        Builds the `target` insertion-point-coordinates record (decision 12) for one
        addable missing-body-property gap, given the endpoint's -Cmdlets list.
    .DESCRIPTION
        When more than one cmdlet already calls the same endpoint (5 real cases today: GET
        /arrays, GET /blades, PATCH /buckets, PATCH /file-systems, PATCH /realms), the
        ALPHABETICALLY FIRST cmdlet name is picked as the single primary target,
        deterministically -- `target` is one set of coordinates, not a list, per the
        brief's shape, and alphabetical order needs no external state to reproduce. A human
        should still check for sibling cmdlets on the same endpoint before assuming this is
        the only place the field could be added.
        Every field degrades gracefully (never throws) if the primary cmdlet's file can't
        be located or its function can't be found -- both should be unreachable in practice
        since -Cmdlets is sourced from the same Get-PfbModuleCalledEndpoints scan
        $cmdletFile is built from, but a missing coordinate is far cheaper to hand a human
        than a failed report generation.
    .OUTPUTS
        [ordered]@{ file; paramBlockLine; payloadVariable; assignmentStyle; hasAttributes }
    #>
    param([string[]]$Cmdlets)

    $primaryCmdlet = @($Cmdlets | Sort-Object)[0]
    $file = if ($cmdletFile.ContainsKey($primaryCmdlet)) { $cmdletFile[$primaryCmdlet] } else { $null }
    if (-not $file) {
        return [ordered]@{ file = $null; paramBlockLine = $null; payloadVariable = $null; assignmentStyle = $null; hasAttributes = $null }
    }

    # Relative-to-$repoRoot when the cmdlet file is actually under it (the real Public/
    # tree, and this task's own repo-relative-path convention for `target.file`) --
    # otherwise (e.g. a test's -PublicDirectory pointed at a synthetic fixture tree
    # entirely outside $repoRoot) falls back to the file's own absolute path rather than
    # throwing a Substring range error.
    $relativeFile = if ($file.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        ($file.Substring($repoRoot.Length + 1)) -replace '\\', '/'
    }
    else {
        $file -replace '\\', '/'
    }
    $funcAst = Get-PfbCmdletFunctionAst -Cmdlet $primaryCmdlet
    if (-not $funcAst) {
        return [ordered]@{ file = $relativeFile; paramBlockLine = $null; payloadVariable = $null; assignmentStyle = $null; hasAttributes = $null }
    }

    $insertion = Get-PfbCmdletBodyInsertionTarget -FunctionAst $funcAst
    if (-not $insertion) {
        return [ordered]@{ file = $relativeFile; paramBlockLine = $null; payloadVariable = $null; assignmentStyle = $null; hasAttributes = $null }
    }

    return [ordered]@{
        file            = $relativeFile
        paramBlockLine  = $insertion.ParamBlockLine
        payloadVariable = $insertion.PayloadVariable
        assignmentStyle = $insertion.AssignmentStyle
        hasAttributes   = $insertion.HasAttributes
    }
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
#
# Task 5: a 'high'-confidence endpoint's MissingBodyProperties entries are enriched into
# full records (name/type/format/specRequired/synopsis/suggestedPowerShellType/enumValues/
# enumStatus/target) -- see this script's own .NOTES above and the comment above
# Get-PfbBodyPropertyEnrichment in tools/lib/PfbApiDriftTools.ps1 for why 'partial'-
# confidence endpoints are deliberately left as bare strings instead. $canEnrichBodyProperties
# is false only when the capability map carries no analysed spec version at all (no
# $newestSpec loaded above) -- an edge case that shouldn't occur on a real capability map,
# but degrading to the pre-enrichment bare-string shape is safer than throwing.
$canEnrichBodyProperties = [bool]$newestSpec

$parameterGaps = @(Get-PfbParameterCoverageGaps -CapabilityMap $capabilityMap -CmdletInventory $inventory -CalledEndpoints $calledEndpoints -SinceVersion $SinceVersion -ExcludedFields $script:PfbNonActionableParameters -CurrentSpecCapabilities $currentSpecCapabilities |
    ForEach-Object {
        $gapRaw = $_
        $endpointParts = $gapRaw.Endpoint -split ' ', 2
        $method = $endpointParts[0]
        $bareEndpoint = $endpointParts[1].TrimStart('/')

        $currentCap = $null
        if ($currentByEndpoint.ContainsKey($gapRaw.Endpoint)) { $currentCap = $currentByEndpoint[$gapRaw.Endpoint] }

        # @(...) wraps the WHOLE if/else, not just each branch's own inner @(...) -- the
        # same "assigning a statement's output straight to a variable silently unwraps an
        # EMPTY result to something that behaves like neither a real $null nor a real
        # empty array" hazard already documented elsewhere in this file (see
        # tools/lib/PfbApiDriftTools.ps1's $readOnlyList comment). Confirmed live: without
        # this outer wrap, a 'high'-confidence endpoint with an EMPTY MissingBodyProperties
        # (e.g. a query-only gap like DELETE /active-directory) produced a per-endpoint
        # value that read as 0 elements in-memory but round-tripped through
        # ConvertTo-Json/ConvertFrom-Json into a ONE-element array containing a single
        # $null (a phantom "field" with every property blank) -- silently inflating the
        # real 402-gap high-confidence addable total to 682 in the committed JSON, entirely
        # invisible to a same-process check that never serializes. Caught only by
        # serializing the real manifest and re-counting from the JSON on disk, exactly like
        # a real consumer would read it -- an in-memory-only check would have missed it.
        $missingBodyProperties = @(
            if ($gapRaw.Confidence.Level -eq 'high' -and $canEnrichBodyProperties) {
                $gapRaw.MissingBodyProperties | ForEach-Object {
                    $fieldName = $_
                    $detail = $null
                    if ($currentCap) { $detail = @($currentCap.BodyPropertyDetails) | Where-Object { $_.Name -eq $fieldName } | Select-Object -First 1 }

                    $type = if ($detail) { $detail.Type } else { $null }
                    $format = if ($detail) { $detail.Format } else { $null }
                    $specRequired = if ($detail) { [bool]$detail.Required } else { $false }
                    $ownerSchema = if ($detail) { $detail.OwnerSchema } else { $null }

                    $enrichment = Get-PfbBodyPropertyEnrichment -FieldName $fieldName -Type $type -Format $format -OwnerSchema $ownerSchema `
                        -Spec $newestSpec -Endpoint $bareEndpoint -Method $method -History $historyResult.History -OldestVersion $historyResult.OldestVersion

                    [ordered]@{
                        name                    = $fieldName
                        type                    = $type
                        format                  = $format
                        specRequired            = $specRequired
                        synopsis                = $enrichment.Synopsis
                        suggestedPowerShellType = $enrichment.SuggestedPowerShellType
                        enumValues              = @($enrichment.EnumValues)
                        enumStatus              = $enrichment.EnumStatus
                        target                  = (Get-PfbGapTarget -Cmdlets $gapRaw.Cmdlets)
                    }
                }
            }
            else {
                $gapRaw.MissingBodyProperties
            }
        )

        [ordered]@{
            endpoint                = $gapRaw.Endpoint
            cmdlets                 = @($gapRaw.Cmdlets)
            missingQueryParameters   = @($gapRaw.MissingQueryParameters)
            missingBodyProperties    = $missingBodyProperties
            readOnlyFields           = @($gapRaw.ReadOnlyFields)
            confidence               = [ordered]@{
                level                = $gapRaw.Confidence.Level
                unresolvedParameters = @($gapRaw.Confidence.UnresolvedParameters | ForEach-Object {
                        [ordered]@{ parameter = $_.Parameter; surface = $_.Surface; file = $_.File; line = $_.Line }
                    })
                escapeHatchOnly      = @($gapRaw.Confidence.EscapeHatchOnly)
                caveat               = $gapRaw.Confidence.Caveat
            }
        }
    })

# --- Category 3 ---
# $historyResult was computed earlier (before category 1) so category 2's enrichment above
# and this category both reuse the SAME Get-PfbValueEnumHistory result -- two logically
# separate report categories (existing-ValidateSet drift here vs. this task's new enum
# join above), never merged or confused, just sharing one expensive spec re-scan.
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
    foreach ($g in $parameterGaps) {
        # missingBodyProperties is a MIX of bare strings (partial-confidence endpoints,
        # unchanged from before this task) and enriched [ordered]@{} records (high-confidence
        # endpoints, this task) -- $_.name on a bare string returns $null, so the ?? falls
        # back to the string itself; on an enriched record it reads the 'name' key. Either
        # way the Markdown table shows just the field name, never a stringified hashtable.
        $bodyPropNames = ($g.missingBodyProperties | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.name } }) -join ', '
        $mdLines.Add("| ``$($g.endpoint)`` | $($g.cmdlets -join ', ') | $($g.missingQueryParameters -join ', ') | $bodyPropNames | $($g.readOnlyFields -join ', ') | $($g.confidence.level) |")
    }
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
