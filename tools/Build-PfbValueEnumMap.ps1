#Requires -Version 7.0
<#
.SYNOPSIS
    Builds the FlashBlade prose "Valid/Possible values" enum manifest from cached
    OpenAPI specs.
.DESCRIPTION
    Loads every cached tools/specs/fb<version>.json in ascending version order, extracts
    every prose-documented value enumeration (see tools/lib/PfbValueEnumTools.ps1) keyed
    by (SchemaName.PropertyName) or parameter component name, and diffs across versions
    to attribute each entry its earliest-seen ("introduced in") version. The current
    legal value set recorded for each entry reflects the newest processed version.

    This is data-extraction and validation only — it does NOT wire up ArgumentCompleters
    and does NOT change Assert-PfbApiCapability enforcement. See
    Value-Enum-Extraction-Work.md for the full design rationale and non-goals.

    Also writes a reconciliation report (Reports/PfbValueEnumReconciliation.md) comparing
    this newly extracted data against every existing hand-written `ValidateSet` in
    Public/ that encodes a spec-documented value enum. Report only — no Public/ cmdlet
    is edited by this script.
.PARAMETER SpecsDirectory
    Where cached spec JSON files live. Defaults to tools/specs relative to this script.
.PARAMETER OutputPath
    Where to write the manifest. Defaults to Reports/PfbValueEnumMap.json relative to the
    repo root (one level up from tools/). Reports/ is advisory output only, never read at
    runtime -- see Reports/README.md.
.PARAMETER ReconciliationPath
    Where to write the reconciliation report. Defaults to
    Reports/PfbValueEnumReconciliation.md relative to the repo root.
.EXAMPLE
    ./tools/Build-PfbValueEnumMap.ps1
#>
[CmdletBinding()]
param(
    [string]$SpecsDirectory,

    [string]$OutputPath,

    [string]$ReconciliationPath
)

$ErrorActionPreference = 'Stop'

$scriptDir = $PSScriptRoot
. (Join-Path $scriptDir 'lib/PfbSpecTools.ps1')
. (Join-Path $scriptDir 'lib/PfbValueEnumTools.ps1')

if (-not $SpecsDirectory) {
    $SpecsDirectory = Join-Path $scriptDir 'specs'
}
if (-not $OutputPath) {
    $repoRoot = Split-Path -Parent $scriptDir
    $OutputPath = Join-Path (Join-Path $repoRoot 'Reports') 'PfbValueEnumMap.json'
}
if (-not $ReconciliationPath) {
    $repoRoot = Split-Path -Parent $scriptDir
    $ReconciliationPath = Join-Path (Join-Path $repoRoot 'Reports') 'PfbValueEnumReconciliation.md'
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

# One record per (SchemaName.PropertyName) or parameter key, tracking the earliest
# version it was ever seen in (MinVersion) and the most recently processed version's
# record (LastRecord) — the latter supplies the "current legal value set" / current
# parsed-vs-unparsed status, since values and prose can change release to release.
#
# $seen is deliberately case-INSENSITIVE (PowerShell's [ordered]@{} default) rather than
# a stricter Ordinal comparer. Confirmed live: the real spec renames a schema's casing
# between versions (e.g. "SNMPAgent" in early REST versions to "SnmpAgent" by fb2.27) —
# NOT a squash-mode-style same-name-different-meaning collision, just a vendor casing
# convention change over time for the *same* logical schema. A case-sensitive dictionary
# would keep both as separate entries, which in turn produces a manifest JSON with two
# top-level keys differing only by case — and PowerShell's ConvertFrom-Json (producing a
# PSCustomObject, the idiom used everywhere else in this repo, including every consumer
# of this file) hard-errors on that ("Cannot convert the JSON string because it contains
# keys with different casing"). So each case-insensitive-equivalent group collapses to
# one entry, but — unlike a real squash-mode merge — nothing about its VALUES gets
# blended: .Key is re-recorded on every sighting so the final output uses whichever
# version's casing was seen LAST (i.e. matches the newest/current spec), while
# MinVersion still reflects the earliest sighting under any casing.
$seen = [ordered]@{}
$processedVersions = [System.Collections.Generic.List[string]]::new()

foreach ($entry in $specFiles) {
    $version = "$($entry.Major).$($entry.Minor)"
    Write-Host "Processing $version ($($entry.File.Name))..." -ForegroundColor Cyan

    $spec = Get-Content -Path $entry.File.FullName -Raw | ConvertFrom-Json -Depth 64
    $valueEnums = Get-PfbSpecValueEnums -Spec $spec

    foreach ($rec in $valueEnums) {
        if (-not $seen.Contains($rec.Key)) {
            $seen[$rec.Key] = [ordered]@{
                Key        = $rec.Key
                Kind       = $rec.Kind
                Name       = $rec.Name
                MinVersion = $version
                LastRecord = $rec
            }
        }
        else {
            $seen[$rec.Key].Key = $rec.Key
            $seen[$rec.Key].LastRecord = $rec
        }
    }

    $processedVersions.Add($version)
}

$entries = [ordered]@{}
$unparsed = [System.Collections.Generic.List[object]]::new()

foreach ($key in $seen.Keys) {
    $s = $seen[$key]
    if ($s.LastRecord.Parsed) {
        $entries[$s.Key] = [ordered]@{
            values     = $s.LastRecord.Values
            minVersion = $s.MinVersion
            kind       = $s.Kind
            name       = $s.Name
        }
    }
    else {
        $unparsed.Add([ordered]@{
            key         = $s.Key
            kind        = $s.Kind
            name        = $s.Name
            version     = $s.MinVersion
            triggerText = $s.LastRecord.TriggerText
        })
    }
}

$manifest = [ordered]@{
    schemaVersion = 1
    generatedFrom = $processedVersions
    entryCount    = $entries.Count
    unparsedCount = $unparsed.Count
    entries       = $entries
    unparsed      = $unparsed
}

$outputDir = Split-Path -Parent $OutputPath
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$manifest | ConvertTo-Json -Depth 20 | Set-Content -Path $OutputPath -Encoding UTF8

Write-Host ''
Write-Host "Wrote $($entries.Count) entries ($($unparsed.Count) unparsed) from $($processedVersions.Count) versions to $OutputPath" -ForegroundColor Green

# --- Reconciliation against existing hand-written ValidateSets in Public/ ---
# Every ValidateSet found (as of this writing) whose values encode a spec-documented
# value enum, excluding Invoke-PfbApiRequest.ps1's HTTP-verb ValidateSet (not spec data).
# "Name" here is the field's wire name (request-body key or query-parameter name), which
# is what Get-PfbSpecValueEnums records as each entry's .name — see its header comment
# for why that differs from a parameter's components.parameters dictionary key.
# "ResourceHint" is a prefix filter on the schema half of an entry's Key (e.g.
# 'NetworkInterface' matches 'NetworkInterface.services' and 'NetworkInterfacePatch.services'
# but not an unrelated schema that happens to share the property name 'services'). This is
# NOT a real field->cmdlet/endpoint mapping (explicitly out of scope for this phase — see
# Value-Enum-Extraction-Work.md) — it is a best-effort disambiguation to avoid a false
# "stale"/"exact-match" claim built on an unrelated schema's same-named field. A field name
# common enough to appear on many resources (protocol, type) can still legitimately collide
# even after hint-filtering; that is reported as 'collision', not force-resolved.
$handWritten = @(
    [PSCustomObject]@{ File = 'Public/Alert/New-PfbAlertWatcher.ps1'; Line = 22; Parameter = '-MinimumSeverity'; Name = 'minimum_notification_severity'; ResourceHint = 'AlertWatcher'; Values = @('info', 'warning', 'error', 'critical') }
    [PSCustomObject]@{ File = 'Public/Alert/Update-PfbAlertWatcher.ps1'; Line = 29; Parameter = '-MinimumSeverity'; Name = 'minimum_notification_severity'; ResourceHint = 'AlertWatcher'; Values = @('info', 'warning', 'critical') }
    [PSCustomObject]@{ File = 'Public/Bucket/New-PfbBucket.ps1'; Line = 29; Parameter = '-Versioning'; Name = 'versioning'; ResourceHint = 'Bucket'; Values = @('enabled', 'suspended', 'none') }
    [PSCustomObject]@{ File = 'Public/Bucket/Update-PfbBucket.ps1'; Line = 31; Parameter = '-Versioning'; Name = 'versioning'; ResourceHint = 'Bucket'; Values = @('enabled', 'suspended', 'none') }
    # '_multiProtocol' is the actual nested body-object schema name for this field (confirmed
    # by direct spec inspection) — a literal alias, not a fuzzy resource-name guess.
    [PSCustomObject]@{ File = 'Public/FileSystem/New-PfbFileSystem.ps1'; Line = 179; Parameter = '-MultiProtocolAccessControlStyle'; Name = 'access_control_style'; ResourceHint = @('FileSystem', '_multiProtocol'); Values = @('nfs', 'smb', 'shared', 'independent', 'mode-bits') }
    [PSCustomObject]@{ File = 'Public/FileSystem/New-PfbFileSystem.ps1'; Line = 192; Parameter = '-GroupOwnership'; Name = 'group_ownership'; ResourceHint = 'FileSystem'; Values = @('creator', 'parent-directory') }
    [PSCustomObject]@{ File = 'Public/FileSystem/Update-PfbFileSystem.ps1'; Line = 97; Parameter = '-RequestedPromotionState'; Name = 'requested_promotion_state'; ResourceHint = 'FileSystem'; Values = @('promoted', 'demoted') }
    [PSCustomObject]@{ File = 'Public/Array/Get-PfbArrayPerformance.ps1'; Line = 37; Parameter = '-Protocol'; Name = 'protocol'; ResourceHint = $null; Values = @('nfs', 'smb', 'http', 's3') }
    [PSCustomObject]@{ File = 'Public/Network/New-PfbNetworkInterface.ps1'; Line = 52; Parameter = '-Services'; Name = 'services'; ResourceHint = 'NetworkInterface'; Values = @('data', 'egress-only', 'management', 'replication', 'support') }
    [PSCustomObject]@{ File = 'Public/Network/New-PfbNetworkInterface.ps1'; Line = 59; Parameter = '-Type'; Name = 'type'; ResourceHint = 'NetworkInterface'; Values = @('vip') }
)

function Test-PfbValueSetsEqual {
    param([string[]]$A, [string[]]$B)
    $setA = [System.Collections.Generic.HashSet[string]]::new([string[]]$A)
    $setB = [System.Collections.Generic.HashSet[string]]::new([string[]]$B)
    return $setA.SetEquals($setB)
}

$reconciliation = foreach ($hw in $handWritten) {
    $allMatches = @($entries.Keys | Where-Object { $entries[$_].name -eq $hw.Name } | ForEach-Object {
        [PSCustomObject]@{ Key = $_; Values = $entries[$_].values }
    })

    # Strict prefix (not substring-contains): "NetworkInterface*" must correctly exclude
    # the unrelated "_networkInterfaceNeighbor*" private schemas (a real collision found
    # live) — those start with an underscore, so a plain prefix check already excludes
    # them without needing a word-boundary check. Known private nested-object schemas
    # that don't share the resource's own name prefix are listed as explicit extra hints
    # above (e.g. '_multiProtocol'), not matched via a
    # looser "contains" rule that would just reopen the same false-positive risk.
    $hints = @($hw.ResourceHint) | Where-Object { $_ }
    $candidates = if ($hints.Count -gt 0) {
        @($allMatches | Where-Object {
            $entryKey = $_.Key
            @($hints | Where-Object { $entryKey -like "$_*" }).Count -gt 0
        })
    }
    else {
        $allMatches
    }

    $status = $null
    $specValues = $null
    $note = ''

    if ($candidates.Count -eq 0 -and $allMatches.Count -eq 0) {
        $status = 'not-found'
    }
    elseif ($candidates.Count -eq 0) {
        # The field name exists elsewhere in the spec, just not under this cmdlet's own
        # resource — do not claim exact-match/stale against an unrelated schema.
        $status = 'not-found-in-resource'
        $note = "field '$($hw.Name)' not found under any of [$($hints -join ', ')]-hinted schemas; found elsewhere: $($allMatches.Key -join '; ')"
    }
    else {
        $distinctValueSets = $candidates | ForEach-Object { ($_.Values | Sort-Object) -join ',' } | Select-Object -Unique
        if (@($distinctValueSets).Count -gt 1) {
            $status = 'collision'
            $note = "matches $($candidates.Count) distinct (schema, property) entries with different value sets: $($candidates.Key -join '; ')"
        }
        else {
            $specValues = $candidates[0].Values
            $status = if (Test-PfbValueSetsEqual -A $hw.Values -B $specValues) { 'exact-match' } else { 'stale' }
            if ($status -eq 'stale') {
                $missing = $specValues | Where-Object { $_ -notin $hw.Values }
                $extra = $hw.Values | Where-Object { $_ -notin $specValues }
                $parts = @()
                if ($missing) { $parts += "spec has but hand-written set is missing: $($missing -join ', ')" }
                if ($extra) { $parts += "hand-written set has but spec does not list: $($extra -join ', ')" }
                $note = $parts -join '; '
            }
        }
    }

    [PSCustomObject]@{
        File       = $hw.File
        Line       = $hw.Line
        Parameter  = $hw.Parameter
        HandValues = $hw.Values -join ', '
        SpecValues = if ($specValues) { $specValues -join ', ' } else { '' }
        Status     = $status
        Note       = $note
    }
}

Write-Host ''
Write-Host 'Reconciliation against hand-written ValidateSets:' -ForegroundColor Cyan
$reconciliation | Format-Table File, Parameter, Status, Note -AutoSize | Out-String | Write-Host

$mdLines = [System.Collections.Generic.List[string]]::new()
$mdLines.Add('# Value-Enum Reconciliation Report')
$mdLines.Add('')
$mdLines.Add("Generated by ``tools/Build-PfbValueEnumMap.ps1`` against ``Reports/PfbValueEnumMap.json`` ($($processedVersions.Count) REST versions, $($entries.Count) entries).")
$mdLines.Add('')
$mdLines.Add('Compares every hand-written `ValidateSet` in `Public/` that encodes a spec-documented value enum against the newly extracted prose data. Report only — no `Public/` cmdlet is edited by this script. See `Value-Enum-Extraction-Work.md` for the full non-goal list.')
$mdLines.Add('')
$mdLines.Add('| File:Line | Parameter | Hand-written values | Spec values | Status | Note |')
$mdLines.Add('|---|---|---|---|---|---|')
foreach ($r in $reconciliation) {
    $mdLines.Add("| ``$($r.File):$($r.Line)`` | ``$($r.Parameter)`` | $($r.HandValues) | $($r.SpecValues) | **$($r.Status)** | $($r.Note) |")
}
$mdLines.Add('')

Set-Content -Path $ReconciliationPath -Value ($mdLines -join "`n") -Encoding UTF8
Write-Host "Wrote reconciliation report to $ReconciliationPath" -ForegroundColor Green
