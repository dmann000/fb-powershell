#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Integration tests for tools/Build-PfbApiDriftReport.ps1 against small synthetic
    fixtures (capability map, field-cmdlet map, Public/Private trees, spec files) -- no
    dependency on the real cached specs in tools/specs/, plus one real-artifact check.
#>

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $script:builderScript = Join-Path $repoRoot 'tools/Build-PfbApiDriftReport.ps1'

    $script:fixtureRoot = Join-Path $TestDrive 'fixture'
    $publicDir = Join-Path $fixtureRoot 'Public/Fixture'
    $privateDir = Join-Path $fixtureRoot 'Private'
    $specsDir = Join-Path $fixtureRoot 'specs'
    New-Item -ItemType Directory -Path $publicDir, $privateDir, $specsDir -Force | Out-Null

    Set-Content -Path (Join-Path $publicDir 'Get-PfbFixtureArrayPerformance.ps1') -Value @'
function Get-PfbFixtureArrayPerformance {
    [CmdletBinding()]
    param(
        [Parameter()] [PSCustomObject]$Array,
        [Parameter()]
        [ValidateSet('nfs', 'smb', 'http', 's3')]
        [string]$Protocol
    )
    $queryParams = @{}
    if ($Protocol) { $queryParams['protocol'] = $Protocol }
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'arrays/performance' -QueryParams $queryParams -AutoPaginate
}
'@

    # Task 5 fixture: a fully-typed (high-confidence) write cmdlet whose endpoint has real
    # addable body-property gaps (color/count/tags) enriched with type/synopsis/enum/target.
    # -Label IS resolved (index-form `$body['label'] = $Label`), establishing 'index' as
    # this cmdlet's own dominant AssignmentStyle for Task 5's target coordinates.
    Set-Content -Path (Join-Path $publicDir 'Update-PfbFixtureWidget.ps1') -Value @'
function Update-PfbFixtureWidget {
    [CmdletBinding()]
    param(
        [Parameter()] [PSCustomObject]$Array,
        [Parameter(Mandatory)] [string]$Name,
        [Parameter()] [string]$Label
    )
    $queryParams = @{}
    $queryParams['names'] = $Name
    $body = @{}
    if ($Label) { $body['label'] = $Label }
    Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'widgets' -Body $body -QueryParams $queryParams
}
'@

    # Task 5 fixture: a PARTIAL-confidence write cmdlet (an unresolved -Tags parameter with
    # a real -Attributes escape hatch) whose endpoint ALSO has an addable body-property gap
    # ('label') -- this gap must stay a bare string, never enriched, per this task's
    # confidence-gating design (see Build-PfbApiDriftReport.ps1's own .NOTES).
    Set-Content -Path (Join-Path $publicDir 'Update-PfbFixtureGizmo.ps1') -Value @'
function Update-PfbFixtureGizmo {
    [CmdletBinding()]
    param(
        [Parameter()] [PSCustomObject]$Array,
        [Parameter()] [string[]]$Tags,
        [Parameter(Mandatory)] [hashtable]$Attributes
    )
    if ($Tags) { Write-Verbose ($Tags -join ',') }
    Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'gizmos' -Body $Attributes
}
'@

    # v1: Protocol has 4 values, matching the fixture cmdlet's ValidateSet exactly. Also
    # declares 'region' (matching the capability map's claim it's introduced at 9.0) so
    # Build-PfbApiDriftReport.ps1's phantom-field cross-check (against the SINGLE newest
    # analysed spec -- see Get-PfbParameterCoverageGaps's -CurrentSpecCapabilities) doesn't
    # treat it as withdrawn-from-the-API just because this fixture spec's JSON and the
    # hand-written capability map fixture would otherwise disagree.
    $specV1 = [ordered]@{
        openapi = '3.0.1'; info = @{ version = '9.0' }
        paths = [ordered]@{
            '/arrays/performance' = [ordered]@{
                get = [ordered]@{
                    parameters = @(
                        [ordered]@{ name = 'protocol'; 'in' = 'query'; schema = [ordered]@{ type = 'string' }; description = 'Valid values are `nfs`, `smb`, `http`, and `s3`.' }
                        [ordered]@{ name = 'region'; 'in' = 'query'; schema = [ordered]@{ type = 'string' } }
                    )
                }
            }
        }
        components = [ordered]@{ schemas = [ordered]@{} }
    }
    # v2: spec adds 'all' -- the real Get-PfbArrayPerformance -Protocol bug shape. Also
    # carries 'region' and 'timezone' forward (see specV1's note above) -- this is the
    # NEWEST analysed spec (capability map's generatedFrom ends at 9.1), so it's the one
    # Build-PfbApiDriftReport.ps1 actually re-parses for phantom-field exclusion AND (Task
    # 5) for enrichment's synopsis/type/array-item lookups and the enum join's schema-kind
    # history.
    $specV2 = [ordered]@{
        openapi = '3.0.1'; info = @{ version = '9.1' }
        paths = [ordered]@{
            '/arrays/performance' = [ordered]@{
                get = [ordered]@{
                    parameters = @(
                        [ordered]@{ name = 'protocol'; 'in' = 'query'; schema = [ordered]@{ type = 'string' }; description = 'Valid values are `all`, `nfs`, `smb`, `http`, and `s3`.' }
                        [ordered]@{ name = 'region'; 'in' = 'query'; schema = [ordered]@{ type = 'string' } }
                        [ordered]@{ name = 'timezone'; 'in' = 'query'; schema = [ordered]@{ type = 'string' } }
                    )
                }
            }
            '/gadgets' = [ordered]@{ get = [ordered]@{ parameters = @() } }
            '/widgets' = [ordered]@{
                patch = [ordered]@{
                    requestBody = [ordered]@{
                        content = [ordered]@{
                            'application/json' = [ordered]@{ schema = [ordered]@{ '$ref' = '#/components/schemas/WidgetPatch' } }
                        }
                    }
                }
            }
            '/gizmos' = [ordered]@{
                patch = [ordered]@{
                    # Deliberately fully INLINE (no $ref anywhere in the chain) -- exercises
                    # OwnerSchema = $null (Task 5's Get-PfbBodyPropertySynopsis/array-item
                    # lookups both return $null for this field, by design).
                    requestBody = [ordered]@{
                        content = [ordered]@{
                            'application/json' = [ordered]@{
                                schema = [ordered]@{
                                    type       = 'object'
                                    properties = [ordered]@{ label = [ordered]@{ type = 'string'; description = 'The gizmo label.' } }
                                }
                            }
                        }
                    }
                }
            }
        }
        components = [ordered]@{
            schemas = [ordered]@{
                WidgetPatch = [ordered]@{
                    type       = 'object'
                    properties = [ordered]@{
                        color = [ordered]@{ type = 'string'; description = 'The fixture widget color. Valid values are `red`, `blue`, and `green`.' }
                        count = [ordered]@{ type = 'integer'; format = 'int64'; description = 'Number of fixture widgets.' }
                        tags  = [ordered]@{ type = 'array'; items = [ordered]@{ type = 'string' }; description = 'Fixture widget tags.' }
                    }
                }
            }
        }
    }
    $specV1 | ConvertTo-Json -Depth 20 | Set-Content -Path (Join-Path $specsDir 'fb9.0.json')
    $specV2 | ConvertTo-Json -Depth 20 | Set-Content -Path (Join-Path $specsDir 'fb9.1.json')

    $script:capabilityMapPath = Join-Path $fixtureRoot 'PfbCapabilityMap.json'
    [ordered]@{
        schemaVersion = 1
        generatedFrom = @('9.0', '9.1')
        endpoints     = [ordered]@{
            'GET /arrays/performance' = [ordered]@{ minVersion = '9.0'; parameters = [ordered]@{ protocol = '9.0'; region = '9.0'; timezone = '9.1'; 'X-Request-ID' = '9.0'; continuation_token = '9.0'; offset = '9.0' }; bodyProperties = [ordered]@{} }
            'GET /gadgets'            = [ordered]@{ minVersion = '9.1'; parameters = [ordered]@{}; bodyProperties = [ordered]@{} }
            'GET /widgets'            = [ordered]@{ minVersion = '9.0'; parameters = [ordered]@{}; bodyProperties = [ordered]@{} }
            'PATCH /widgets'          = [ordered]@{ minVersion = '9.0'; parameters = [ordered]@{}; bodyProperties = [ordered]@{ color = '9.0'; count = '9.0'; tags = '9.0' } }
            'PATCH /gizmos'           = [ordered]@{ minVersion = '9.1'; parameters = [ordered]@{}; bodyProperties = [ordered]@{ label = '9.1' } }
        }
    } | ConvertTo-Json -Depth 20 | Set-Content -Path $capabilityMapPath

    $script:fieldCmdletMapPath = Join-Path $fixtureRoot 'PfbFieldCmdletMap.json'
    [ordered]@{
        schemaVersion   = 1
        generatedFrom   = @('9.0', '9.1')
        entries         = @(
            [ordered]@{ cmdlet = 'New-PfbFixtureWidget'; parameter = 'Color'; wireName = 'color'; status = 'matched'; matchedKey = 'Widget.color'; specValues = @('red', 'blue'); stableSinceOldestVersion = $true; recommendation = 'ValidateSet' }
        )
        attributesOnly  = @()
        typedUnresolved = @()
    } | ConvertTo-Json -Depth 20 | Set-Content -Path $fieldCmdletMapPath

    $script:outputPath = Join-Path $TestDrive 'output/PfbApiDriftReport.json'
    $script:reportPath = Join-Path $TestDrive 'output/PfbApiDriftReport.md'

    & $builderScript -SpecsDirectory $specsDir -PublicDirectory $publicDir -PrivateDirectory $privateDir `
        -CapabilityMapPath $capabilityMapPath -FieldCmdletMapPath $fieldCmdletMapPath `
        -OutputPath $outputPath -ReportPath $reportPath

    $script:manifest = Get-Content -Path $outputPath -Raw | ConvertFrom-Json -Depth 20
}

Describe 'Build-PfbApiDriftReport' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
    It 'category 1: flags GET /gadgets as an uncovered endpoint' {
        ($manifest.uncoveredEndpoints | Where-Object { $_.endpoint -eq 'GET /gadgets' }) | Should -Not -BeNullOrEmpty
    }

    It 'category 3: flags the Protocol ValidateSet missing the spec''s newly-added "all" value' {
        $rec = $manifest.validateSetDrift | Where-Object { $_.cmdlet -eq 'Get-PfbFixtureArrayPerformance' -and $_.parameter -eq 'Protocol' }
        $rec.missingValues | Should -Contain 'all'
    }

    It 'category 4: passes Build-PfbFieldCmdletMap.ps1''s matched entries through unchanged' {
        $rec = $manifest.newValidateSetCandidates | Where-Object { $_.cmdlet -eq 'New-PfbFixtureWidget' }
        $rec.parameter | Should -Be 'Color'
    }

    It 'writes both a JSON manifest and a Markdown report' {
        Test-Path $outputPath | Should -BeTrue
        Test-Path $reportPath | Should -BeTrue
    }

    It 'the JSON manifest contains no non-deterministic content (no timestamp fields)' {
        $manifest.PSObject.Properties.Name | Should -Not -Contain 'generatedAt'
        $manifest.PSObject.Properties.Name | Should -Not -Contain 'timestamp'
    }

    It 'without -SinceVersion, sinceVersion is not set and older gaps are present' {
        $manifest.sinceVersion | Should -BeNullOrEmpty
        ($manifest.uncoveredEndpoints | Where-Object { $_.endpoint -eq 'GET /widgets' }) | Should -Not -BeNullOrEmpty
    }

    It 'never reports X-Request-ID as a missing query parameter, even though the fixture endpoint has it' {
        $gap = $manifest.parameterGaps | Where-Object { $_.endpoint -eq 'GET /arrays/performance' }
        $gap.missingQueryParameters | Should -Not -Contain 'X-Request-ID'
        $gap.missingQueryParameters | Should -Contain 'region'
    }

    It 'never reports continuation_token or offset as a missing query parameter, even though the fixture endpoint has both' {
        $gap = $manifest.parameterGaps | Where-Object { $_.endpoint -eq 'GET /arrays/performance' }
        $gap.missingQueryParameters | Should -Not -Contain 'continuation_token'
        $gap.missingQueryParameters | Should -Not -Contain 'offset'
        $gap.missingQueryParameters | Should -Contain 'region'
    }

    Context 'Task 5: enrichment + enum join on a high-confidence endpoint (PATCH /widgets)' {
        BeforeAll {
            $script:widgetGap = $manifest.parameterGaps | Where-Object { $_.endpoint -eq 'PATCH /widgets' }
            $script:colorRecord = $widgetGap.missingBodyProperties | Where-Object { $_.name -eq 'color' }
            $script:countRecord = $widgetGap.missingBodyProperties | Where-Object { $_.name -eq 'count' }
            $script:tagsRecord = $widgetGap.missingBodyProperties | Where-Object { $_.name -eq 'tags' }
        }

        It 'is high-confidence (fully typed cmdlet, no unresolved surface)' {
            $widgetGap.confidence.level | Should -Be 'high'
        }

        It 'turns each addable body-property gap into a RECORD, not a bare string' {
            $colorRecord | Should -Not -BeNullOrEmpty
            $colorRecord.name | Should -Be 'color'
            $colorRecord.type | Should -Be 'string'
        }

        It 'resolves enumStatus matched and enumValues via the real Resolve-PfbFieldValueEnum join (not a bare-name lookup)' {
            $colorRecord.enumStatus | Should -Be 'matched'
            $colorRecord.enumValues | Should -Be @('red', 'blue', 'green')
        }

        It 'extracts synopsis as the first sentence only, newline-normalised' {
            $colorRecord.synopsis | Should -Be 'The fixture widget color.'
        }

        It 'maps type:integer,format:int64 to suggestedPowerShellType [long], never the truncating [int]' {
            $countRecord.format | Should -Be 'int64'
            $countRecord.suggestedPowerShellType | Should -Be '[long]'
        }

        It 'maps type:array with inline items.type:string to suggestedPowerShellType [string[]]' {
            $tagsRecord.type | Should -Be 'array'
            $tagsRecord.suggestedPowerShellType | Should -Be '[string[]]'
        }

        It 'never maps specRequired to [Parameter(Mandatory)] -- specRequired is present as plain metadata only' {
            $colorRecord.PSObject.Properties.Name | Should -Contain 'specRequired'
            $colorRecord.specRequired | Should -Be $false
        }

        It 'carries target insertion-point coordinates matching this cmdlet''s own dominant (index) assignment style' {
            $colorRecord.target.file | Should -Match 'Update-PfbFixtureWidget\.ps1$'
            $colorRecord.target.payloadVariable | Should -Be 'body'
            $colorRecord.target.assignmentStyle | Should -Be 'index'
            $colorRecord.target.hasAttributes | Should -BeFalse
            $colorRecord.target.paramBlockLine | Should -BeGreaterThan 0
        }
    }

    It 'REGRESSION: a high-confidence endpoint with an EMPTY MissingBodyProperties serializes as [] in JSON, never a phantom one-element array with a blank name' {
        # Real-data-only bug, invisible to any in-memory-only check: a query-only
        # high-confidence gap (GET /arrays/performance has body-property gaps at all here)
        # -- `$missingBodyProperties = if (...) {...} else {...}` (missing an outer @()
        # around the WHOLE if/else, only wrapping each branch's own content) let an empty
        # result collapse to a value that read as 0 elements in-memory but round-tripped
        # through ConvertTo-Json/ConvertFrom-Json into a 1-element array containing a
        # single $null -- inflating the high-confidence addable-gap total from 402 to 682
        # on the real capability map. $manifest here is loaded from the actual JSON FILE
        # this script wrote (see BeforeAll), not the in-memory array, so this test would
        # NOT have caught the bug if it only inspected pre-serialization objects.
        $perfGap = $manifest.parameterGaps | Where-Object { $_.endpoint -eq 'GET /arrays/performance' }
        $perfGap.confidence.level | Should -Be 'high'
        @($perfGap.missingBodyProperties).Count | Should -Be 0
    }

    Context 'Task 5: the query-vs-body vs. confidence-level enrichment asymmetry' {
        BeforeAll {
            $script:gizmoGap = $manifest.parameterGaps | Where-Object { $_.endpoint -eq 'PATCH /gizmos' }
        }

        It 'PATCH /gizmos is partial-confidence (an unresolved -Tags parameter with an -Attributes escape hatch)' {
            $gizmoGap.confidence.level | Should -Be 'partial'
        }

        It 'leaves a partial-confidence endpoint''s missingBodyProperties as BARE STRINGS, never enriched records' {
            $gizmoGap.missingBodyProperties | Should -Contain 'label'
            ($gizmoGap.missingBodyProperties | Where-Object { $_ -is [string] }) | Should -Be @('label')
        }

        It 'leaves missingQueryParameters as bare strings on a high-confidence endpoint too (query gaps are never enriched, regardless of confidence)' {
            $arraysPerfGap = $manifest.parameterGaps | Where-Object { $_.endpoint -eq 'GET /arrays/performance' }
            ($arraysPerfGap.missingQueryParameters | ForEach-Object { $_ -is [string] }) | Should -Not -Contain $false
        }
    }
}

Describe 'Build-PfbApiDriftReport -SinceVersion filter' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
    BeforeAll {
        $script:filteredOutputPath = Join-Path $TestDrive 'output/PfbApiDriftReportSince.json'
        $script:filteredReportPath = Join-Path $TestDrive 'output/PfbApiDriftReportSince.md'
        & $builderScript -SpecsDirectory $specsDir -PublicDirectory $publicDir -PrivateDirectory $privateDir `
            -CapabilityMapPath $capabilityMapPath -FieldCmdletMapPath $fieldCmdletMapPath `
            -OutputPath $filteredOutputPath -ReportPath $filteredReportPath -SinceVersion '9.0'
        $script:filteredManifest = Get-Content -Path $filteredOutputPath -Raw | ConvertFrom-Json -Depth 20
        $script:filteredReportText = Get-Content -Path $filteredReportPath -Raw
    }

    It 'records the requested SinceVersion in the manifest' {
        $filteredManifest.sinceVersion | Should -Be '9.0'
    }

    It 'excludes an uncovered endpoint introduced at or before -SinceVersion' {
        ($filteredManifest.uncoveredEndpoints | Where-Object { $_.endpoint -eq 'GET /widgets' }) | Should -BeNullOrEmpty
    }

    It 'keeps an uncovered endpoint introduced after -SinceVersion' {
        ($filteredManifest.uncoveredEndpoints | Where-Object { $_.endpoint -eq 'GET /gadgets' }) | Should -Not -BeNullOrEmpty
    }

    It 'filters a parameter gap down to only fields introduced after -SinceVersion' {
        $gap = $filteredManifest.parameterGaps | Where-Object { $_.endpoint -eq 'GET /arrays/performance' }
        $gap.missingQueryParameters | Should -Be @('timezone')
    }

    It 'notes the SinceVersion filter in the Markdown report' {
        $filteredReportText | Should -Match 'introduced after REST 9\.0'
    }
}

Describe 'Build-PfbApiDriftReport determinism (Task 8: end-to-end round-trip, same inputs, two separate output paths, byte-identical)' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
    # Existing coverage elsewhere in this file only asserts "no timestamp fields" (see the
    # non-deterministic-content test above) and, inside tools/lib/PfbApiDriftTools.ps1 itself,
    # alphabetical-ordering guarantees on individual collections (Sort-Object on
    # MissingQueryParameters/MissingBodyProperties/ReadOnlyFields -- see that file's own
    # load-bearing comment on why: Dictionary/PSCustomObject property enumeration order is not
    # guaranteed stable run-to-run, and two Hashtable-staged candidate sets were once observed to
    # reorder purely from .NET's per-process-randomized string hash codes). Neither is an
    # end-to-end test: nothing here has ever run the FULL builder script twice against IDENTICAL
    # inputs and diffed the two written files byte-for-byte. That gap matters more now than it did
    # before this task: Tasks 4-7 added three entirely new collections (systemicGaps,
    # conventionStrength, plus per-row confidence/annotations) since the last such check would have
    # been meaningful, and the weekly CI workflow (update-api-capability-map.yml) opens a PR on ANY
    # diff in the committed Reports/ output -- a single non-deterministic field anywhere in the
    # manifest would make that job spuriously fire on every run, forever, even with zero real API
    # drift.
    BeforeAll {
        $script:detOutputA = Join-Path $TestDrive 'determinism/runA/report.json'
        $script:detReportA = Join-Path $TestDrive 'determinism/runA/report.md'
        $script:detOutputB = Join-Path $TestDrive 'determinism/runB/report.json'
        $script:detReportB = Join-Path $TestDrive 'determinism/runB/report.md'
        & $builderScript -SpecsDirectory $specsDir -PublicDirectory $publicDir -PrivateDirectory $privateDir `
            -CapabilityMapPath $capabilityMapPath -FieldCmdletMapPath $fieldCmdletMapPath `
            -OutputPath $detOutputA -ReportPath $detReportA
        & $builderScript -SpecsDirectory $specsDir -PublicDirectory $publicDir -PrivateDirectory $privateDir `
            -CapabilityMapPath $capabilityMapPath -FieldCmdletMapPath $fieldCmdletMapPath `
            -OutputPath $detOutputB -ReportPath $detReportB
    }

    It 'produces a byte-identical JSON manifest across two independent runs against the same inputs' {
        $hashA = (Get-FileHash -Path $detOutputA -Algorithm SHA256).Hash
        $hashB = (Get-FileHash -Path $detOutputB -Algorithm SHA256).Hash
        $hashA | Should -Be $hashB
    }

    It 'produces a byte-identical Markdown report across two independent runs against the same inputs' {
        $hashA = (Get-FileHash -Path $detReportA -Algorithm SHA256).Hash
        $hashB = (Get-FileHash -Path $detReportB -Algorithm SHA256).Hash
        $hashA | Should -Be $hashB
    }
}

Describe 'Build-PfbApiDriftReport (real generated artifacts, skips gracefully if absent)' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
    BeforeAll {
        $script:realCapabilityMapPath = Join-Path $repoRoot 'Data/PfbCapabilityMap.json'
        $script:realFieldCmdletMapPath = Join-Path $repoRoot 'Reports/PfbFieldCmdletMap.json'
        $script:realSpecsDir = Join-Path $repoRoot 'tools/specs'
        $script:hasRealArtifacts = (Test-Path $realCapabilityMapPath) -and (Test-Path $realFieldCmdletMapPath) -and
            (Test-Path $realSpecsDir) -and (Get-ChildItem $realSpecsDir -Filter 'fb*.json' -ErrorAction SilentlyContinue)

        if ($hasRealArtifacts) {
            $script:realOutput = Join-Path $TestDrive 'realOutput/report.json'
            $script:realReport = Join-Path $TestDrive 'realOutput/report.md'
            & $builderScript -SpecsDirectory $realSpecsDir -PublicDirectory (Join-Path $repoRoot 'Public') -PrivateDirectory (Join-Path $repoRoot 'Private') `
                -CapabilityMapPath $realCapabilityMapPath -FieldCmdletMapPath $realFieldCmdletMapPath `
                -OutputPath $realOutput -ReportPath $realReport
            $script:realManifest = Get-Content -Path $realOutput -Raw | ConvertFrom-Json -Depth 20
            $script:realCapMapForCheck = Get-Content -Path $realCapabilityMapPath -Raw | ConvertFrom-Json -Depth 20
        }
    }

    It 'produces a manifest against the real Public/Private tree and Reports/ + Data/ inputs' {
        if (-not $hasRealArtifacts) { Set-ItResult -Skipped -Because 'Data/PfbCapabilityMap.json, Reports/PfbFieldCmdletMap.json, or tools/specs/ not present locally'; return }
        Test-Path $realOutput | Should -BeTrue
    }

    It 'Task 7: wires systemicGaps through with the pinned acceptance figures (context_names 253, allow_errors 109)' {
        if (-not $hasRealArtifacts) { Set-ItResult -Skipped -Because 'real artifacts not present locally'; return }
        ($realManifest.systemicGaps | Where-Object { $_.name -eq 'context_names' }).endpointCount | Should -Be 253
        ($realManifest.systemicGaps | Where-Object { $_.name -eq 'allow_errors' }).endpointCount | Should -Be 109
    }

    It 'Task 7: wires conventionStrength through with the pinned acceptance figures (names 306, ids 218, context_names 0)' {
        if (-not $hasRealArtifacts) { Set-ItResult -Skipped -Because 'real artifacts not present locally'; return }
        ($realManifest.conventionStrength | Where-Object { $_.name -eq 'names' }).cmdletCount | Should -Be 306
        ($realManifest.conventionStrength | Where-Object { $_.name -eq 'ids' }).cmdletCount | Should -Be 218
        ($realManifest.conventionStrength | Where-Object { $_.name -eq 'context_names' }).cmdletCount | Should -Be 0
    }

    It 'Task 7: attaches docs/drift-annotations.json''s designDecision note to the context_names systemic-gap finding' {
        if (-not $hasRealArtifacts) { Set-ItResult -Skipped -Because 'real artifacts not present locally'; return }
        $ctx = $realManifest.systemicGaps | Where-Object { $_.name -eq 'context_names' }
        $ctx.annotations | Should -Not -BeNullOrEmpty
        ($ctx.annotations | Select-Object -First 1).note | Should -Match 'not yet implemented'
    }

    It 'Task 7: attaches docs/drift-annotations.json''s liveTestingHazard note to a management-access-policies parameter-gap row' {
        if (-not $hasRealArtifacts) { Set-ItResult -Skipped -Because 'real artifacts not present locally'; return }
        $row = $realManifest.parameterGaps | Where-Object { $_.endpoint -match 'management-access-policies' } | Select-Object -First 1
        if (-not $row) { Set-ItResult -Skipped -Because 'no management-access-policies endpoint currently has a parameter gap'; return }
        $row.annotations | Should -Not -BeNullOrEmpty
        ($row.annotations | Select-Object -First 1).note | Should -Match '403'
    }

    It 'Task 7: splits generatedFrom into analysedVersions (from the capability map) and availableSpecVersions (from tools/specs/ on disk), warning exactly when they disagree' {
        if (-not $hasRealArtifacts) { Set-ItResult -Skipped -Because 'real artifacts not present locally'; return }
        $realManifest.analysedVersions | Should -Be @($realCapMapForCheck.generatedFrom)
        $onDiskVersions = @(Get-ChildItem $realSpecsDir -Filter 'fb*.json' | ForEach-Object { $_.BaseName -replace '^fb', '' })
        @(Compare-Object -ReferenceObject $realManifest.availableSpecVersions -DifferenceObject $onDiskVersions).Count | Should -Be 0
        $diverges = @(Compare-Object -ReferenceObject $realManifest.analysedVersions -DifferenceObject $realManifest.availableSpecVersions).Count -gt 0
        if ($diverges) { $realManifest.versionDivergenceWarning | Should -Not -BeNullOrEmpty }
        else { $realManifest.versionDivergenceWarning | Should -BeNullOrEmpty }
    }

    It 'Task 7: phantomFieldCount is a non-negative integer, present on the manifest' {
        if (-not $hasRealArtifacts) { Set-ItResult -Skipped -Because 'real artifacts not present locally'; return }
        $realManifest.phantomFieldCount | Should -BeGreaterOrEqual 0
    }
}

Describe 'Build-PfbApiDriftReport (Task 8: regression canaries + spot-checks against the real generated report, skips gracefully if absent)' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
    BeforeAll {
        $script:t8CapabilityMapPath = Join-Path $repoRoot 'Data/PfbCapabilityMap.json'
        $script:t8FieldCmdletMapPath = Join-Path $repoRoot 'Reports/PfbFieldCmdletMap.json'
        $script:t8SpecsDir = Join-Path $repoRoot 'tools/specs'
        $script:t8HasRealArtifacts = (Test-Path $t8CapabilityMapPath) -and (Test-Path $t8FieldCmdletMapPath) -and
            (Test-Path $t8SpecsDir) -and (Get-ChildItem $t8SpecsDir -Filter 'fb*.json' -ErrorAction SilentlyContinue)

        if ($t8HasRealArtifacts) {
            $script:t8Output = Join-Path $TestDrive 't8output/report.json'
            $script:t8Report = Join-Path $TestDrive 't8output/report.md'
            & $builderScript -SpecsDirectory $t8SpecsDir -PublicDirectory (Join-Path $repoRoot 'Public') -PrivateDirectory (Join-Path $repoRoot 'Private') `
                -CapabilityMapPath $t8CapabilityMapPath -FieldCmdletMapPath $t8FieldCmdletMapPath `
                -OutputPath $t8Output -ReportPath $t8Report
            $script:t8Manifest = Get-Content -Path $t8Output -Raw | ConvertFrom-Json -Depth 20
        }

        function Get-T8GapFieldNames {
            param($Gap)
            @($Gap.missingBodyProperties | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.name } })
        }
    }

    # PLAN DEFECT #1 correction (see .superpowers/sdd/drift-report-actionable-plan/progress.md):
    # the task-8 brief originally listed 13 canaries, but PATCH /certificates|{id,name} are
    # confirmed phantoms (readOnly 2.0-2.19, removed entirely 2.20+, never actually settable) --
    # they must NOT be asserted as actionable. Only 11 of the brief's 13 listed (endpoint, field)
    # pairs are real, confirmed regressions against first-sight readOnly semantics.
    It 'Task 8 canaries: 11 confirmed (endpoint, field) pairs remain actionable body gaps, since first-sight readOnly semantics would have wrongly suppressed all 11' {
        if (-not $t8HasRealArtifacts) { Set-ItResult -Skipped -Because 'real artifacts not present locally'; return }
        $canaries = @(
            @{ Endpoint = 'PATCH /api-clients'; Field = 'max_role' }
            @{ Endpoint = 'PATCH /tls-policies'; Field = 'name' }
            @{ Endpoint = 'PATCH /storage-class-tiering-policies'; Field = 'name' }
            @{ Endpoint = 'PATCH /dns'; Field = 'name' }
            @{ Endpoint = 'PATCH /ssh-certificate-authority-policies'; Field = 'name' }
            @{ Endpoint = 'PATCH /ssh-certificate-authority-policies'; Field = 'location' }
            @{ Endpoint = 'PATCH /targets'; Field = 'ca_certificate_group' }
            @{ Endpoint = 'PATCH /array-connections'; Field = 'ca_certificate_group' }
            @{ Endpoint = 'POST /array-connections'; Field = 'ca_certificate_group' }
            @{ Endpoint = 'PATCH /hardware-connectors'; Field = 'port_speed' }
            @{ Endpoint = 'PATCH /network-interfaces/connectors'; Field = 'port_speed' }
        )
        foreach ($c in $canaries) {
            $gap = $t8Manifest.parameterGaps | Where-Object { $_.endpoint -eq $c.Endpoint }
            $gap | Should -Not -BeNullOrEmpty -Because "$($c.Endpoint) must have a parameter-gap row"
            (Get-T8GapFieldNames -Gap $gap) | Should -Contain $c.Field -Because "$($c.Endpoint)|$($c.Field) is a regression canary"
        }
    }

    It 'Task 8 canary correction: PATCH /certificates|{id,name} are phantoms -- NOT actionable body gaps, NOT read-only fields, absent from the endpoint''s row entirely' {
        if (-not $t8HasRealArtifacts) { Set-ItResult -Skipped -Because 'real artifacts not present locally'; return }
        $gap = $t8Manifest.parameterGaps | Where-Object { $_.endpoint -eq 'PATCH /certificates' }
        $gap | Should -Not -BeNullOrEmpty
        (Get-T8GapFieldNames -Gap $gap) | Should -Not -Contain 'id'
        (Get-T8GapFieldNames -Gap $gap) | Should -Not -Contain 'name'
        $gap.readOnlyFields | Should -Not -Contain 'id'
        $gap.readOnlyFields | Should -Not -Contain 'name'
    }

    It 'Task 8 spot-check: all five policy-family PATCH endpoints list is_local and policy_type as read-only' {
        if (-not $t8HasRealArtifacts) { Set-ItResult -Skipped -Because 'real artifacts not present locally'; return }
        foreach ($ep in @('PATCH /worm-data-policies', 'PATCH /qos-policies', 'PATCH /ssh-certificate-authority-policies', 'PATCH /storage-class-tiering-policies', 'PATCH /tls-policies')) {
            $gap = $t8Manifest.parameterGaps | Where-Object { $_.endpoint -eq $ep }
            $gap | Should -Not -BeNullOrEmpty -Because "$ep must have a parameter-gap row"
            $gap.readOnlyFields | Should -Contain 'is_local' -Because "$ep|is_local"
            $gap.readOnlyFields | Should -Contain 'policy_type' -Because "$ep|policy_type"
        }
    }

    It 'Task 8 spot-check: PATCH /certificates / generate_new_key appears as a query-parameter gap' {
        if (-not $t8HasRealArtifacts) { Set-ItResult -Skipped -Because 'real artifacts not present locally'; return }
        $gap = $t8Manifest.parameterGaps | Where-Object { $_.endpoint -eq 'PATCH /certificates' }
        $gap.missingQueryParameters | Should -Contain 'generate_new_key'
    }

    It 'Task 8 spot-check: PATCH /directory-services/roles / management_access_policies is read-only' {
        if (-not $t8HasRealArtifacts) { Set-ItResult -Skipped -Because 'real artifacts not present locally'; return }
        $gap = $t8Manifest.parameterGaps | Where-Object { $_.endpoint -eq 'PATCH /directory-services/roles' }
        $gap.readOnlyFields | Should -Contain 'management_access_policies'
    }

    It 'Task 8 spot-check: PATCH /management-access-policies read-only set is exactly context, id, is_local, policy_type, realms, version' {
        if (-not $t8HasRealArtifacts) { Set-ItResult -Skipped -Because 'real artifacts not present locally'; return }
        $gap = $t8Manifest.parameterGaps | Where-Object { $_.endpoint -eq 'PATCH /management-access-policies' }
        (@($gap.readOnlyFields) | Sort-Object) | Should -Be @('context', 'id', 'is_local', 'policy_type', 'realms', 'version')
    }

    It 'Task 8 correction: Update-PfbFileSystemExport''s genuinely read-only set is context, enabled, id, name, policy_type, status -- member/server are settable' {
        if (-not $t8HasRealArtifacts) { Set-ItResult -Skipped -Because 'real artifacts not present locally'; return }
        $gap = $t8Manifest.parameterGaps | Where-Object { $_.endpoint -eq 'PATCH /file-system-exports' }
        (@($gap.readOnlyFields) | Sort-Object) | Should -Be @('context', 'enabled', 'id', 'name', 'policy_type', 'status')
        $gap.readOnlyFields | Should -Not -Contain 'member'
        $gap.readOnlyFields | Should -Not -Contain 'server'
    }

    It 'Task 8 correction: Update-PfbCertificate''s read-only set includes realms, beyond the five originally named' {
        if (-not $t8HasRealArtifacts) { Set-ItResult -Skipped -Because 'real artifacts not present locally'; return }
        $gap = $t8Manifest.parameterGaps | Where-Object { $_.endpoint -eq 'PATCH /certificates' }
        $gap.readOnlyFields | Should -Contain 'realms'
    }

    Context '"Nothing vanishes" invariant: every capability-map candidate field lands in exactly one of reported/phantom-excluded' {
        # Every query parameter and body property Data/PfbCapabilityMap.json lists for an
        # endpoint an existing cmdlet calls, that isn't already exposed as a Typed parameter and
        # isn't one of the non-actionable placeholder fields (X-Request-ID/continuation_token/
        # offset -- see Get-PfbNonActionableParameters, a documented, deliberate exclusion
        # unrelated to phantom detection), must land in EXACTLY ONE of: the real report's
        # missingQueryParameters/missingBodyProperties (addable)/readOnlyFields, or the
        # phantom-exclusion set (absent from the newest analysed spec). Verified arithmetically
        # over (endpoint, list, field) triples -- never bare field names, since a field name can
        # repeat across more than one endpoint's row -- using the SAME phantom-diffing technique
        # tools/Build-PfbApiDriftReport.ps1 itself already uses (a second
        # Get-PfbParameterCoverageGaps call without -CurrentSpecCapabilities), never a
        # re-derivation of the phantom-detection logic.
        BeforeAll {
            if ($t8HasRealArtifacts) {
                . (Join-Path $repoRoot 'tools/lib/PfbSpecTools.ps1')
                . (Join-Path $repoRoot 'tools/lib/PfbValueEnumTools.ps1')
                . (Join-Path $repoRoot 'tools/lib/PfbCmdletParamTools.ps1')
                . (Join-Path $repoRoot 'tools/lib/PfbApiDriftTools.ps1')
                $script:t8Inventory = Get-PfbCmdletParameterInventory -PublicDirectory (Join-Path $repoRoot 'Public')
                $script:t8CalledEndpoints = Get-PfbModuleCalledEndpoints -PublicDirectory (Join-Path $repoRoot 'Public') -PrivateDirectory (Join-Path $repoRoot 'Private')
                $script:t8CapMap = Get-Content -Path $t8CapabilityMapPath -Raw | ConvertFrom-Json -Depth 20
                $script:t8NonActionable = Get-PfbNonActionableParameters -PrivateDirectory (Join-Path $repoRoot 'Private')

                $newestAnalysedVersion8 = $t8CapMap.generatedFrom | Select-Object -Last 1
                $newestSpecPath8 = Join-Path $t8SpecsDir "fb$newestAnalysedVersion8.json"
                $newestSpec8 = Get-Content -Path $newestSpecPath8 -Raw | ConvertFrom-Json -Depth 64
                $script:t8CurrentSpecCapabilities = @(Get-PfbSpecCapabilities -Spec $newestSpec8)

                function Get-T8TripleSet {
                    param([object[]]$Gaps)
                    $set = [System.Collections.Generic.HashSet[string]]::new()
                    foreach ($g in $Gaps) {
                        foreach ($f in @($g.MissingQueryParameters)) { [void]$set.Add("$($g.Endpoint)|query|$f") }
                        foreach ($f in @($g.MissingBodyProperties)) { [void]$set.Add("$($g.Endpoint)|body|$f") }
                        foreach ($f in @($g.ReadOnlyFields)) { [void]$set.Add("$($g.Endpoint)|readOnly|$f") }
                    }
                    return $set
                }

                # Population: every real candidate field (Typed-exposed and non-actionable
                # placeholder fields already excluded), BEFORE phantom filtering.
                $script:t8PopulationRaw = @(Get-PfbParameterCoverageGaps -CapabilityMap $t8CapMap -CmdletInventory $t8Inventory -CalledEndpoints $t8CalledEndpoints -ExcludedFields $t8NonActionable -CurrentSpecCapabilities @())
                $script:t8PopulationSet = Get-T8TripleSet -Gaps $t8PopulationRaw

                # Reported: the exact same call Build-PfbApiDriftReport.ps1 itself makes.
                $script:t8ReportedRaw = @(Get-PfbParameterCoverageGaps -CapabilityMap $t8CapMap -CmdletInventory $t8Inventory -CalledEndpoints $t8CalledEndpoints -ExcludedFields $t8NonActionable -CurrentSpecCapabilities $t8CurrentSpecCapabilities)
                $script:t8ReportedSet = Get-T8TripleSet -Gaps $t8ReportedRaw

                $script:t8PhantomExcludedSet = [System.Collections.Generic.HashSet[string]]::new([string[]]@($t8PopulationSet))
                $t8PhantomExcludedSet.ExceptWith([string[]]@($t8ReportedSet))
            }
        }

        It 'reported UNION phantom-excluded exactly equals the full candidate population -- nothing missing, nothing extra' {
            if (-not $t8HasRealArtifacts) { Set-ItResult -Skipped -Because 'real artifacts not present locally'; return }
            $union = [System.Collections.Generic.HashSet[string]]::new([string[]]@($t8ReportedSet))
            $union.UnionWith([string[]]@($t8PhantomExcludedSet))
            $missingFromUnion = [System.Collections.Generic.HashSet[string]]::new([string[]]@($t8PopulationSet))
            $missingFromUnion.ExceptWith([string[]]@($union))
            $extraInUnion = [System.Collections.Generic.HashSet[string]]::new([string[]]@($union))
            $extraInUnion.ExceptWith([string[]]@($t8PopulationSet))
            $missingFromUnion.Count | Should -Be 0
            $extraInUnion.Count | Should -Be 0
        }

        It 'reported and phantom-excluded are disjoint -- no (endpoint, list, field) triple lands in both buckets' {
            if (-not $t8HasRealArtifacts) { Set-ItResult -Skipped -Because 'real artifacts not present locally'; return }
            $overlap = [System.Collections.Generic.HashSet[string]]::new([string[]]@($t8ReportedSet))
            $overlap.IntersectWith([string[]]@($t8PhantomExcludedSet))
            $overlap.Count | Should -Be 0
        }

        It 'the phantom-excluded count matches the real manifest''s phantomFieldCount exactly (34, full population)' {
            if (-not $t8HasRealArtifacts) { Set-ItResult -Skipped -Because 'real artifacts not present locally'; return }
            $t8PhantomExcludedSet.Count | Should -Be $t8Manifest.phantomFieldCount
            $t8PhantomExcludedSet.Count | Should -Be 34
        }

        It 'restricting the same diff to high-confidence-only gaps reproduces the doc-comment-pinned 13' {
            if (-not $t8HasRealArtifacts) { Set-ItResult -Skipped -Because 'real artifacts not present locally'; return }
            $populationHigh = @($t8PopulationRaw | Where-Object { $_.Confidence.Level -eq 'high' })
            $reportedHigh = @($t8ReportedRaw | Where-Object { $_.Confidence.Level -eq 'high' })
            $populationHighSet = Get-T8TripleSet -Gaps $populationHigh
            $reportedHighSet = Get-T8TripleSet -Gaps $reportedHigh
            $phantomHighSet = [System.Collections.Generic.HashSet[string]]::new([string[]]@($populationHighSet))
            $phantomHighSet.ExceptWith([string[]]@($reportedHighSet))
            $phantomHighSet.Count | Should -Be 13
        }

        It 'the in-memory reported set matches the real committed Reports/PfbApiDriftReport.json on disk exactly (no serialization-only divergence)' {
            if (-not $t8HasRealArtifacts) { Set-ItResult -Skipped -Because 'real artifacts not present locally'; return }
            $committedReportPath = Join-Path $repoRoot 'Reports/PfbApiDriftReport.json'
            if (-not (Test-Path $committedReportPath)) { Set-ItResult -Skipped -Because 'Reports/PfbApiDriftReport.json not present locally'; return }
            $committedManifest = Get-Content -Path $committedReportPath -Raw | ConvertFrom-Json -Depth 20
            $committedTripleSet = [System.Collections.Generic.HashSet[string]]::new()
            foreach ($g in $committedManifest.parameterGaps) {
                foreach ($f in @($g.missingQueryParameters)) { [void]$committedTripleSet.Add("$($g.endpoint)|query|$f") }
                foreach ($f in @($g.missingBodyProperties)) {
                    $name = if ($f -is [string]) { $f } else { $f.name }
                    [void]$committedTripleSet.Add("$($g.endpoint)|body|$name")
                }
                foreach ($f in @($g.readOnlyFields)) { [void]$committedTripleSet.Add("$($g.endpoint)|readOnly|$f") }
            }
            $diff = [System.Collections.Generic.HashSet[string]]::new([string[]]@($t8ReportedSet))
            $diff.SymmetricExceptWith([string[]]@($committedTripleSet))
            $diff.Count | Should -Be 0
        }
    }
}

Describe 'Build-PfbApiDriftReport (Task 7: systemic gaps, convention strength, phantom-field count, generatedFrom split -- own small fixture)' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
    BeforeAll {
        $script:t7FixtureRoot = Join-Path $TestDrive 't7fixture'
        $t7PublicDir = Join-Path $t7FixtureRoot 'Public/Fixture7'
        $t7PrivateDir = Join-Path $t7FixtureRoot 'Private'
        $t7SpecsDir = Join-Path $t7FixtureRoot 'specs'
        New-Item -ItemType Directory -Path $t7PublicDir, $t7PrivateDir, $t7SpecsDir -Force | Out-Null

        # Two endpoints, each missing the SAME query parameter ('shared_gap') and neither
        # exposing it -- this is what Get-PfbSystemicGaps is supposed to collapse into ONE
        # finding with EndpointCount 2. No cmdlet anywhere in this fixture exposes
        # 'shared_gap' as a Typed parameter, so Get-PfbConventionStrength should rank it at
        # CmdletCount 0 -- the "architectural gap, not a mechanical one" case (the
        # context_names precedent).
        Set-Content -Path (Join-Path $t7PublicDir 'Get-PfbFixtureAlpha.ps1') -Value @'
function Get-PfbFixtureAlpha {
    [CmdletBinding()]
    param([Parameter()] [PSCustomObject]$Array)
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'alpha' -AutoPaginate
}
'@
        # Beta is PARTIAL-confidence (an unresolved -Weird parameter, no -Attributes escape
        # hatch) -- exercises the Markdown confidence marker/footnote wiring on a fixture
        # this task fully controls. It also misses 'shared_gap', but Get-PfbSystemicGaps
        # is aggregated ONLY over 'high'-confidence gaps (this task's own precedent, same
        # as the real 253/109 acceptance figures), so Beta must NOT count towards
        # 'shared_gap's systemic EndpointCount below -- Gamma (high-confidence) is the
        # fixture's second contributor to that finding instead.
        Set-Content -Path (Join-Path $t7PublicDir 'Get-PfbFixtureBeta.ps1') -Value @'
function Get-PfbFixtureBeta {
    [CmdletBinding()]
    param(
        [Parameter()] [PSCustomObject]$Array,
        [Parameter()] [string]$Weird
    )
    if ($Weird) { Write-Verbose $Weird }
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'beta' -AutoPaginate
}
'@
        # Gamma is fully-typed (high-confidence) and also misses 'shared_gap' -- together
        # with Alpha, this is the systemic-gaps EndpointCount-2 case.
        Set-Content -Path (Join-Path $t7PublicDir 'Get-PfbFixtureGamma.ps1') -Value @'
function Get-PfbFixtureGamma {
    [CmdletBinding()]
    param([Parameter()] [PSCustomObject]$Array)
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'gamma' -AutoPaginate
}
'@

        $t7SpecV1 = [ordered]@{
            openapi = '3.0.1'; info = @{ version = '1.0' }
            paths   = [ordered]@{
                '/alpha' = [ordered]@{ get = [ordered]@{ parameters = @(
                            [ordered]@{ name = 'shared_gap'; 'in' = 'query'; schema = [ordered]@{ type = 'string' } }
                            [ordered]@{ name = 'withdrawn_field'; 'in' = 'query'; schema = [ordered]@{ type = 'string' } }
                        ) } }
                '/beta'  = [ordered]@{ get = [ordered]@{ parameters = @(
                            [ordered]@{ name = 'shared_gap'; 'in' = 'query'; schema = [ordered]@{ type = 'string' } }
                        ) } }
                '/gamma' = [ordered]@{ get = [ordered]@{ parameters = @(
                            [ordered]@{ name = 'shared_gap'; 'in' = 'query'; schema = [ordered]@{ type = 'string' } }
                        ) } }
            }
            components = [ordered]@{ schemas = [ordered]@{} }
        }
        # v1.1 is the NEWEST ANALYSED spec: 'withdrawn_field' is gone -- a phantom field
        # (accumulated in the capability map's own /alpha entry below, absent here).
        $t7SpecV2 = [ordered]@{
            openapi = '3.0.1'; info = @{ version = '1.1' }
            paths   = [ordered]@{
                '/alpha' = [ordered]@{ get = [ordered]@{ parameters = @(
                            [ordered]@{ name = 'shared_gap'; 'in' = 'query'; schema = [ordered]@{ type = 'string' } }
                        ) } }
                '/beta'  = [ordered]@{ get = [ordered]@{ parameters = @(
                            [ordered]@{ name = 'shared_gap'; 'in' = 'query'; schema = [ordered]@{ type = 'string' } }
                        ) } }
                '/gamma' = [ordered]@{ get = [ordered]@{ parameters = @(
                            [ordered]@{ name = 'shared_gap'; 'in' = 'query'; schema = [ordered]@{ type = 'string' } }
                        ) } }
            }
            components = [ordered]@{ schemas = [ordered]@{} }
        }
        $t7SpecV1 | ConvertTo-Json -Depth 20 | Set-Content -Path (Join-Path $t7SpecsDir 'fb1.0.json')
        $t7SpecV2 | ConvertTo-Json -Depth 20 | Set-Content -Path (Join-Path $t7SpecsDir 'fb1.1.json')
        # On disk but NOT in the capability map's own generatedFrom below -- deliberately
        # engineers the analysedVersions/availableSpecVersions divergence this task's
        # generatedFrom-split item exists to surface.
        $t7SpecV2 | ConvertTo-Json -Depth 20 | Set-Content -Path (Join-Path $t7SpecsDir 'fb1.2.json')

        $script:t7CapabilityMapPath = Join-Path $t7FixtureRoot 'PfbCapabilityMap.json'
        [ordered]@{
            schemaVersion = 1
            generatedFrom = @('1.0', '1.1')
            endpoints     = [ordered]@{
                'GET /alpha' = [ordered]@{ minVersion = '1.0'; parameters = [ordered]@{ shared_gap = '1.0'; withdrawn_field = '1.0' }; bodyProperties = [ordered]@{} }
                'GET /beta'  = [ordered]@{ minVersion = '1.0'; parameters = [ordered]@{ shared_gap = '1.0' }; bodyProperties = [ordered]@{} }
                'GET /gamma' = [ordered]@{ minVersion = '1.0'; parameters = [ordered]@{ shared_gap = '1.0' }; bodyProperties = [ordered]@{} }
            }
        } | ConvertTo-Json -Depth 20 | Set-Content -Path $t7CapabilityMapPath

        $script:t7FieldCmdletMapPath = Join-Path $t7FixtureRoot 'PfbFieldCmdletMap.json'
        [ordered]@{ schemaVersion = 1; generatedFrom = @('1.0', '1.1'); entries = @(); attributesOnly = @(); typedUnresolved = @() } |
            ConvertTo-Json -Depth 20 | Set-Content -Path $t7FieldCmdletMapPath

        $script:t7OutputPath = Join-Path $TestDrive 't7output/report.json'
        $script:t7ReportPath = Join-Path $TestDrive 't7output/report.md'
        & $builderScript -SpecsDirectory $t7SpecsDir -PublicDirectory $t7PublicDir -PrivateDirectory $t7PrivateDir `
            -CapabilityMapPath $t7CapabilityMapPath -FieldCmdletMapPath $t7FieldCmdletMapPath `
            -OutputPath $t7OutputPath -ReportPath $t7ReportPath
        $script:t7Manifest = Get-Content -Path $t7OutputPath -Raw | ConvertFrom-Json -Depth 20
        $script:t7ReportText = Get-Content -Path $t7ReportPath -Raw
    }

    It 'collapses the field missing on both HIGH-CONFIDENCE fixture endpoints into ONE systemic-gaps finding with EndpointCount 2, excluding the partial-confidence endpoint that also misses it' {
        $finding = $t7Manifest.systemicGaps | Where-Object { $_.name -eq 'shared_gap' }
        $finding | Should -Not -BeNullOrEmpty
        $finding.endpointCount | Should -Be 2
        $finding.endpoints | Should -Be @('GET /alpha', 'GET /gamma')
    }

    It 'ranks conventionStrength at CmdletCount 0 for a name no fixture cmdlet exposes (the architectural-gap case)' {
        $strength = $t7Manifest.conventionStrength | Where-Object { $_.name -eq 'shared_gap' }
        $strength | Should -Not -BeNullOrEmpty
        $strength.cmdletCount | Should -Be 0
        @($strength.cmdlets).Count | Should -Be 0
    }

    It 'counts the withdrawn (phantom) field, filtered out of every list, in phantomFieldCount' {
        $t7Manifest.phantomFieldCount | Should -Be 1
        # And confirms it never leaks into a real gap list on GET /alpha.
        $alphaGap = $t7Manifest.parameterGaps | Where-Object { $_.endpoint -eq 'GET /alpha' }
        $alphaGap.missingQueryParameters | Should -Not -Contain 'withdrawn_field'
    }

    It 'splits analysedVersions (capability map) from availableSpecVersions (specs on disk) and warns when they disagree' {
        $t7Manifest.analysedVersions | Should -Be @('1.0', '1.1')
        $t7Manifest.availableSpecVersions | Should -Be @('1.0', '1.1', '1.2')
        $t7Manifest.versionDivergenceWarning | Should -Not -BeNullOrEmpty
        $t7Manifest.versionDivergenceWarning | Should -Match 'analysedVersions'
        $t7Manifest.versionDivergenceWarning | Should -Match 'availableSpecVersions'
    }

    It 'marks the partial-confidence fixture endpoint (GET /beta) with a visible unresolved-parameter marker in the Markdown table' {
        $betaGap = $t7Manifest.parameterGaps | Where-Object { $_.endpoint -eq 'GET /beta' }
        $betaGap.confidence.level | Should -Be 'partial'
        $t7ReportText | Should -Match 'unresolved param'
    }

    It 'gives the partial-confidence unresolved parameter a Partial-confidence detail row with a file:line a human can open' {
        $t7ReportText | Should -Match '### Partial-confidence detail'
        $t7ReportText | Should -Match '-Weird'
        $t7ReportText | Should -Match 'Get-PfbFixtureBeta\.ps1:\d+'
    }

    It 'orders Markdown sections: How to read this report -> Summary -> Systemic gaps -> Parameter gaps -> Read-only fields -> Uncovered endpoints' {
        $howToIndex = $t7ReportText.IndexOf('## How to read this report')
        $summaryIndex = $t7ReportText.IndexOf('## Summary')
        $systemicIndex = $t7ReportText.IndexOf('## Systemic gaps')
        $paramGapsIndex = $t7ReportText.IndexOf('## Parameter gaps')
        $howToIndex | Should -BeGreaterThan -1
        $summaryIndex | Should -BeGreaterThan $howToIndex
        $systemicIndex | Should -BeGreaterThan $summaryIndex
        $paramGapsIndex | Should -BeGreaterThan $systemicIndex
    }

    It 'reproduces the decision-6 false-positive procedure verbatim in "How to read this report"' {
        $t7ReportText | Should -Match 'This report accepts \*\*false positives in order to eliminate false negatives\*\*'
        $t7ReportText | Should -Match 'Open the named parameter at the given `file:line` and follow where its value goes\.'
        $t7ReportText | Should -Match 'the gap is a false positive AND a tooling bug'
        $t7ReportText | Should -Match 'If it reaches the wire under a different name'
        $t7ReportText | Should -Match 'the reported gap may still be real; check that field against the spec'
        $t7ReportText | Should -Match 'If it never reaches the wire'
        $t7ReportText | Should -Match 'a false positive costs a reader one `file:line` lookup; a false negative costs an undetected gap indefinitely'
    }

    It 'the Summary section reports phantom fields and systemic gaps, not just the pre-Task-7 bullets' {
        $t7ReportText | Should -Match 'Phantom fields silently excluded[^:]*: 1'
        $t7ReportText | Should -Match 'Systemic gaps \(distinct field names[^:]*: 1'
    }
}
