#Requires -Version 7.0
<#
.SYNOPSIS
    Builds the FlashBlade API capability manifest from cached OpenAPI specs.
.DESCRIPTION
    Loads every cached tools/specs/fb<version>.json in ascending version order and
    records, for each (HTTP method, normalized path), the earliest version it appears
    in — and likewise for each parameter name and request-body top-level property name
    on that endpoint. This is the data Phase 2's per-cmdlet capability check and Phase
    3's version-aware ArgumentCompleters will consume.

    Deliberately NOT included: per-enum-value "introduced in version X" tracking. The
    FlashBlade OpenAPI spec has no structural JSON Schema `enum` anywhere (verified
    against fb2.10 and fb2.27) — allowed values are documented only in free-text
    `description` prose, which is not reliably machine-diffable. See
    tools/lib/PfbSpecTools.ps1 for the full finding.

    Also NOT included (deferred, see plan): endpoint/field deprecation or removal
    tracking, and hardware-model (//S vs //E) capability — that is a separate axis from
    REST version and is handled in a later phase from a different data source.

    Each endpoint also carries, where non-empty, readOnlyBodyProperties and
    deprecatedBodyProperties (string arrays) -- both last-seen-wins (the newest spec that
    mentions the endpoint always wins), NOT first-sight like minVersion/parameters/
    bodyProperties, because readOnly is not monotonic across versions (a field can go
    read-only -> writable, and about half the observed flips in fb2.0-2.27 do exactly
    that; persisting first-sight would silently hide genuinely settable fields).

    parameterComponentDefaults/parameterComponentOverrides resolution contract (also
    documented in tools/README.md): the component backing a given (endpoint, parameter)
    is looked up as (1) the endpoint's parameterComponentOverrides value for that
    parameter name if present -- which may be JSON null, meaning "this endpoint's
    parameter has no component" -- otherwise (2) the top-level parameterComponentDefaults
    value for that parameter name if present, otherwise (3) no known component. Split
    into a global table plus per-endpoint overrides (rather than one full map per
    endpoint) because the vast majority of parameters share a small set of common
    components: measured across fb2.0-2.27, 4102 total (endpoint, parameter) -> component
    pairs collapse to just 224 distinct pairs and 179 distinct parameter names. Defaults
    are chosen by frequency (most common component per parameter name across all
    endpoints), ties broken ALPHABETICALLY by component name for determinism regardless
    of endpoint processing order. The explicit-null-override case matters: a parameter
    declared inline (no "$ref", so no component) whose NAME happens to coincide with a
    $ref'd component elsewhere must get an explicit null override, or "absent from
    overrides" would wrongly make it inherit that unrelated default.
.PARAMETER SpecsDirectory
    Where cached spec JSON files live. Defaults to tools/specs relative to this script.
.PARAMETER OutputPath
    Where to write the manifest. Defaults to Data/PfbCapabilityMap.json relative to the
    repo root (one level up from tools/).
.PARAMETER MaxVersion
    Optional inclusive upper bound on REST version to ingest, e.g. '2.27'. Compared
    numerically (Major, then Minor as integers) using the same parsing already used to
    sort $specFiles below -- NOT a string compare, since '2.9' sorts above '2.27' as a
    string. Defaults to $null, meaning no cap: every cached spec under -SpecsDirectory is
    ingested (unchanged default behaviour, so CI is unaffected). Exists so a rebuild can be
    pinned to a known spec set without deleting newer files out of tools/specs/ --
    adopting a newly-cached version's data is a separate, deliberate decision, not a side
    effect of this script simply seeing a new file on disk.
.EXAMPLE
    ./tools/Build-PfbCapabilityMap.ps1
.EXAMPLE
    ./tools/Build-PfbCapabilityMap.ps1 -MaxVersion 2.27
#>
[CmdletBinding()]
param(
    [string]$SpecsDirectory,

    [string]$OutputPath,

    [string]$MaxVersion
)

$ErrorActionPreference = 'Stop'

$scriptDir = $PSScriptRoot
. (Join-Path $scriptDir 'lib/PfbSpecTools.ps1')

if (-not $SpecsDirectory) {
    $SpecsDirectory = Join-Path $scriptDir 'specs'
}
if (-not $OutputPath) {
    $repoRoot = Split-Path -Parent $scriptDir
    $OutputPath = Join-Path (Join-Path $repoRoot 'Data') 'PfbCapabilityMap.json'
}

$specFiles = Get-ChildItem -Path $SpecsDirectory -Filter 'fb*.json' -ErrorAction SilentlyContinue
if (-not $specFiles) {
    throw "No cached specs found in '$SpecsDirectory'. Run Update-PfbApiSpecs.ps1 first."
}

# Sort by numeric version, not filename string (fb2.9 must sort before fb2.10).
$specFiles = $specFiles | ForEach-Object {
    if ($_.BaseName -match '^fb(\d+)\.(\d+)$') {
        [PSCustomObject]@{
            File  = $_
            Major = [int]$Matches[1]
            Minor = [int]$Matches[2]
        }
    }
    else {
        Write-Warning "Skipping unrecognized spec filename: $($_.Name)"
        $null
    }
} | Where-Object { $_ } | Sort-Object Major, Minor

if ($MaxVersion) {
    if ($MaxVersion -notmatch '^(\d+)\.(\d+)$') {
        throw "-MaxVersion must be in 'Major.Minor' form (e.g. '2.27'), got '$MaxVersion'."
    }
    # Reuse the same Major/Minor int parsing as the sort above -- a string compare would
    # wrongly place e.g. '2.9' above '2.27' (this exact bug has been found twice already).
    $capMajor = [int]$Matches[1]
    $capMinor = [int]$Matches[2]
    $beforeCount = @($specFiles).Count
    $specFiles = @($specFiles | Where-Object {
            $_.Major -lt $capMajor -or ($_.Major -eq $capMajor -and $_.Minor -le $capMinor)
        })
    Write-Host "MaxVersion $MaxVersion applied: including $($specFiles.Count) of $beforeCount cached specs." -ForegroundColor Yellow
}

# ---- Fusion context scope ----
#
# Curated scope values for endpoints upstream has flagged x-pure-incomplete-gre, where the
# ABSENCE of a domains override carries no information. Every entry here was established by
# live testing, not inference.
#
# This table lives in the GENERATOR, never in Private/. Runtime code reads scope from the
# shipped map and nowhere else -- a curated list consulted at runtime would be a second
# source of truth for the same fact, which is the failure mode issue #74 exists to fix.
#
# Each entry retires as upstream fills in the corresponding override. The drift test in
# Tests/Build-PfbCapabilityMap.ContextScopeDrift.Tests.ps1 fails when that happens, so the
# table shrinks on its own instead of quietly shadowing better data.
$curatedContextScope = @{
    'GET /topology-groups'         = 'fleet'
    'GET /topology-groups/arrays'  = 'fleet'
    'GET /topology-groups/members' = 'fleet'
    'GET /workloads/tags'          = 'array'
}

$endpoints = [ordered]@{}
$processedVersions = [System.Collections.Generic.List[string]]::new()

foreach ($entry in $specFiles) {
    $version = "$($entry.Major).$($entry.Minor)"
    Write-Host "Processing $version ($($entry.File.Name))..." -ForegroundColor Cyan

    $spec = Get-Content -Path $entry.File.FullName -Raw | ConvertFrom-Json -Depth 64
    $capabilities = Get-PfbSpecCapabilities -Spec $spec

    # Index this version's remote-execution annotations by endpoint key. Read per version
    # and applied last-seen-wins, same as readOnlyBodyProperties -- a resource does not
    # migrate between the fleet database and an array, so the newest annotation is simply
    # the best one, and no first-sight guard is wanted here.
    $contextScopeByEndpoint = @{}
    foreach ($scopeRecord in (Get-PfbSpecContextScope -Spec $spec)) {
        $contextScopeByEndpoint[$scopeRecord.Endpoint] = $scopeRecord
    }

    foreach ($cap in $capabilities) {
        $epKey = "$($cap.Method) $($cap.Path)"

        if (-not $endpoints.Contains($epKey)) {
            $endpoints[$epKey] = [ordered]@{
                minVersion     = $version
                parameters     = [ordered]@{}
                bodyProperties = [ordered]@{}
            }
        }
        $entryRecord = $endpoints[$epKey]

        foreach ($paramName in $cap.Parameters) {
            if (-not $entryRecord.parameters.Contains($paramName)) {
                $entryRecord.parameters[$paramName] = $version
            }
        }
        foreach ($propName in $cap.BodyProperties) {
            if (-not $entryRecord.bodyProperties.Contains($propName)) {
                $entryRecord.bodyProperties[$propName] = $version
            }
        }

        # Decision 1 -- readOnly is NOT monotonic across versions: 58 of 1264 analysed
        # (endpoint, body-field) pairs flip their readOnly flag somewhere in fb2.0-2.27,
        # and most flips go read-only -> writable. Unlike parameters/bodyProperties above
        # (genuinely monotonic "introduced in version X", correctly guarded by first-sight
        # above), readOnlyBodyProperties must be assigned UNCONDITIONALLY every iteration
        # so the newest-processed spec always wins -- never guarded by "only if not
        # already present". Persisting first-sight here would silently suppress
        # genuinely settable fields from the actionable gap list -- e.g.
        # PATCH /api-clients|max_role, read-only in older specs and writable in 2.27 --
        # and a missing gap is far worse than a noisy one. Because $specFiles is
        # processed in ascending version order, "unconditional" is simply "overwrite each
        # time"; an endpoint absent from a later spec is simply not visited that
        # iteration, so it naturally keeps its last-seen value for free.
        # Emitted only when non-empty (same "keep the manifest lean" rule as deprecated
        # below): most operations have no read-only body fields at all, and writing
        # "readOnlyBodyProperties": [] on all ~520 of them would roughly 14x the actual
        # ~15KB growth budget for zero information gain. Absence IS the empty-set here.
        if ($cap.ReadOnlyBodyProperties -and @($cap.ReadOnlyBodyProperties).Count -gt 0) {
            $entryRecord.readOnlyBodyProperties = @($cap.ReadOnlyBodyProperties | Sort-Object)
        }
        elseif ($entryRecord.Contains('readOnlyBodyProperties')) {
            $entryRecord.Remove('readOnlyBodyProperties')
        }

        # deprecated: emit the key only when non-empty (true for zero top-level
        # request-body properties across all 28 analysed specs today -- the sole
        # "deprecated" occurrence in the whole surface is a nested, readOnly,
        # response-only field -- so this key will not appear in today's manifest at all,
        # which is correct). Same last-seen-wins reasoning as readOnly: if the
        # newest-seen version for this endpoint has no deprecated fields, remove any
        # stale key from an earlier version rather than leaving it behind.
        if ($cap.DeprecatedBodyProperties -and @($cap.DeprecatedBodyProperties).Count -gt 0) {
            $entryRecord.deprecatedBodyProperties = @($cap.DeprecatedBodyProperties | Sort-Object)
        }
        elseif ($entryRecord.Contains('deprecatedBodyProperties')) {
            $entryRecord.Remove('deprecatedBodyProperties')
        }

        # contextScope: fleet-scoped vs array-scoped, plus where the answer came from.
        # Assigned UNCONDITIONALLY (last-seen-wins), not first-sight -- see the indexing
        # comment above. Phase 0 SHIPS this field and nothing reads it at runtime; Phase 1's
        # kind-vs-scope validation and scope-aware error messages consume it.
        $scopeRecord = $contextScopeByEndpoint[$epKey]
        $scopeValue = 'array'
        $scopeProvenance = 'default'
        if ($scopeRecord -and @($scopeRecord.DomainsOverride).Count -gt 0) {
            # Declared domains are authoritative. FLEET-only means fleet-scoped; anything
            # that also accepts ARRAY is usable array-scoped, which is what Phase 1 needs
            # to know.
            #
            # An unrecognised domain token falls to unknown/unknown rather than to 'fleet'.
            # Only ARRAY and FLEET occur across all 29 cached specs today (measured), so this
            # branch is unreachable -- but treating a token we cannot interpret as 'fleet'
            # would assert a scope on no evidence AND stamp it provenance='declared', which
            # reads as "upstream told us" to Phase 1. Recording ignorance is the honest
            # failure mode, and it is the same one the flagged-but-uncurated case uses.
            $declaredDomains = @($scopeRecord.DomainsOverride | ForEach-Object { "$_".ToUpperInvariant() })
            if ($declaredDomains -contains 'ARRAY') {
                $scopeValue = 'array'
                $scopeProvenance = 'declared'
            }
            elseif ($declaredDomains -contains 'FLEET') {
                $scopeValue = 'fleet'
                $scopeProvenance = 'declared'
            }
            else {
                $scopeValue = 'unknown'
                $scopeProvenance = 'unknown'
            }
        }
        elseif ($curatedContextScope.ContainsKey($epKey)) {
            $scopeValue = $curatedContextScope[$epKey]
            $scopeProvenance = 'live-tested'
        }
        elseif ($scopeRecord -and $scopeRecord.IsIncompleteGre) {
            # Flagged incomplete and not curated: the absent override proves nothing, so
            # recording 'array' would assert something unevidenced. 'unknown' suppresses
            # kind-vs-scope validation in Phase 1 and leaves today's behaviour.
            $scopeValue = 'unknown'
            $scopeProvenance = 'unknown'
        }
        $entryRecord.contextScope = [ordered]@{
            scope      = $scopeValue
            provenance = $scopeProvenance
        }

        # parameterComponents bookkeeping -- which $ref component backs each parameter
        # (e.g. context_names -> Context_names_get) for the CURRENT (last-seen) version of
        # this endpoint, plus which of this endpoint's CURRENT parameters have NO
        # component at all (declared inline, no "$ref"). This describes the CURRENT wire
        # shape, not "introduced in version X" -- a version number attached to it would be
        # meaningless at best -- so both are overwritten UNCONDITIONALLY every iteration,
        # same last-seen-wins treatment as readOnlyBodyProperties above, not the
        # first-sight guard.
        #
        # These two "_current*" keys are TEMPORARY per-build bookkeeping, not part of the
        # manifest's public shape: a full per-endpoint component map would be ~90% pure
        # duplication (measured: 4102 total (parameter, component) pairs across fb2.0-2.27
        # but only 224 distinct pairs and 179 distinct parameter names -- most endpoints
        # just reuse the same shared "Filter"/"Limit"/"Sort"/etc. components), which blew
        # the manifest's lean-growth budget ~12x when first tried. The second pass below
        # (after every spec is processed) deduplicates this into a single
        # parameterComponentDefaults table plus minimal per-endpoint
        # parameterComponentOverrides, then strips these bookkeeping keys back out.
        #
        # $cap.ParameterComponents is a typed Dictionary[string,string] (API parameter
        # names as keys) -- .get_Keys() avoids the live Hashtable-shadowing bug elsewhere
        # in this codebase (a key literally named "keys"/"count"/"values" hijacking member
        # access), used defensively even though a typed Dictionary does not actually
        # exhibit that shadowing the way a plain Hashtable/OrderedDictionary does.
        $currentParamComponents = [System.Collections.Generic.Dictionary[string, string]]::new()
        foreach ($paramName in ($cap.ParameterComponents.get_Keys() | Sort-Object)) {
            $currentParamComponents[$paramName] = $cap.ParameterComponents[$paramName]
        }
        $entryRecord['_currentParamComponents'] = $currentParamComponents

        $currentParamsWithoutComponent = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($paramName in ($cap.Parameters | Select-Object -Unique)) {
            if (-not $currentParamComponents.ContainsKey($paramName)) {
                [void]$currentParamsWithoutComponent.Add($paramName)
            }
        }
        $entryRecord['_currentParamsWithoutComponent'] = $currentParamsWithoutComponent
    }

    $processedVersions.Add($version)
}

# ---- Second pass: deduplicate parameterComponents into a global defaults table plus
# minimal per-endpoint overrides ----
#
# Resolution contract (also documented in tools/README.md): for a given (endpoint,
# parameter), the effective component is:
#   1. If the endpoint's parameterComponentOverrides contains the parameter name, use
#      that value -- which may be JSON null, meaning "this endpoint's parameter has no
#      component" (see below). This takes precedence over the default.
#   2. Otherwise, if parameterComponentDefaults contains the parameter name, use that
#      value.
#   3. Otherwise, the parameter has no known component.
#
# Deterministic default selection: for each parameter name, count how often each
# component name occurs across every endpoint's CURRENT (last-seen) mapping, and pick
# the MOST FREQUENT; ties are broken ALPHABETICALLY by component name. This must be
# fully deterministic across builds regardless of endpoint processing order -- frequency
# counting alone is not enough when two components are equally common for a parameter
# name (this happens; do not assume it can't).
$componentCountsByParam = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.Dictionary[string, int]]]::new()
foreach ($epKey in $endpoints.get_Keys()) {
    $paramComponents = $endpoints[$epKey]['_currentParamComponents']
    foreach ($paramName in $paramComponents.get_Keys()) {
        if (-not $componentCountsByParam.ContainsKey($paramName)) {
            $componentCountsByParam[$paramName] = [System.Collections.Generic.Dictionary[string, int]]::new()
        }
        $componentName = $paramComponents[$paramName]
        $counts = $componentCountsByParam[$paramName]
        if (-not $counts.ContainsKey($componentName)) { $counts[$componentName] = 0 }
        $counts[$componentName]++
    }
}

$parameterComponentDefaults = [ordered]@{}
foreach ($paramName in ($componentCountsByParam.get_Keys() | Sort-Object)) {
    $counts = $componentCountsByParam[$paramName]
    $best = $counts.get_Keys() |
        Sort-Object @{ Expression = { $counts[$_] }; Descending = $true }, @{ Expression = { $_ }; Descending = $false } |
        Select-Object -First 1
    $parameterComponentDefaults[$paramName] = $best
}

# Per-endpoint overrides: emitted only where this endpoint's CURRENT value differs from
# the global default for that parameter name, OR where this endpoint's parameter
# currently has NO component (inline, no "$ref") but the parameter NAME does have a
# global default from some other endpoint -- an explicit JSON null override records "no
# component here", distinguishing it from "absent", which would otherwise silently
# resolve to the (wrong) default under the lookup contract above. This is the subtle
# case: only 7 of 4109 parameter declarations in fb2.27 are inline/no-$ref, but every one
# whose name collides with a global default MUST get a null override or it would
# misreport a component it does not actually have.
foreach ($epKey in $endpoints.get_Keys()) {
    $rec = $endpoints[$epKey]
    $paramComponents = $rec['_currentParamComponents']
    $paramsWithoutComponent = $rec['_currentParamsWithoutComponent']

    $overrides = [ordered]@{}
    foreach ($paramName in $paramComponents.get_Keys()) {
        $componentName = $paramComponents[$paramName]
        if ($componentName -ne $parameterComponentDefaults[$paramName]) {
            $overrides[$paramName] = $componentName
        }
    }
    foreach ($paramName in $paramsWithoutComponent) {
        if ($parameterComponentDefaults.Contains($paramName)) {
            $overrides[$paramName] = $null
        }
    }

    if ($overrides.get_Count() -gt 0) {
        # Re-sort: the two loops above each insert in their own sorted order, but their
        # combination is not necessarily sorted overall.
        $sortedOverrides = [ordered]@{}
        foreach ($paramName in ($overrides.get_Keys() | Sort-Object)) {
            $sortedOverrides[$paramName] = $overrides[$paramName]
        }
        $rec.parameterComponentOverrides = $sortedOverrides
    }

    $rec.Remove('_currentParamComponents')
    $rec.Remove('_currentParamsWithoutComponent')
}

$manifest = [ordered]@{
    schemaVersion              = 2
    generatedFrom              = $processedVersions
    endpointCount              = $endpoints.Count
    parameterComponentDefaults = $parameterComponentDefaults
    endpoints                  = $endpoints
}

$outputDir = Split-Path -Parent $OutputPath
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$manifest | ConvertTo-Json -Depth 20 | Set-Content -Path $OutputPath -Encoding UTF8

Write-Host ''
Write-Host "Wrote $($endpoints.Count) endpoints from $($processedVersions.Count) versions to $OutputPath" -ForegroundColor Green
