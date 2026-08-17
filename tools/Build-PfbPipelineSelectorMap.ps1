#Requires -Version 7.0
<#
.SYNOPSIS
    Builds Reports/PfbPipelineSelectorMap.json and .md -- "can a piped object bind this cmdlet's
    selector, or does it stringify into the filter?" (issue #90).
.DESCRIPTION
    PowerShell resolves pipeline binding in FOUR passes: ByValue, ByPropertyName, ByValue WITH
    COERCION, then ByPropertyName WITH COERCION. If a piped object has no property matching any
    pipeline-bound parameter, pass 3 fires and ToString()s the whole object into a [string[]]
    selector, producing a query filter like

        remote_names=@{id=10314f42-aaaa; status=connected; remote=}

    which the array either rejects or, worse, silently ignores -- returning every record
    unfiltered. On a Remove-* cmdlet that is a wider blast radius than the caller intended. See
    #64 for the specific instance and the guard that fixed it.

    Do NOT assume that removing ValueFromPipeline makes coercion impossible. Pass 4 is
    ByPropertyName WITH COERCION, so a ValueFromPipelineByPropertyName-only parameter whose ALIAS
    matches an object-valued property still binds that object stringified. Measured on pwsh 7.6.4.
    Detection is unaffected -- a pass-4 coercion still contains '@{' and still reads Coerced -- but
    the remedy differs: such a parameter needs a guard, not an attribute removal.

    Every verdict here is OBSERVED, never inferred. The generator imports the shipped module,
    shadows Invoke-PfbApiRequest inside module scope with a capture shim, pipes a schema-derived
    probe object into the real cmdlet, and records what reached the wire. Nothing is a finding
    unless a probe produced it. That is the direct lesson of #89, which was closed as a false
    positive after its evidence turned out to come from a hand-written stand-in rather than the
    real module.

    NO NETWORK ACCESS. Initialize-PfbSelectorHarness verifies the shim is live and throws rather
    than probe if it cannot prove its own isolation -- the silent failure mode of the shadowing
    is a real HTTP call, which on a Remove-* probe would be a live DELETE.

    Producers are GET endpoints only: the cmdlet's own GET, others in its resource family, and
    chains the module documents in its own help. Extending to New-*/Update-* producers was sized
    and rejected -- 230 of 241 non-GET endpoints return a shape identical to their GET
    counterpart, and of the 11 that differ, 6 drop only `context` and 4 return an operation result
    rather than a resource.
.PARAMETER SpecsDirectory
    Cached OpenAPI specs. Defaults to tools/specs.
.PARAMETER OutputPath
    JSON output. Defaults to Reports/PfbPipelineSelectorMap.json. The .md companion is written
    alongside it, with the same base name.
.NOTES
    Does NOT fetch specs. Run tools/Update-PfbApiSpecs.ps1 separately and deliberately.

    PowerShell 7 only, like every other tools/Build-*.ps1 -- this is developer/CI tooling and CI
    runs it on pwsh 7 / ubuntu. The module it imports still supports Windows PowerShell 5.1.
#>
[CmdletBinding()]
param(
    [string]$SpecsDirectory,
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $SpecsDirectory) { $SpecsDirectory = Join-Path $PSScriptRoot 'specs' }
if (-not $OutputPath) { $OutputPath = Join-Path $repoRoot 'Reports/PfbPipelineSelectorMap.json' }
$markdownPath = [System.IO.Path]::ChangeExtension($OutputPath, '.md')

. (Join-Path $PSScriptRoot 'lib/PfbSpecTools.ps1')
. (Join-Path $PSScriptRoot 'lib/PfbCmdletParamTools.ps1')
. (Join-Path $PSScriptRoot 'lib/PfbPipelineSelectorTools.ps1')
. (Join-Path $PSScriptRoot 'lib/PfbSelectorProbeHarness.ps1')

# tools/specs is gitignored, and its absence silently skips ~27 drift tests elsewhere in this
# repo -- reported as a pass. A generator whose output is a regression baseline must not inherit
# that failure mode, so refuse rather than emit a thinner report that looks complete.
$specFiles = @(Get-ChildItem -Path $SpecsDirectory -Filter 'fb*.json' -ErrorAction SilentlyContinue)
if (-not $specFiles.Count) {
    throw "No cached specs found in '$SpecsDirectory'. Run Update-PfbApiSpecs.ps1 first."
}

# Newest spec decides response item TYPES. Property names come from the response-shape map, which
# already accumulates across every version; only the types need a single spec to read.
$newestSpec = $specFiles | ForEach-Object {
    if ($_.BaseName -match '^fb(\d+)\.(\d+)$') {
        [PSCustomObject]@{ File = $_; Major = [int]$Matches[1]; Minor = [int]$Matches[2] }
    }
} | Sort-Object Major, Minor | Select-Object -Last 1

if (-not $newestSpec) { throw "No spec in '$SpecsDirectory' matched the expected fb<major>.<minor>.json naming." }

$module = Initialize-PfbSelectorHarness -ManifestPath (Join-Path $repoRoot 'PureStorageFlashBladePowerShell.psd1')

$shapeMap = Get-Content (Join-Path $repoRoot 'Data/PfbResponseShapeMap.json') -Raw | ConvertFrom-Json
$producerIndex = Get-PfbSelectorProducerIndex -ResponseShapeMap $shapeMap
$endpointLiteral = Get-PfbCmdletEndpointLiteral -PublicDirectory (Join-Path $repoRoot 'Public')
$exampleChain = Get-PfbHelpExampleChain -PublicDirectory (Join-Path $repoRoot 'Public')
$inventory = Get-PfbCmdletParameterInventory -PublicDirectory (Join-Path $repoRoot 'Public')
$bound = Get-PfbPipelineBoundParameter -Module $module

$producerSet = @{}
foreach ($cmdlet in ($bound.Cmdlet | Sort-Object -Unique)) {
    $producerSet[$cmdlet] = Get-PfbSelectorProducerSet -Cmdlet $cmdlet -EndpointLiteral $endpointLiteral `
        -ProducerIndex $producerIndex -ExampleChain $exampleChain
}

# EVERY triple is probed, not only the candidates. The non-candidate results are the control group
# that proves the predicate discriminates -- exactly what #89's list never had.
$candidates = Get-PfbSelectorCandidate -PipelineParameter $bound -Inventory $inventory `
    -ProducerSet $producerSet -ResponseShapeMap $shapeMap

$typeCache = @{}
$degraded = [System.Collections.Generic.List[string]]::new()
$results = [System.Collections.Generic.List[object]]::new()

foreach ($candidate in $candidates) {
    if (-not $typeCache.ContainsKey($candidate.Producer)) {
        $types = Get-PfbResponseItemType -SpecPath $newestSpec.File.FullName -Endpoint $candidate.Producer
        if (-not $types.Count) { $degraded.Add($candidate.Producer) }
        $typeCache[$candidate.Producer] = $types
    }

    $itemProperties = @($shapeMap.endpoints.($candidate.Producer).responseItemProperties.PSObject.Properties.Name)
    if (-not $itemProperties) { continue }

    $probe = New-PfbSelectorProbeObject -ItemProperty $itemProperties -ItemType $typeCache[$candidate.Producer]
    $result = Invoke-PfbSelectorProbe -Module $module -Cmdlet $candidate.Cmdlet -ProbeObject $probe
    $outcome = Get-PfbSelectorOutcome -ProbeResult $result -Parameter $candidate.Parameter `
        -WireName $candidate.WireName -ProbeObject $probe -Alias @($candidate.Aliases)

    # ProbeProperties/ProbeTypes are emitted so Rail A can rebuild this exact probe object without
    # reading tools/specs, which is gitignored. A rail that silently skips when a cache is missing
    # is the failure mode it exists to prevent.
    $probeTypes = [ordered]@{}
    foreach ($name in @(Sort-PfbSelectorString -Value $itemProperties -Unique)) {
        $probeTypes[$name] = $typeCache[$candidate.Producer][$name]
    }

    $results.Add([PSCustomObject]@{
            Cmdlet            = $candidate.Cmdlet
            Verb              = $candidate.Verb
            Parameter         = $candidate.Parameter
            Producer          = $candidate.Producer
            # Provenance, so a finding can be ranked by how real the chain is: the cmdlet's own
            # GET (a user would obviously pipe from it), a chain the module advertises in its own
            # help, or merely another endpoint in the same family.
            IsPrimary         = ($candidate.Producer -in @($producerSet[$candidate.Cmdlet].Primary))
            FromExample       = ($candidate.Producer -in @($producerSet[$candidate.Cmdlet].FromExample))
            WireName          = $candidate.WireName
            IsCandidate       = $candidate.IsCandidate
            Gate              = $candidate.Gate
            ValueFromPipeline = $candidate.ValueFromPipeline
            Outcome           = $outcome.Outcome
            Evidence          = $outcome.Evidence
            BoundWireKey      = $outcome.BoundWireKey
            BoundValue        = $outcome.BoundValue
            ErrorKind         = $result.ErrorKind
            # Non-empty means an ASSISTED verdict: a real invocation of the real cmdlet, reached
            # by synthesising mandatory parameters the probe object cannot carry. Fillers only
            # ever target parameters the piped object provably could not have bound.
            FilledParameter   = @(Sort-PfbSelectorString -Value @($result.FillerArgument.Keys) -Unique)
            ProbeProperties   = @(Sort-PfbSelectorString -Value $itemProperties -Unique)
            ProbeTypes        = [PSCustomObject]$probeTypes
        })
}

$evaluated = @($results | Where-Object { $_.Gate -in @('Candidate', 'Matched') })
$findings = @($results | Where-Object { $_.Outcome -in @('Coerced', 'WrongScalar') })
$controlLeak = @($findings | Where-Object { -not $_.IsCandidate })
$candidateCount = @($results | Where-Object IsCandidate).Count
$assisted = @($results | Where-Object { $_.FilledParameter.Count })
$findingPairs = @(Sort-PfbSelectorString -Value @($findings | ForEach-Object { "$($_.Cmdlet)/$($_.Parameter)" }) -Unique)

# Ordinal throughout. Sort-Object -Culture '' is invariant LINGUISTIC comparison and the two
# editions this repo gates on disagree on it (5.1 ignores the hyphen in 'file-system-snapshots',
# 7 does not), which showed up as 10 of 1179 rows changing position with every verdict identical.
$report = [PSCustomObject]@{
    schemaVersion     = '1.0'
    generatedFromSpec = $newestSpec.File.BaseName
    degradedProducers = @(Sort-PfbSelectorString -Value $degraded -Unique)
    totals            = [PSCustomObject]@{
        probePairs       = $results.Count
        evaluatedPairs   = $evaluated.Count
        candidatePairs   = $candidateCount
        candidateRate    = if ($evaluated.Count) { [math]::Round(@($evaluated | Where-Object IsCandidate).Count / $evaluated.Count, 4) } else { 0 }
        findings         = $findings.Count
        findingPairs     = $findingPairs.Count
        confirmationRate = if ($candidateCount) { [math]::Round($findings.Count / $candidateCount, 4) } else { 0 }
        controlLeakage   = $controlLeak.Count
        assistedRows     = $assisted.Count
    }
    outcomeBreakdown  = @(Sort-PfbSelectorRecord -Record @($results | Group-Object Outcome |
                ForEach-Object { [PSCustomObject]@{ Outcome = $_.Name; Count = $_.Count } }) -Property 'Outcome')
    gateBreakdown     = @(Sort-PfbSelectorRecord -Record @($results | Group-Object Gate |
                ForEach-Object { [PSCustomObject]@{ Gate = $_.Name; Count = $_.Count } }) -Property 'Gate')
    results           = @(Sort-PfbSelectorRecord -Record @($results) -Property 'Cmdlet', 'Parameter', 'Producer')
}

$report | ConvertTo-Json -Depth 8 | Set-Content -Path $OutputPath -Encoding UTF8

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('# Pipeline Selector Map')
$lines.Add('')
$lines.Add('Generated by `tools/Build-PfbPipelineSelectorMap.ps1`. Do not edit by hand.')
$lines.Add('')
$lines.Add('Answers: **can a piped object bind this cmdlet''s selector, or does it stringify into the filter?**')
$lines.Add('Every row is an observed probe against the real imported module with the HTTP layer shadowed --')
$lines.Add('no request leaves the machine, and nothing here is inferred from pattern-matching.')
$lines.Add('')
$lines.Add('## Control metrics')
$lines.Add('')
$lines.Add('| Metric | Value |')
$lines.Add('|---|---:|')
foreach ($property in $report.totals.PSObject.Properties) {
    $lines.Add("| ``$($property.Name)`` | $($property.Value) |")
}
$lines.Add('')
$lines.Add('`findings` counts probe ROWS; `findingPairs` counts distinct (cmdlet, parameter) pairs. One')
$lines.Add('defect appears once per producing endpoint, so rows always exceed pairs.')
$lines.Add('')
$lines.Add('## Outcomes')
$lines.Add('')
$lines.Add('| Outcome | Rows | Finding? |')
$lines.Add('|---|---:|---|')
$meaning = @{
    'Bound'       = 'no -- the selector bound as intended'
    'Coerced'     = '**yes** -- a stringified object reached the wire'
    'WrongScalar' = '**yes** -- a value from the wrong property reached the wire'
    'Unbindable'  = 'no -- PowerShell declined to bind this probe object at all. Note that pass 4 is ByPropertyName WITH coercion, so a ByPropertyName-only parameter whose alias matches an object-valued property CAN still coerce; this outcome is not a structural immunity'
    'NoSelector'  = 'no -- reported observation'
    'Guarded'     = 'no -- a #64/#90 coercion guard fired'
    'CmdletError' = 'no -- the cmdlet threw before any request was built'
    'BindError'   = 'triage -- the harness never invoked, the only unmeasured outcome'
}
foreach ($row in $report.outcomeBreakdown) {
    $lines.Add("| ``$($row.Outcome)`` | $($row.Count) | $($meaning[$row.Outcome]) |")
}
$lines.Add('')
$lines.Add('## Findings')
$lines.Add('')
$lines.Add('Ordered with primary-producer rows first: those are the chains a user would most obviously write.')
$lines.Add('')
$lines.Add('| Cmdlet | Parameter | Producer | Primary | Evidence |')
$lines.Add('|---|---|---|---|---|')
# Sort-Object with a single boolean key and no tiebreaker is UNSTABLE -- it reproduces only while
# the input sequence and the runtime's introsort both hold, so a .NET change could reshuffle all
# 389 rows with every verdict identical and red the drift rail as if the map had changed. Order
# ordinally first, then partition explicitly.
$orderedFindings = Sort-PfbSelectorRecord -Record @($findings) -Property 'Cmdlet', 'Parameter', 'Producer'
foreach ($row in (@($orderedFindings | Where-Object IsPrimary) +
        @($orderedFindings | Where-Object { -not $_.IsPrimary }))) {
    $evidence = ($row.Evidence -replace '\|', '\|')
    $lines.Add("| ``$($row.Cmdlet)`` | ``$($row.Parameter)`` | ``$($row.Producer)`` | $(if ($row.IsPrimary) { 'yes' } else { '' }) | ``$evidence`` |")
}
$lines.Add('')
Set-Content -Path $markdownPath -Value ($lines -join "`n") -Encoding UTF8

Write-Host "Probe pairs: $($results.Count)  Candidates: $candidateCount  Findings: $($findings.Count) rows / $($findingPairs.Count) pairs  Control leakage: $($controlLeak.Count)"
Write-Host "Wrote $OutputPath and $markdownPath"
