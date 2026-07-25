#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Integration tests for tools/Build-PfbCapabilityMap.ps1 against small synthetic
    spec fixtures (no dependency on the real cached specs in tools/specs/), plus a
    shape/sanity check of the real committed manifest when present.
#>

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $script:builderScript = Join-Path $repoRoot 'tools/Build-PfbCapabilityMap.ps1'
}

Describe 'Build-PfbCapabilityMap: introduced-in diffing' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
    BeforeAll {
        New-Item -ItemType Directory -Path 'TestDrive:\specs' -Force | Out-Null

        # v9.0: baseline — GET /widgets (param: filter), POST /widgets (body: name)
        $specV1 = [ordered]@{
            openapi = '3.0.1'
            info    = @{ version = '9.0' }
            paths   = [ordered]@{
                '/api/9.0/widgets' = [ordered]@{
                    get  = @{
                        parameters = @(@{ name = 'filter'; 'in' = 'query'; schema = @{ type = 'string' } })
                    }
                    post = @{
                        requestBody = @{
                            content = @{
                                'application/json' = @{
                                    schema = @{
                                        type       = 'object'
                                        properties = @{ name = @{ type = 'string' } }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        # v9.1: adds a 'sort' param to the existing GET, and a brand-new endpoint.
        $specV2 = [ordered]@{
            openapi = '3.0.1'
            info    = @{ version = '9.1' }
            paths   = [ordered]@{
                '/api/9.1/widgets' = [ordered]@{
                    get  = @{
                        parameters = @(
                            @{ name = 'filter'; 'in' = 'query'; schema = @{ type = 'string' } }
                            @{ name = 'sort'; 'in' = 'query'; schema = @{ type = 'string' } }
                        )
                    }
                    post = @{
                        requestBody = @{
                            content = @{
                                'application/json' = @{
                                    schema = @{
                                        type       = 'object'
                                        properties = @{ name = @{ type = 'string' } }
                                    }
                                }
                            }
                        }
                    }
                }
                '/api/9.1/gadgets' = [ordered]@{
                    get = @{
                        parameters = @(@{ name = 'id'; 'in' = 'query'; schema = @{ type = 'string' } })
                    }
                }
            }
        }

        $specV1 | ConvertTo-Json -Depth 20 | Set-Content -Path 'TestDrive:\specs\fb9.0.json'
        $specV2 | ConvertTo-Json -Depth 20 | Set-Content -Path 'TestDrive:\specs\fb9.1.json'

        & $builderScript -SpecsDirectory 'TestDrive:\specs' -OutputPath 'TestDrive:\output\manifest.json'
        $script:manifest = Get-Content -Path 'TestDrive:\output\manifest.json' -Raw | ConvertFrom-Json -Depth 20
    }

    It 'records generatedFrom in ascending version order' {
        $manifest.generatedFrom | Should -Be @('9.0', '9.1')
    }

    It 'attributes an endpoint present since the earliest version to that version' {
        $manifest.endpoints.'GET /widgets'.minVersion | Should -Be '9.0'
        $manifest.endpoints.'POST /widgets'.minVersion | Should -Be '9.0'
    }

    It 'attributes a brand-new endpoint to the version it first appears in' {
        $manifest.endpoints.'GET /gadgets'.minVersion | Should -Be '9.1'
    }

    It 'attributes a pre-existing parameter to the endpoint''s earliest version' {
        $manifest.endpoints.'GET /widgets'.parameters.filter | Should -Be '9.0'
    }

    It 'attributes a parameter added later to the version it first appears in, not the endpoint''s' {
        $manifest.endpoints.'GET /widgets'.parameters.sort | Should -Be '9.1'
    }

    It 'attributes request-body properties correctly' {
        $manifest.endpoints.'POST /widgets'.bodyProperties.name | Should -Be '9.0'
    }

    It 'normalizes the version-prefixed path consistently across versions (does not create duplicate endpoints)' {
        ($manifest.endpoints.PSObject.Properties.Name | Where-Object { $_ -like '*widgets*' }).Count | Should -Be 2
    }
}

Describe 'Build-PfbCapabilityMap: manifest shape' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
    BeforeAll {
        New-Item -ItemType Directory -Path 'TestDrive:\shapeSpecs' -Force | Out-Null
        $spec = [ordered]@{
            openapi = '3.0.1'
            info    = @{ version = '9.0' }
            paths   = [ordered]@{
                '/api/9.0/widgets' = [ordered]@{ get = @{} }
            }
        }
        $spec | ConvertTo-Json -Depth 20 | Set-Content -Path 'TestDrive:\shapeSpecs\fb9.0.json'

        & $builderScript -SpecsDirectory 'TestDrive:\shapeSpecs' -OutputPath 'TestDrive:\shapeOutput\manifest.json'
        $script:shapeManifest = Get-Content -Path 'TestDrive:\shapeOutput\manifest.json' -Raw | ConvertFrom-Json -Depth 20
    }

    It 'has the required top-level keys' {
        $shapeManifest.PSObject.Properties.Name | Should -Contain 'schemaVersion'
        $shapeManifest.PSObject.Properties.Name | Should -Contain 'generatedFrom'
        $shapeManifest.PSObject.Properties.Name | Should -Contain 'endpointCount'
        $shapeManifest.PSObject.Properties.Name | Should -Contain 'endpoints'
    }

    It 'reports an endpointCount matching the actual number of endpoint entries' {
        $shapeManifest.endpointCount | Should -Be $shapeManifest.endpoints.PSObject.Properties.Name.Count
    }

    It 'does NOT include an enums key (no structural enum data exists in the source specs)' {
        $shapeManifest.endpoints.'GET /widgets'.PSObject.Properties.Name | Should -Not -Contain 'enums'
    }

    It 'throws a clear error when no cached specs are present' {
        New-Item -ItemType Directory -Path 'TestDrive:\emptySpecs' -Force | Out-Null
        { & $builderScript -SpecsDirectory 'TestDrive:\emptySpecs' -OutputPath 'TestDrive:\emptyOutput\manifest.json' } |
            Should -Throw '*No cached specs found*'
    }
}

Describe 'Build-PfbCapabilityMap: readOnly/deprecated last-seen-wins and parameterComponents' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
    BeforeAll {
        New-Item -ItemType Directory -Path 'TestDrive:\roSpecs' -Force | Out-Null

        # v9.0 (older): 'name' is readOnly, 'category' is writable. 'legacy-endpoint' exists
        # with a readOnly 'oldFlag' and is REMOVED entirely from v9.1 (tests "endpoint
        # disappears from later specs keeps its last-seen readOnly value"). No deprecated
        # fields anywhere yet. GET /widgets has a $ref'd 'filter' query parameter.
        $specV1 = [ordered]@{
            openapi    = '3.0.1'
            info       = @{ version = '9.0' }
            paths      = [ordered]@{
                '/api/9.0/widgets'          = [ordered]@{
                    get   = @{
                        parameters = @(@{ '$ref' = '#/components/parameters/Widget_filter' })
                    }
                    patch = @{
                        requestBody = @{
                            content = @{
                                'application/json' = @{
                                    schema = @{
                                        type       = 'object'
                                        properties = [ordered]@{
                                            name     = @{ type = 'string'; readOnly = $true }
                                            category = @{ type = 'string' }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                '/api/9.0/legacy-endpoint'  = [ordered]@{
                    patch = @{
                        requestBody = @{
                            content = @{
                                'application/json' = @{
                                    schema = @{
                                        type       = 'object'
                                        properties = [ordered]@{
                                            oldFlag = @{ type = 'string'; readOnly = $true }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            components = [ordered]@{
                parameters = [ordered]@{
                    Widget_filter = [ordered]@{ name = 'filter'; 'in' = 'query'; schema = @{ type = 'string' } }
                }
            }
        }

        # v9.1 (newer): 'name' flips to writable, 'category' flips to readOnly, and a brand
        # new 'secretNote' field is deprecated. 'legacy-endpoint' is gone entirely.
        $specV2 = [ordered]@{
            openapi    = '3.0.1'
            info       = @{ version = '9.1' }
            paths      = [ordered]@{
                '/api/9.1/widgets' = [ordered]@{
                    get   = @{
                        parameters = @(@{ '$ref' = '#/components/parameters/Widget_filter' })
                    }
                    patch = @{
                        requestBody = @{
                            content = @{
                                'application/json' = @{
                                    schema = @{
                                        type       = 'object'
                                        properties = [ordered]@{
                                            name       = @{ type = 'string' }
                                            category   = @{ type = 'string'; readOnly = $true }
                                            secretNote = @{ type = 'string'; deprecated = $true }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            components = [ordered]@{
                parameters = [ordered]@{
                    Widget_filter = [ordered]@{ name = 'filter'; 'in' = 'query'; schema = @{ type = 'string' } }
                }
            }
        }

        $specV1 | ConvertTo-Json -Depth 20 | Set-Content -Path 'TestDrive:\roSpecs\fb9.0.json'
        $specV2 | ConvertTo-Json -Depth 20 | Set-Content -Path 'TestDrive:\roSpecs\fb9.1.json'

        & $builderScript -SpecsDirectory 'TestDrive:\roSpecs' -OutputPath 'TestDrive:\roOutput\manifest.json'
        $script:roManifest = Get-Content -Path 'TestDrive:\roOutput\manifest.json' -Raw | ConvertFrom-Json -Depth 20
    }

    It 'the decision-1 regression: a field readOnly in the older version and writable in the newer ends up ABSENT from readOnlyBodyProperties' {
        $roManifest.endpoints.'PATCH /widgets'.readOnlyBodyProperties | Should -Not -Contain 'name'
    }

    It 'the mirror case: a field writable in the older version and readOnly in the newer ends up PRESENT in readOnlyBodyProperties' {
        $roManifest.endpoints.'PATCH /widgets'.readOnlyBodyProperties | Should -Contain 'category'
    }

    It 'an endpoint that disappears from later specs keeps its last-seen readOnlyBodyProperties value' {
        $roManifest.endpoints.'PATCH /legacy-endpoint'.readOnlyBodyProperties | Should -Be @('oldFlag')
    }

    It 'omits deprecatedBodyProperties entirely when empty' {
        $roManifest.endpoints.'PATCH /legacy-endpoint'.PSObject.Properties.Name | Should -Not -Contain 'deprecatedBodyProperties'
    }

    It 'includes deprecatedBodyProperties when non-empty' {
        $roManifest.endpoints.'PATCH /widgets'.deprecatedBodyProperties | Should -Be @('secretNote')
    }

    It 'emits parameterComponents per endpoint with the { paramName: componentName } shape' {
        $roManifest.endpoints.'GET /widgets'.parameterComponents.filter | Should -Be 'Widget_filter'
    }

    It 'leaves the pre-existing minVersion/parameters/bodyProperties keys unaffected by the new keys' {
        $entry = $roManifest.endpoints.'PATCH /widgets'
        $entry.minVersion | Should -Be '9.0'
        $entry.bodyProperties.name | Should -Be '9.0'
        $entry.bodyProperties.category | Should -Be '9.0'
        $entry.bodyProperties.secretNote | Should -Be '9.1'
    }
}

Describe 'Build-PfbCapabilityMap: -MaxVersion cap' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
    BeforeAll {
        New-Item -ItemType Directory -Path 'TestDrive:\capSpecs' -Force | Out-Null

        $specV1 = [ordered]@{
            openapi = '3.0.1'
            info    = @{ version = '9.0' }
            paths   = [ordered]@{ '/api/9.0/widgets' = [ordered]@{ get = @{} } }
        }
        $specV2 = [ordered]@{
            openapi = '3.0.1'
            info    = @{ version = '9.1' }
            paths   = [ordered]@{ '/api/9.1/widgets' = [ordered]@{ get = @{} } }
        }
        # A newer version that must be excluded by the cap -- adds a brand-new endpoint.
        $specV3 = [ordered]@{
            openapi = '3.0.1'
            info    = @{ version = '9.2' }
            paths   = [ordered]@{
                '/api/9.2/widgets'  = [ordered]@{ get = @{} }
                '/api/9.2/newthing' = [ordered]@{ get = @{} }
            }
        }

        $specV1 | ConvertTo-Json -Depth 20 | Set-Content -Path 'TestDrive:\capSpecs\fb9.0.json'
        $specV2 | ConvertTo-Json -Depth 20 | Set-Content -Path 'TestDrive:\capSpecs\fb9.1.json'
        $specV3 | ConvertTo-Json -Depth 20 | Set-Content -Path 'TestDrive:\capSpecs\fb9.2.json'

        & $builderScript -SpecsDirectory 'TestDrive:\capSpecs' -OutputPath 'TestDrive:\capOutput\manifest.json' -MaxVersion '9.1'
        $script:capManifest = Get-Content -Path 'TestDrive:\capOutput\manifest.json' -Raw | ConvertFrom-Json -Depth 20
    }

    It 'excludes a cached spec newer than -MaxVersion from generatedFrom' {
        $capManifest.generatedFrom | Should -Be @('9.0', '9.1')
    }

    It 'excludes an endpoint that only exists in a version newer than -MaxVersion' {
        $capManifest.endpoints.PSObject.Properties.Name | Should -Not -Contain 'GET /newthing'
    }

    It 'still includes endpoints from versions at or below -MaxVersion' {
        $capManifest.endpoints.PSObject.Properties.Name | Should -Contain 'GET /widgets'
    }
}

Describe 'Real committed capability map (skips gracefully if not yet generated)' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
    BeforeAll {
        $repoRoot = Split-Path -Parent $PSScriptRoot
        $script:realManifestPath = Join-Path $repoRoot 'Data/PfbCapabilityMap.json'
        $script:realSpecsDir = Join-Path $repoRoot 'tools/specs'
    }

    It 'every (method, path) in the newest cached spec is represented in the manifest' {
        if (-not (Test-Path $realManifestPath) -or -not (Test-Path $realSpecsDir)) {
            Set-ItResult -Skipped -Because 'Data/PfbCapabilityMap.json or tools/specs/ not present (run Update-PfbApiSpecs.ps1 and Build-PfbCapabilityMap.ps1 first)'
            return
        }

        . (Join-Path $repoRoot 'tools/lib/PfbSpecTools.ps1')

        $specFiles = Get-ChildItem -Path $realSpecsDir -Filter 'fb*.json' | Where-Object { $_.BaseName -match '^fb(\d+)\.(\d+)$' }
        if (-not $specFiles) {
            Set-ItResult -Skipped -Because 'No cached spec files found under tools/specs/'
            return
        }
        $newest = $specFiles | ForEach-Object {
            $null = $_.BaseName -match '^fb(\d+)\.(\d+)$'
            [PSCustomObject]@{ File = $_; Major = [int]$Matches[1]; Minor = [int]$Matches[2] }
        } | Sort-Object Major, Minor | Select-Object -Last 1

        $spec = Get-Content -Path $newest.File.FullName -Raw | ConvertFrom-Json -Depth 64
        $capabilities = Get-PfbSpecCapabilities -Spec $spec
        $manifest = Get-Content -Path $realManifestPath -Raw | ConvertFrom-Json -Depth 20
        $manifestKeys = [System.Collections.Generic.HashSet[string]]::new([string[]]$manifest.endpoints.PSObject.Properties.Name)

        $missing = $capabilities | ForEach-Object { "$($_.Method) $($_.Path)" } | Where-Object { -not $manifestKeys.Contains($_) }

        $missing | Should -BeNullOrEmpty -Because "these endpoints exist in the newest spec but are missing from the manifest: $($missing -join ', ')"
    }
}
