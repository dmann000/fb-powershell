<#
.SYNOPSIS
    Builds Data/PfbResponseShapeMap.json -- the response-side counterpart to
    Data/PfbCapabilityMap.json.
.DESCRIPTION
    For every endpoint with a 2xx JSON response, records the top-level envelope properties
    and the items[] element properties one level deep, each with the version it was first
    seen in, plus any that have since disappeared.

    THIS ARTIFACT HAS NO RUNTIME CONSUMER BY DESIGN. It is deliberately a separate file
    from Data/PfbCapabilityMap.json, which Private/Get-PfbCapabilityMap.ps1 lazily loads and
    caches into every user session: merging this axis in would cost +35% on every module
    import for data no runtime code reads. Nothing may gate an API call on response data --
    Assert-PfbApiCapability guards request construction only, and a missing response field
    is never a reason to refuse a call.

    Monotonicity rule -- first-seen for introduction, last-seen for presence:
      * responseEnvelope / responseItemProperties are {field: introducedVersion}, holding
        only fields still present in the endpoint's lastSeenVersion.
      * A field last seen before its endpoint's lastSeenVersion has been REMOVED and moves
        to removedResponseFields.
    This differs from readOnly's last-seen-wins because presence is what is tracked, not an
    attribute whose value flips.
.NOTES
    Does NOT fetch specs. Run tools/Update-PfbApiSpecs.ps1 separately and deliberately.
#>
[CmdletBinding()]
param(
    [string]$SpecsDirectory,
    [string]$OutputPath
)

# Deliberately NOT Set-StrictMode, matching tools/Build-PfbCapabilityMap.ps1. StrictMode is
# dynamically scoped, so setting it here would leak into the dot-sourced PfbSpecTools
# functions, which document (lib/PfbSpecTools.ps1:43) that they are intentionally
# null-tolerant walkers over heterogeneous spec nodes -- under StrictMode a response with no
# .content throws instead of being skipped, and real cached specs contain such responses.
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $SpecsDirectory) { $SpecsDirectory = Join-Path $PSScriptRoot 'specs' }
if (-not $OutputPath) { $OutputPath = Join-Path $repoRoot 'Data/PfbResponseShapeMap.json' }

. (Join-Path $PSScriptRoot 'lib/PfbSpecTools.ps1')

$specFiles = Get-ChildItem -Path $SpecsDirectory -Filter 'fb*.json' -ErrorAction SilentlyContinue
if (-not $specFiles) {
    throw "No cached specs found in '$SpecsDirectory'. Run Update-PfbApiSpecs.ps1 first."
}

# Numeric sort -- 'fb2.9' must precede 'fb2.10'. A string sort puts 2.9 above 2.27 and would
# invert the whole accumulation, turning every newer field into a phantom removal.
$specFiles = $specFiles | ForEach-Object {
    if ($_.BaseName -match '^fb(\d+)\.(\d+)$') {
        [PSCustomObject]@{ File = $_; Major = [int]$Matches[1]; Minor = [int]$Matches[2] }
    }
    else {
        Write-Warning "Skipping unrecognized spec filename: $($_.Name)"
        $null
    }
} | Where-Object { $_ } | Sort-Object Major, Minor

# Guard AGAIN on the parsed set, not just the glob. A directory whose fb*.json files all fail
# the version regex clears the check above, and without this the run would go on to write a
# well-formed artifact with an empty generatedFrom -- silently replacing the real
# Data/PfbResponseShapeMap.json with an empty one.
if (-not $specFiles) {
    throw "No spec files in '$SpecsDirectory' have a parseable fb<major>.<minor>.json name. Run Update-PfbApiSpecs.ps1 first."
}

# endpointKey -> record. Typed Dictionary, not a Hashtable: endpoint keys are safe, but the
# per-field dictionaries below hold API field names, where a field named 'keys'/'count'/
# 'values' would shadow real member access on a Hashtable.
$endpoints = [System.Collections.Generic.Dictionary[string, object]]::new()
$processedVersions = [System.Collections.Generic.List[string]]::new()

foreach ($entry in $specFiles) {
    $version = "$($entry.Major).$($entry.Minor)"
    Write-Host "Processing $version ($($entry.File.Name))..." -ForegroundColor Cyan
    $processedVersions.Add($version)

    $spec = Get-Content -Path $entry.File.FullName -Raw | ConvertFrom-Json -Depth 64
    # MaxDepth is left at the function's own default of 32 -- see its help. Do not pass 8.
    $shapes = Get-PfbSpecResponseShapes -Spec $spec

    foreach ($shape in $shapes) {
        $epKey = "$($shape.Method) $($shape.Path)"

        if (-not $endpoints.ContainsKey($epKey)) {
            $endpoints[$epKey] = [PSCustomObject]@{
                MinVersion      = $version
                LastSeenVersion = $version
                # field -> [PSCustomObject]@{ Introduced; LastSeen }
                Envelope        = [System.Collections.Generic.Dictionary[string, object]]::new()
                Items           = [System.Collections.Generic.Dictionary[string, object]]::new()
            }
        }

        $record = $endpoints[$epKey]
        $record.LastSeenVersion = $version

        foreach ($pair in @(
                @{ Names = $shape.EnvelopeProperties; Bag = $record.Envelope },
                @{ Names = $shape.ItemProperties; Bag = $record.Items }
            )) {
            foreach ($name in $pair.Names) {
                if ($pair.Bag.ContainsKey($name)) {
                    $pair.Bag[$name].LastSeen = $version
                }
                else {
                    $pair.Bag[$name] = [PSCustomObject]@{ Introduced = $version; LastSeen = $version }
                }
            }
        }
    }
}

$emitted = [ordered]@{}
foreach ($epKey in ($endpoints.get_Keys() | Sort-Object)) {
    $record = $endpoints[$epKey]

    $present = [ordered]@{ envelope = [ordered]@{}; items = [ordered]@{} }
    $removed = [System.Collections.Generic.List[object]]::new()

    foreach ($locationPair in @(
            @{ Location = 'envelope'; Bag = $record.Envelope },
            @{ Location = 'items'; Bag = $record.Items }
        )) {
        foreach ($name in ($locationPair.Bag.get_Keys() | Sort-Object)) {
            $field = $locationPair.Bag[$name]
            if ($field.LastSeen -eq $record.LastSeenVersion) {
                $present[$locationPair.Location][$name] = $field.Introduced
            }
            else {
                $removed.Add([ordered]@{
                        field             = $name
                        location          = $locationPair.Location
                        introducedVersion = $field.Introduced
                        lastSeenVersion   = $field.LastSeen
                    })
            }
        }
    }

    $endpointRecord = [ordered]@{
        minVersion             = $record.MinVersion
        lastSeenVersion        = $record.LastSeenVersion
        responseEnvelope       = $present['envelope']
        responseItemProperties = $present['items']
    }

    # Emitted only when non-empty -- across all 496 endpoints just 7 removal records exist, so
    # ~500 empty arrays would be pure noise in a tracked artifact. The count is 7 rather than
    # the larger number a naive version-to-version diff reports because "removed" here means
    # absent from the endpoint's own lastSeenVersion: a field that disappears for a single
    # version and then returns is still present in the newest spec and is deliberately NOT
    # counted. (Both known instances -- GET /active-directory at 2.12, GET /buckets/performance
    # at 2.20 -- were spec-authoring errors corrected in the following release.)
    if ($removed.Count -gt 0) {
        $endpointRecord.removedResponseFields = @($removed | Sort-Object { $_.location }, { $_.field })
    }

    $emitted[$epKey] = $endpointRecord
}

$manifest = [ordered]@{
    schemaVersion = 1
    generatedFrom = @($processedVersions)
    endpoints     = $emitted
}

$outputDirectory = Split-Path -Parent $OutputPath
if ($outputDirectory -and -not (Test-Path $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}

$manifest | ConvertTo-Json -Depth 20 | Set-Content -Path $OutputPath -Encoding UTF8
Write-Host "`nWrote $($emitted.Count) endpoints from $($processedVersions.Count) versions to $OutputPath"
