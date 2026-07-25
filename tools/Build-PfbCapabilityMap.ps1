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

$endpoints = [ordered]@{}
$processedVersions = [System.Collections.Generic.List[string]]::new()

foreach ($entry in $specFiles) {
    $version = "$($entry.Major).$($entry.Minor)"
    Write-Host "Processing $version ($($entry.File.Name))..." -ForegroundColor Cyan

    $spec = Get-Content -Path $entry.File.FullName -Raw | ConvertFrom-Json -Depth 64
    $capabilities = Get-PfbSpecCapabilities -Spec $spec

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

        # parameterComponents: which $ref component backs each parameter (e.g.
        # context_names -> Context_names_get). This describes the CURRENT wire shape, not
        # "introduced in version X" -- a version number attached to it would be
        # meaningless at best -- so it gets the same unconditional last-seen-wins
        # treatment as readOnlyBodyProperties, not the first-sight guard.
        # $cap.ParameterComponents is a typed Dictionary[string,string] (API parameter
        # names as keys) -- .get_Keys() avoids the live Hashtable-shadowing bug elsewhere
        # in this codebase (a key literally named "keys"/"count"/"values" hijacking
        # member access), and is used defensively even though a typed Dictionary does not
        # actually exhibit that shadowing the way a plain Hashtable does.
        # Emitted only when non-empty, same lean-manifest reasoning as readOnly above: a
        # parameter contributes an entry here only if it was declared via a "$ref" to a
        # components/parameters/* component -- plenty of endpoints have none.
        $paramComponents = [ordered]@{}
        foreach ($paramName in ($cap.ParameterComponents.get_Keys() | Sort-Object)) {
            $paramComponents[$paramName] = $cap.ParameterComponents[$paramName]
        }
        if ($paramComponents.Count -gt 0) {
            $entryRecord.parameterComponents = $paramComponents
        }
        elseif ($entryRecord.Contains('parameterComponents')) {
            $entryRecord.Remove('parameterComponents')
        }
    }

    $processedVersions.Add($version)
}

$manifest = [ordered]@{
    schemaVersion  = 1
    generatedFrom  = $processedVersions
    endpointCount  = $endpoints.Count
    endpoints      = $endpoints
}

$outputDir = Split-Path -Parent $OutputPath
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$manifest | ConvertTo-Json -Depth 20 | Set-Content -Path $OutputPath -Encoding UTF8

Write-Host ''
Write-Host "Wrote $($endpoints.Count) endpoints from $($processedVersions.Count) versions to $OutputPath" -ForegroundColor Green
