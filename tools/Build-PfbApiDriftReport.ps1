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
    [string]$ResponseShapeMapPath,
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
. (Join-Path $scriptDir 'lib/PfbContextRuleTools.ps1')

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

if (-not $ResponseShapeMapPath) {
    $ResponseShapeMapPath = Join-Path $repoRoot 'Data/PfbResponseShapeMap.json'
}

# Response-shape findings are optional: the map is a separate artifact with no runtime
# consumer, so a report generated before it exists should degrade to empty lists rather
# than fail. Absence is reported honestly below rather than rendered as "no drift".
$responseFindings = [PSCustomObject]@{
    Removals                = @()
    RenameCandidates        = @()
    UnhandledEnvelopeFields = @()
}
$responseShapeMapPresent = Test-Path $ResponseShapeMapPath
if ($responseShapeMapPresent) {
    $responseShapeMap = Get-Content -Path $ResponseShapeMapPath -Raw | ConvertFrom-Json
    $responseFindings = Get-PfbResponseShapeFindings `
        -ResponseShapeMap $responseShapeMap `
        -RequestHandlerPath (Join-Path $repoRoot 'Private/Invoke-PfbApiRequest.ps1')
}
else {
    Write-Warning "Response shape map not found at '$ResponseShapeMapPath'; response-shape drift categories will be empty. Run tools/Build-PfbResponseShapeMap.ps1."
}

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

function ConvertTo-PfbRepoRelativePath {
    <#
    .SYNOPSIS
        Rewrites an absolute cmdlet path to a forward-slashed path relative to $repoRoot.
    .DESCRIPTION
        Every path this report emits MUST be repo-relative. These artifacts are committed, so an
        absolute path bakes the generating machine's directory layout into the repository: it
        leaks a local filesystem structure, and it makes the committed file depend on WHERE it was
        generated -- regenerating from a git worktree instead of the main checkout rewrites every
        such line, producing hundreds of lines of diff churn that bury the real changes.

        Falls back to the forward-slashed absolute path when the file genuinely is not under
        $repoRoot (a test pointing -PublicDirectory at a synthetic fixture tree), rather than
        throwing a Substring range error.
    #>
    param([string]$Path)

    if (-not $Path) { return $Path }
    if ($Path.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return ($Path.Substring($repoRoot.Length + 1)) -replace '\\', '/'
    }
    return $Path -replace '\\', '/'
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

    $relativeFile = ConvertTo-PfbRepoRelativePath -Path $file
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

# Task 6: $script:PfbNonActionableParameters no longer carries continuation_token by hand
# -- Get-PfbNonActionableParameters derives it (plus the still-hardcoded X-Request-ID/
# offset, neither of which has any Private/ injection site) from a live AST scan of
# -PrivateDirectory, so a future change to how Invoke-PfbApiRequest.ps1 injects
# continuation_token is reflected here automatically instead of silently going stale.
$nonActionableParameters = Get-PfbNonActionableParameters -PrivateDirectory $PrivateDirectory

# Task 7: docs/drift-annotations.json -- Get-PfbDriftAnnotations returns $null gracefully
# when the file is absent (never throws), so every Find-PfbDriftAnnotation lookup below
# degrades to "no annotations" rather than failing report generation.
$driftAnnotationsPath = Join-Path $repoRoot 'docs/drift-annotations.json'
$driftAnnotations = Get-PfbDriftAnnotations -Path $driftAnnotationsPath

# Captured as its own variable rather than piped straight into the ForEach-Object
# projection below -- Task 6's Get-PfbSystemicGaps wiring and this task's own phantom-
# field transparency count (further down) both need the SAME raw, pre-projection gap
# objects Get-PfbParameterCoverageGaps returns. Calling the function twice for two
# different purposes would risk the two views drifting apart if -SinceVersion/
# -ExcludedFields ever diverged between call sites; capturing once and reusing avoids
# that entirely.
$parameterGapsRaw = @(Get-PfbParameterCoverageGaps -CapabilityMap $capabilityMap -CmdletInventory $inventory -CalledEndpoints $calledEndpoints -SinceVersion $SinceVersion -ExcludedFields $nonActionableParameters -CurrentSpecCapabilities $currentSpecCapabilities)

$parameterGaps = @($parameterGapsRaw | ForEach-Object {
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
                        # Repo-relative, same as target.file: these artifacts are committed, so an
                        # absolute path would leak the generating machine's layout and churn the
                        # diff whenever the report is regenerated from a different directory.
                        [ordered]@{ parameter = $_.Parameter; surface = $_.Surface; file = (ConvertTo-PfbRepoRelativePath -Path $_.File); line = $_.Line }
                    })
                escapeHatchOnly      = @($gapRaw.Confidence.EscapeHatchOnly)
                caveat               = $gapRaw.Confidence.Caveat
            }
            # Task 7: endpoint-matched entries from docs/drift-annotations.json (e.g. the
            # management-access-policies POST/PATCH/DELETE-403 liveTestingHazard note) --
            # matchType 'field' annotations are surfaced separately, per-name, on
            # `systemicGaps` below (Find-PfbDriftAnnotation -FieldName), not here.
            annotations              = @(Find-PfbDriftAnnotation -Annotations $driftAnnotations -Endpoint $gapRaw.Endpoint | ForEach-Object {
                    [ordered]@{ matchType = $_.matchType; match = $_.match; kind = $_.kind; note = $_.note; reference = $_.reference }
                })
        }
    })

# --- Task 6 wiring: systemic gaps + convention strength (this task's own job) ---
# Aggregated ONLY over 'high'-confidence gaps: a 'partial'-confidence endpoint's gap lists
# can contain false positives (an unresolved parameter may already cover the apparent gap
# through a path this AST-only inventory can't see -- see Get-PfbParameterCoverageGaps's
# own Confidence.Caveat), so folding it into a systemic FINDING would overstate a
# confidence the endpoint's own row already warns against. This mirrors the same
# high-confidence-only filter Tests/PfbApiDriftTools.Tests.ps1's 'Task 6 real-data
# invariants' Describe block applies before calling Get-PfbSystemicGaps, so the two stay
# in sync -- that Describe block recounts EndpointCount independently rather than pinning
# an exact figure (see docs/superpowers/plans/2026-07-30-drift-report-acceptance-figure-invariants.md).
$highConfidenceGapsRaw = @($parameterGapsRaw | Where-Object { $_.Confidence.Level -eq 'high' })
$systemicGapsRaw = @(Get-PfbSystemicGaps -Gaps $highConfidenceGapsRaw)

$systemicGaps = @($systemicGapsRaw | ForEach-Object {
        $finding = $_
        [ordered]@{
            name               = $finding.Name
            endpointCount      = $finding.EndpointCount
            queryEndpointCount = $finding.QueryEndpointCount
            bodyEndpointCount  = $finding.BodyEndpointCount
            endpoints          = @($finding.Endpoints)
            # Task 6's acceptance criterion: "the systemic section shows context_names at
            # its endpoint count with its annotation" -- matchType 'field' lookup by this
            # finding's own Name (never $null; Find-PfbDriftAnnotation always returns []).
            annotations        = @(Find-PfbDriftAnnotation -Annotations $driftAnnotations -FieldName $finding.Name | ForEach-Object {
                    [ordered]@{ matchType = $_.matchType; match = $_.match; kind = $_.kind; note = $_.note; reference = $_.reference }
                })
        }
    })

# No cap on -Names: Get-PfbConventionStrength is a cheap per-name dictionary lookup against
# a table built ONCE (Get-PfbWireNameCmdletCounts), so every systemic-gap name gets ranked
# here -- nothing is silently dropped from this list. Re-sorted by CmdletCount descending
# (Get-PfbConventionStrength itself preserves -Names' input order, ranking is this script's
# own choice) since a mechanical batch-fix candidate (high CmdletCount, e.g. `names` at
# 306) and an architectural gap (zero CmdletCount, e.g. `context_names`) are the two ends
# of this ranking a reader most wants surfaced first/last.
$conventionStrengthRaw = @(if ($systemicGapsRaw.Count -gt 0) { Get-PfbConventionStrength -CmdletInventory $inventory -Names @($systemicGapsRaw.Name) } else { @() })
$conventionStrength = @($conventionStrengthRaw | Sort-Object -Property @{ Expression = 'CmdletCount'; Descending = $true }, Name |
        ForEach-Object { [ordered]@{ name = $_.Name; cmdletCount = $_.CmdletCount; cmdlets = @($_.Cmdlets) } })

# --- Task 7: phantom-field transparency ---
# How many (endpoint, field) pairs were silently dropped from every gap list because
# Get-PfbParameterCoverageGaps's own -CurrentSpecCapabilities phantom-field exclusion (see
# that function's own .PARAMETER help) found them accumulated in the capability map but
# absent from the newest ANALYSED spec (fb$newestAnalysedVersion.json) -- e.g. a field
# withdrawn from the API after the version that first added it. Computed by calling the
# SAME function a second time WITHOUT -CurrentSpecCapabilities (its own documented "safe
# no-op default", i.e. no phantom filtering) and diffing the resulting (endpoint, list,
# field) triples against $parameterGapsRaw (the real, phantom-filtered run) -- never a
# re-derivation of the phantom-detection logic itself, so this can't silently drift from
# what Get-PfbParameterCoverageGaps actually does.
function Get-PfbGapFieldTripleSet {
    <#
    .SYNOPSIS
        Internal helper: every "<endpoint>|<list>|<field>" triple across -Gaps (one of
        Get-PfbParameterCoverageGaps's own raw outputs), used only to diff two runs of that
        function (with vs. without -CurrentSpecCapabilities) for the phantom-field count
        below. Not a general-purpose utility -- deliberately local to this script.
    #>
    param([object[]]$Gaps)
    $set = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($g in $Gaps) {
        foreach ($f in @($g.MissingQueryParameters)) { [void]$set.Add("$($g.Endpoint)|query|$f") }
        foreach ($f in @($g.MissingBodyProperties)) { [void]$set.Add("$($g.Endpoint)|body|$f") }
        foreach ($f in @($g.ReadOnlyFields)) { [void]$set.Add("$($g.Endpoint)|readOnly|$f") }
    }
    return $set
}
$parameterGapsRawUnfiltered = @(Get-PfbParameterCoverageGaps -CapabilityMap $capabilityMap -CmdletInventory $inventory -CalledEndpoints $calledEndpoints -SinceVersion $SinceVersion -ExcludedFields $nonActionableParameters)
$phantomFilteredTripleSet = Get-PfbGapFieldTripleSet -Gaps $parameterGapsRaw
$phantomUnfilteredTripleSet = Get-PfbGapFieldTripleSet -Gaps $parameterGapsRawUnfiltered
$phantomFieldCount = @($phantomUnfilteredTripleSet | Where-Object { -not $phantomFilteredTripleSet.Contains($_) }).Count

# --- Task 7: generatedFrom split ---
# `generatedFrom` over-claimed what the report actually analysed: it was populated from the
# tools/specs/ directory scan (Get-PfbValueEnumHistory's own $historyResult.ProcessedVersions),
# not from Data/PfbCapabilityMap.json's OWN generatedFrom -- the versions that actually drive
# every gap/phantom-field category above. The two are normally in step, which is why this
# was invisible, but they are independent inputs that drift the moment specs are refreshed
# without rebuilding the map (verified 2026-07-25 on bdf9d67: specs at 2.0-2.28, map still at
# 2.0-2.27 -- the report would have claimed 2.28 coverage while analysing nothing from it).
# Emitted as two separate, distinctly-named keys instead of one ambiguous `generatedFrom`:
#   - analysedVersions:      $CapabilityMap.generatedFrom -- what every gap category (and
#     the phantom-field filter above) is actually scoped against.
#   - availableSpecVersions: $historyResult.ProcessedVersions -- every spec on disk under
#     -SpecsDirectory, which Task 5's enum join and category 3 (ValidateSet drift) DO read
#     fresher-than-analysedVersions data from (see $historyResult's own construction
#     comment above) -- so this fact stays load-bearing, never silently dropped.
$analysedVersions = @($capabilityMap.generatedFrom)
$availableSpecVersions = @($historyResult.ProcessedVersions)
$versionDiffCount = @(Compare-Object -ReferenceObject $analysedVersions -DifferenceObject $availableSpecVersions).Count
$versionSetsDiverge = $versionDiffCount -gt 0
$versionDivergenceWarning = if ($versionSetsDiverge) {
    "analysedVersions ($($analysedVersions.Count) versions, through $($analysedVersions[-1])) and availableSpecVersions ($($availableSpecVersions.Count) versions, through $($availableSpecVersions[-1])) disagree -- this is expected while Data/PfbCapabilityMap.json is deliberately pinned to a specific REST version; rebuild it (tools/Build-PfbCapabilityMap.ps1) only when intentionally adopting the newer spec. Every gap/phantom-field/systemic-gap category in this report is scoped to analysedVersions; validateSetDrift and newValidateSetCandidates (Task 5's enum join) use availableSpecVersions, the fresher on-disk set."
}
else { $null }

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

# --- Category 5: spec-vs-module assumption (Fusion context_names cardinality rule) ---
# Categorically different from categories 1-4. Those ask "does the module cover what the
# API offers?"; this one asks "is an assumption baked into the module still true?". The
# module's cardinality rule is EXECUTED from its single declared home
# (Private/Test-PfbContextMultiValueCapable.ps1, dot-sourced by PfbContextRuleTools.ps1),
# never re-derived here -- a check that re-implements its own rule verifies nothing.
#
# The parameter signals come from the capability map, whose component data is
# last-seen-wins across analysedVersions, i.e. it describes $newestAnalysedVersion's wire
# shape. The HTTP 207 signal CANNOT come from the map -- it records the request surface
# only, with no response data at all -- so it is read from that same version's spec, keeping
# both halves on one version. When no spec is available the 207 signal is omitted entirely
# rather than defaulted: Get-PfbContextParameterFact carries an unknown 207 as $null and
# excludes it from comparison, so a missing spec narrows what this category can see but
# never makes it report something false.
# Plain if-statements with direct assignment, NOT `$x = if (...) { @() }`: an empty array
# emitted as the value of a scriptblock collapses to $null, which here would silently
# convert "checked the spec, no endpoint declares 207" into "207 was never checked", and
# would hand a null $contextFacts to functions that require a collection.
$context207Endpoints = $null
if ($newestSpec) {
    $context207Endpoints = [string[]]@(Get-PfbContextHttp207Endpoint -Spec $newestSpec)
}
$contextFacts = @()
if ($null -ne $context207Endpoints) {
    $contextFacts = @(Get-PfbContextParameterFact -CapabilityMap $capabilityMap -Http207Endpoint $context207Endpoints)
}
else {
    $contextFacts = @(Get-PfbContextParameterFact -CapabilityMap $capabilityMap)
}
$contextSignalDisagreements = @(Get-PfbContextSignalDisagreement -Fact $contextFacts |
    ForEach-Object {
        [ordered]@{
            endpoint                = $_.Endpoint
            method                  = $_.Method
            contextComponent        = $_.ContextComponent
            shape                   = $_.Shape
            ruleSaysMultiValue      = $_.RuleSaysMultiValue
            componentSaysMultiValue = $_.ComponentSaysMultiValue
            declaresAllowErrors     = $_.DeclaresAllowErrors
            declaresHttp207         = $_.DeclaresHttp207
            multiValueSignals       = @($_.MultiValueSignals)
            sizeOneSignals          = @($_.SizeOneSignals)
            summary                 = $_.Summary
        }
    })
# A NAMED SUBSET of the above, never an additional category -- see the function's help.
$contextSizeOneWithAllowErrors = @(Get-PfbContextSizeOneWithAllowErrors -Fact $contextFacts |
    ForEach-Object { [ordered]@{ endpoint = $_.Endpoint; method = $_.Method; contextComponent = $_.ContextComponent } })
$contextUnresolvedComponents = @(Get-PfbContextUnresolvedComponent -Fact $contextFacts |
    ForEach-Object { [ordered]@{ endpoint = $_.Endpoint; method = $_.Method } })

$manifest = [ordered]@{
    schemaVersion             = 1
    # See the generatedFrom-split block above: two distinctly-named keys instead of one
    # ambiguous `generatedFrom`, plus a warning (never $null-vs-absent-silent) when they
    # disagree.
    analysedVersions          = $analysedVersions
    availableSpecVersions     = $availableSpecVersions
    versionDivergenceWarning  = $versionDivergenceWarning
    sinceVersion              = if ($SinceVersion) { $SinceVersion } else { $null }
    phantomFieldCount         = $phantomFieldCount
    uncoveredEndpoints        = $uncoveredEndpoints
    parameterGaps             = $parameterGaps
    systemicGaps              = $systemicGaps
    conventionStrength        = $conventionStrength
    validateSetDrift          = $validateSetDrift
    newValidateSetCandidates  = $newValidateSetCandidates
    responseFieldRemovals           = @($responseFindings.Removals | ForEach-Object {
            [ordered]@{
                endpoint          = $_.Endpoint
                field             = $_.Field
                location          = $_.Location
                introducedVersion = $_.IntroducedVersion
                lastSeenVersion   = $_.LastSeenVersion
            }
        })
    responseFieldRenameCandidates   = @($responseFindings.RenameCandidates | ForEach-Object {
            [ordered]@{
                endpoint = $_.Endpoint
                location = $_.Location
                from     = $_.From
                to       = $_.To
                version  = $_.Version
            }
        })
    unhandledResponseEnvelopeFields = @($responseFindings.UnhandledEnvelopeFields | ForEach-Object {
            [ordered]@{ field = $_.Field; endpointCount = $_.EndpointCount }
        })
    contextCardinality        = [ordered]@{
        # The version this category's numbers describe -- never omit it, see the block
        # where these are computed.
        componentSourceVersion    = $newestAnalysedVersion
        # $null (not $false) when no spec was available to read responses from, so a
        # consumer can tell "no endpoint declares 207" from "207 was never checked".
        http207SignalAvailable    = ($null -ne $context207Endpoints)
        endpointsWithContextNames = $contextFacts.Count
        multiContextCapable       = @($contextFacts | Where-Object { $_.RuleSaysMultiValue }).Count
        signalDisagreements       = $contextSignalDisagreements
        # Named subset of signalDisagreements, NOT an additional finding.
        sizeOneWithAllowErrors    = $contextSizeOneWithAllowErrors
        unresolvedComponents      = $contextUnresolvedComponents
    }
}

$outputDir = Split-Path -Parent $OutputPath
if (-not (Test-Path $outputDir)) { New-Item -ItemType Directory -Path $outputDir -Force | Out-Null }
$manifest | ConvertTo-Json -Depth 20 | Set-Content -Path $OutputPath -Encoding UTF8

# --- Markdown report ---
# Section order (this task's brief): How to read this report -> Summary -> Systemic gaps
# -> Parameter gaps (query/body as separate columns) -> Read-only fields (not addressable)
# -> Uncovered endpoints -> ValidateSet drift -> New ValidateSet candidates.
$mdLines = [System.Collections.Generic.List[string]]::new()
$mdLines.Add('# API Drift Report')
$mdLines.Add('')
$mdLines.Add("Generated by ``tools/Build-PfbApiDriftReport.ps1`` ($($analysedVersions.Count) analysed REST versions; $($availableSpecVersions.Count) available on disk under ``tools/specs/``).")
$mdLines.Add('')
$mdLines.Add('Reporting only -- no `Public/` cmdlet is edited by this script.')
$mdLines.Add('')
if ($SinceVersion) {
    $mdLines.Add("Uncovered endpoints and parameter gaps are filtered to items introduced after REST $SinceVersion. ValidateSet drift and new ValidateSet candidates are not filtered (no per-value introduced-version data to filter on).")
    $mdLines.Add('')
}
if ($versionSetsDiverge) {
    $mdLines.Add("**Warning:** $versionDivergenceWarning")
    $mdLines.Add('')
}
$partialConfidenceCount = @($parameterGaps | Where-Object { $_.confidence.level -eq 'partial' }).Count

# "How to read this report" -- the decision-6 false-positive procedure, verbatim (see
# docs/superpowers/plans/drift-report-readonly-deprecated-fix-brief.md lines 249-283).
$mdLines.Add('## How to read this report')
$mdLines.Add('')
$mdLines.Add('This report accepts **false positives in order to eliminate false negatives**. A field is listed as missing even though the module can already set it, when a parameter covering it could not be traced to a wire name.')
$mdLines.Add('')
$mdLines.Add('**Detection.** Only possible where `confidence.level` is `partial`. When it is `high` (`unresolvedParameters` empty), the row carries no false-positive risk from this mechanism.')
$mdLines.Add('')
$mdLines.Add('**Resolution procedure:**')
$mdLines.Add('1. Open the named parameter at the given `file:line` and follow where its value goes.')
$mdLines.Add('2. If it reaches the wire under the same name as the reported gap -> the gap is a false positive AND a tooling bug: the parser does not recognise that idiom. File it as a parser gap and fix the parser.')
$mdLines.Add('3. If it reaches the wire under a different name -> the reported gap may still be real; check that field against the spec.')
$mdLines.Add('4. If it never reaches the wire -> the gap is real.')
$mdLines.Add('')
$mdLines.Add('**Why this trade is right:** a false positive costs a reader one `file:line` lookup; a false negative costs an undetected gap indefinitely. Every false positive here is a parser-gap detector -- it either fixes the tool permanently for every endpoint, or confirms a real gap.')

$mdLines.Add(''); $mdLines.Add('## Summary'); $mdLines.Add('')
$mdLines.Add("- Uncovered endpoints: $($uncoveredEndpoints.Count)")
$mdLines.Add("- Endpoints with parameter gaps: $($parameterGaps.Count)")
$mdLines.Add("- Missing body properties (addable): $((@($parameterGaps.missingBodyProperties) | Measure-Object).Count)")
$mdLines.Add("- Missing query parameters (addable): $((@($parameterGaps.missingQueryParameters) | Measure-Object).Count)")
$mdLines.Add("- Read-only body fields (not addable -- see the Read-only fields section below): $((@($parameterGaps.readOnlyFields) | Measure-Object).Count)")
$mdLines.Add("- Phantom fields silently excluded (accumulated in the capability map, absent from the newest analysed spec): $phantomFieldCount")
$mdLines.Add("- Partial-confidence endpoints (see ``How to read this report`` above, and each row's marker in the Parameter gaps table): $partialConfidenceCount")
$mdLines.Add("- Systemic gaps (distinct field names collapsed across high-confidence endpoints, detailed below): $($systemicGaps.Count)")
$mdLines.Add("- ValidateSet drift: $($validateSetDrift.Count)")
$mdLines.Add("- New ValidateSet candidates: $($newValidateSetCandidates.Count)")
$mdLines.Add("- Context cardinality signal disagreements (fb$newestAnalysedVersion): $($contextSignalDisagreements.Count)")
$mdLines.Add(('- Removed response fields: **{0}**' -f @($responseFindings.Removals).Count))
$mdLines.Add(('- Response rename candidates: **{0}**' -f @($responseFindings.RenameCandidates).Count))
$mdLines.Add(('- Envelope fields not read by `Invoke-PfbApiRequest`: **{0}**' -f @($responseFindings.UnhandledEnvelopeFields).Count))

if ($systemicGaps.Count -gt 0) {
    $mdLines.Add(''); $mdLines.Add('## Systemic gaps'); $mdLines.Add('')
    $mdLines.Add('One finding per distinct wire field name, collapsed across every endpoint where a high-confidence gap exists (decision 7) -- turns hundreds of per-endpoint rows into a handful of real, actionable decisions. "Cmdlets already using this name" is decision 8''s convention-strength ranking: a high count means closing the remaining gaps for this name is a mechanical batch fix; zero means no established convention exists to extend at all -- closing it is an architectural decision, not a mechanical one.')
    $mdLines.Add('')
    $systemicTopN = 25
    $systemicShown = @($systemicGaps | Select-Object -First $systemicTopN)
    if ($systemicGaps.Count -gt $systemicTopN) {
        $mdLines.Add("Showing the top $systemicTopN of $($systemicGaps.Count) findings by endpoint count -- the full list is in the JSON manifest's ``systemicGaps``, nothing is dropped there.")
        $mdLines.Add('')
    }
    $mdLines.Add('| Field name | Endpoints | Query | Body | Cmdlets already using this name | Annotation |'); $mdLines.Add('|---|---|---|---|---|---|')
    foreach ($s in $systemicShown) {
        $strength = $conventionStrength | Where-Object { $_.name -eq $s.name } | Select-Object -First 1
        $cmdletCount = if ($strength) { $strength.cmdletCount } else { 0 }
        $annotationNote = if (@($s.annotations).Count -gt 0) { ($s.annotations | ForEach-Object { $_.note }) -join '; ' } else { '' }
        $mdLines.Add("| ``$($s.name)`` | $($s.endpointCount) | $($s.queryEndpointCount) | $($s.bodyEndpointCount) | $cmdletCount | $annotationNote |")
    }
}

if ($parameterGaps.Count -gt 0) {
    $mdLines.Add(''); $mdLines.Add('## Parameter gaps'); $mdLines.Add('')
    $mdLines.Add('Endpoints an existing cmdlet already calls, where the capability map knows of a query parameter or addable body property the cmdlet does not yet expose. Read-only fields (never addable, regardless of confidence) are reported separately below, never blended into either column here.')
    $mdLines.Add('')
    $mdLines.Add('| Endpoint | Cmdlets | Missing query parameters | Missing body properties | Confidence | Notes |'); $mdLines.Add('|---|---|---|---|---|---|')
    foreach ($g in $parameterGaps) {
        # missingBodyProperties is a MIX of bare strings (partial-confidence endpoints,
        # unchanged from before this task) and enriched [ordered]@{} records (high-confidence
        # endpoints, this task) -- $_.name on a bare string returns $null, so the ?? falls
        # back to the string itself; on an enriched record it reads the 'name' key. Either
        # way the Markdown table shows just the field name, never a stringified hashtable.
        $bodyPropNames = ($g.missingBodyProperties | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.name } }) -join ', '
        $confidenceCell = if ($g.confidence.level -eq 'partial') {
            $unresolvedCount = @($g.confidence.unresolvedParameters).Count
            $plural = if ($unresolvedCount -eq 1) { '' } else { 's' }
            "``partial`` -- /!\ $unresolvedCount unresolved param$plural (see Partial-confidence detail below)"
        }
        else { '`high`' }
        $notes = if (@($g.annotations).Count -gt 0) { ($g.annotations | ForEach-Object { $_.note }) -join '; ' } else { '' }
        $mdLines.Add("| ``$($g.endpoint)`` | $($g.cmdlets -join ', ') | $($g.missingQueryParameters -join ', ') | $bodyPropNames | $confidenceCell | $notes |")
    }

    $partialGaps = @($parameterGaps | Where-Object { $_.confidence.level -eq 'partial' })
    if ($partialGaps.Count -gt 0) {
        $mdLines.Add(''); $mdLines.Add('### Partial-confidence detail'); $mdLines.Add('')
        $mdLines.Add('Per the decision-6 procedure above: open each parameter at its `file:line` and follow where its value goes.')
        $mdLines.Add('')
        $mdLines.Add('| Endpoint | Parameter | Surface | File:Line | Caveat |'); $mdLines.Add('|---|---|---|---|---|')
        foreach ($g in $partialGaps) {
            foreach ($u in $g.confidence.unresolvedParameters) {
                $mdLines.Add("| ``$($g.endpoint)`` | ``-$($u.parameter)`` | $($u.surface) | ``$($u.file):$($u.line)`` | $($g.confidence.caveat) |")
            }
        }
    }
}

$readOnlyRows = @($parameterGaps | Where-Object { @($_.readOnlyFields).Count -gt 0 })
if ($readOnlyRows.Count -gt 0) {
    $mdLines.Add(''); $mdLines.Add('## Read-only fields (not addressable)'); $mdLines.Add('')
    $mdLines.Add('The capability map knows these body properties exist, but the newest analysed spec marks them read-only -- no `Public/` cmdlet can ever set them, on any confidence level. Listed for completeness only; never merged into the Parameter gaps table above.')
    $mdLines.Add('')
    $mdLines.Add('| Endpoint | Cmdlets | Read-only fields |'); $mdLines.Add('|---|---|---|')
    foreach ($g in $readOnlyRows) { $mdLines.Add("| ``$($g.endpoint)`` | $($g.cmdlets -join ', ') | $($g.readOnlyFields -join ', ') |") }
}

$mdLines.Add(''); $mdLines.Add('## Response-shape drift'); $mdLines.Add('')
if (-not $responseShapeMapPresent) {
    $mdLines.Add('> **Not analysed.** `Data/PfbResponseShapeMap.json` was not found when this report was generated. Run `tools/Build-PfbResponseShapeMap.ps1`. The absence of findings below does *not* mean there is no response drift.')
}
else {
    $mdLines.Add('Cmdlets pass API responses through raw -- there is no projection anywhere in `Public/`, so the module holds no schema of its own. A **removed or renamed** response field therefore reaches user scripts as a silent `$null`, which no other report category can detect. **Added** response fields are deliberately not reported: they surface automatically and need no module change.')
    $mdLines.Add('')

    $mdLines.Add('### Removed response fields')
    $mdLines.Add('')
    if (@($responseFindings.Removals).Count -eq 0) {
        $mdLines.Add('_None._')
    }
    else {
        $mdLines.Add('| Endpoint | Location | Field | Introduced | Last seen |')
        $mdLines.Add('|---|---|---|---|---|')
        foreach ($r in $responseFindings.Removals) {
            $mdLines.Add(('| `{0}` | {1} | `{2}` | {3} | {4} |' -f $r.Endpoint, $r.Location, $r.Field, $r.IntroducedVersion, $r.LastSeenVersion))
        }
    }
    $mdLines.Add('')

    $mdLines.Add('### Rename candidates')
    $mdLines.Add('')
    $mdLines.Add('_A removal and an addition adjacent in version on the same endpoint. Suggestive, not proof -- confirm against the spec before acting._')
    $mdLines.Add('')
    if (@($responseFindings.RenameCandidates).Count -eq 0) {
        $mdLines.Add('_None._')
    }
    else {
        $mdLines.Add('| Endpoint | Location | From | To | Version |')
        $mdLines.Add('|---|---|---|---|---|')
        foreach ($r in $responseFindings.RenameCandidates) {
            $mdLines.Add(('| `{0}` | {1} | `{2}` | `{3}` | {4} |' -f $r.Endpoint, $r.Location, $r.From, $r.To, $r.Version))
        }
    }
    $mdLines.Add('')

    $mdLines.Add('### Response envelope fields not read by `Invoke-PfbApiRequest`')
    $mdLines.Add('')
    $mdLines.Add('_Informational coverage observation, not a correctness claim -- many envelope keys legitimately need no handling there. It cannot tell whether a field is handled correctly, only whether it is referenced at all._')
    $mdLines.Add('')
    if (@($responseFindings.UnhandledEnvelopeFields).Count -eq 0) {
        $mdLines.Add('_None._')
    }
    else {
        $mdLines.Add('| Envelope field | Endpoints declaring it |')
        $mdLines.Add('|---|---|')
        foreach ($r in $responseFindings.UnhandledEnvelopeFields) {
            $mdLines.Add(('| `{0}` | {1} |' -f $r.Field, $r.EndpointCount))
        }
    }
}

if ($uncoveredEndpoints.Count -gt 0) {
    $mdLines.Add(''); $mdLines.Add('## Uncovered endpoints'); $mdLines.Add('')
    $mdLines.Add('| Endpoint | Introduced in |'); $mdLines.Add('|---|---|')
    foreach ($e in $uncoveredEndpoints) { $mdLines.Add("| ``$($e.endpoint)`` | $($e.minVersion) |") }
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

# Emitted UNCONDITIONALLY, unlike every section above -- for this category "nothing to
# report" is itself a finding, and a section that disappears when clean is
# indistinguishable from a section that never ran.
$mdLines.Add(''); $mdLines.Add('## Spec-vs-module assumptions: `context_names` cardinality'); $mdLines.Add('')
$mdLines.Add('Every category above asks *"does the module cover what the API offers?"*. This one asks a different question: *"is an assumption baked into the module still true?"*')
$mdLines.Add('')
$mdLines.Add('The module''s cardinality rule -- **an endpoint is multi-context-capable if and only if its `context_names` resolves to component `Context_names_get` AND the endpoint declares `allow_errors`** -- is declared in exactly one place, `Private/Test-PfbContextMultiValueCapable.ps1`, which this check *executes* rather than re-derives. The HTTP verb is not the rule; it survives only as a fallback for an endpoint absent from the capability map. See section 8 of `docs/design/fusion-context-injection.md`.')
$mdLines.Add('')
$mdLines.Add('This is a **cross-signal** check, not a rule-versus-spec one. The earlier two-signal shape was structurally unable to see the defect that actually exists: four fleet-scoped GETs reference the multi-value component *and* are size-1 on the wire, so the rule and the component agreed while both were wrong. Any endpoint whose available signals do not all agree is reported below, including the case where the component agrees with the rule but the remaining signals dissent.')
$mdLines.Add('')
$mdLines.Add("Measured against **fb$newestAnalysedVersion** (the newest analysed version; the capability map's component data is last-seen-wins, so it describes that version's wire shape). $($contextFacts.Count) endpoints declare ``context_names``, of which **$(@($contextFacts | Where-Object { $_.RuleSaysMultiValue }).Count)** satisfy the rule.")
$mdLines.Add('')
if ($null -ne $context207Endpoints) {
    $mdLines.Add("The HTTP 207 signal is read from ``tools/specs/fb$newestAnalysedVersion.json`` -- the capability map records the request surface only and holds no response data, so 207 is a corroborating signal for this report and never a runtime gate.")
}
else {
    $mdLines.Add('**The HTTP 207 signal was unavailable** (no spec on disk for the newest analysed version), so it was excluded from comparison rather than assumed absent. Findings below are based on the component and `allow_errors` signals only.')
}
$mdLines.Add('')
$mdLines.Add('**A disagreement is not automatically a spec defect.** The case worth catching is a genuine future multi-context endpoint, where the *module* would be the wrong side. A human decides which signal is wrong, each time.')
$mdLines.Add('')
if ($contextSignalDisagreements.Count -eq 0) {
    $mdLines.Add("**No signal disagreements** across all $($contextFacts.Count) endpoints in fb$newestAnalysedVersion.")
    $mdLines.Add('')
    $mdLines.Add('Read this as *the available signals agree*, not as *the module is verified correct*. Signals agreeing is exactly the state the four fleet-scoped GETs were in under the previous two-signal check while being wrong on the wire. Only live testing settles behaviour; see Appendix A of the design doc for what has actually been probed.')
}
else {
    $mdLines.Add("**$($contextSignalDisagreements.Count) endpoint(s) with disagreeing signals**, grouped by shape.")
    $mdLines.Add('')
    foreach ($shapeGroup in ($contextSignalDisagreements | Group-Object { $_.shape } | Sort-Object Name)) {
        $mdLines.Add("#### ``$($shapeGroup.Name)`` ($($shapeGroup.Count))")
        $mdLines.Add('')
        switch ($shapeGroup.Name) {
            'component-says-multi-value-but-no-allow-errors' {
                $mdLines.Add('The component claims fan-out while the endpoint offers no partial-failure story. Strong evidence of a spec defect: this is the shape of the four fleet-scoped GETs confirmed size-1 on the wire, and of `DELETE /management-access-policies` before its 2.28 correction.')
            }
            'size-1-component-but-declares-allow-errors' {
                $mdLines.Add('The mirror case -- a size-1 component on an endpoint that nonetheless declares `allow_errors`. Named again below.')
            }
            'rule-says-capable-but-declares-no-207' {
                $mdLines.Add('Component and `allow_errors` both say fan-out, but no HTTP 207 is declared, so partial failure has no documented response shape. Status genuinely unknown -- which is precisely why 207 is a corroborating signal here and never a runtime gate: treating these as size-1 would block calls that may well work.')
            }
            default {
                $mdLines.Add('An endpoint declaring a partial-failure response while no other signal says it fans out.')
            }
        }
        $mdLines.Add('')
        $mdLines.Add('| Endpoint | Method | Component | Declares `allow_errors` | Declares 207 | Module rule |'); $mdLines.Add('|---|---|---|---|---|---|')
        foreach ($d in $shapeGroup.Group) {
            $aeCell = if ($d.declaresAllowErrors) { 'yes' } else { 'no' }
            $c207Cell = if ($null -eq $d.declaresHttp207) { '_unknown_' } elseif ($d.declaresHttp207) { 'yes' } else { 'no' }
            $ruleCell = if ($d.ruleSaysMultiValue) { 'multi-value' } else { 'size-1' }
            $mdLines.Add("| ``$($d.endpoint)`` | $($d.method) | ``$($d.contextComponent)`` | $aeCell | $c207Cell | $ruleCell |")
        }
        $mdLines.Add('')
    }
}

# A NAMED SUBSET of the findings above, never an additional category -- reporting it as its
# own finding would double-count one defect as two.
$mdLines.Add('')
$mdLines.Add('### Named case: size-1 component declaring `allow_errors`')
$mdLines.Add('')
$mdLines.Add('A **subset** of the findings above (shape `size-1-component-but-declares-allow-errors`), not an additional finding. Called out by name because it is a known, characterized case.')
$mdLines.Add('')
if ($contextSizeOneWithAllowErrors.Count -eq 0) { $mdLines.Add('_None._') }
else {
    foreach ($s in $contextSizeOneWithAllowErrors) { $mdLines.Add("- ``$($s.endpoint)``") }
    $mdLines.Add('')
    $mdLines.Add('Not live-verified: these carry mutating verbs and were not probed during the 2026-08-01 testing (Appendix A, "Not verified").')
}

if ($contextUnresolvedComponents.Count -gt 0) {
    $mdLines.Add('')
    $mdLines.Add("### Unresolved `context_names` components ($($contextUnresolvedComponents.Count))")
    $mdLines.Add('')
    $mdLines.Add('These endpoints declare `context_names` with no resolvable `$ref` component, so their cardinality cannot be checked at all. They are **not** scored as size-1 -- doing so would hide a genuine multi-value endpoint behind the module''s size-1 throw.')
    $mdLines.Add('')
    foreach ($u in $contextUnresolvedComponents) { $mdLines.Add("- ``$($u.endpoint)``") }
}

$mdLines.Add('')

Set-Content -Path $ReportPath -Value ($mdLines -join "`n") -Encoding UTF8
Write-Host "Wrote API drift report to $OutputPath and $ReportPath" -ForegroundColor Green
