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

Describe 'Build-PfbApiDriftReport (real generated artifacts, skips gracefully if absent)' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
    It 'produces a manifest against the real Public/Private tree and Reports/ + Data/ inputs' {
        $realCapabilityMapPath = Join-Path $repoRoot 'Data/PfbCapabilityMap.json'
        $realFieldCmdletMapPath = Join-Path $repoRoot 'Reports/PfbFieldCmdletMap.json'
        $realSpecsDir = Join-Path $repoRoot 'tools/specs'
        if (-not (Test-Path $realCapabilityMapPath) -or -not (Test-Path $realFieldCmdletMapPath) -or
            -not (Test-Path $realSpecsDir) -or -not (Get-ChildItem $realSpecsDir -Filter 'fb*.json' -ErrorAction SilentlyContinue)) {
            Set-ItResult -Skipped -Because 'Data/PfbCapabilityMap.json, Reports/PfbFieldCmdletMap.json, or tools/specs/ not present locally'
            return
        }

        $realOutput = Join-Path $TestDrive 'realOutput/report.json'
        $realReport = Join-Path $TestDrive 'realOutput/report.md'
        & $builderScript -SpecsDirectory $realSpecsDir -PublicDirectory (Join-Path $repoRoot 'Public') -PrivateDirectory (Join-Path $repoRoot 'Private') `
            -CapabilityMapPath $realCapabilityMapPath -FieldCmdletMapPath $realFieldCmdletMapPath `
            -OutputPath $realOutput -ReportPath $realReport
        Test-Path $realOutput | Should -BeTrue
    }
}
