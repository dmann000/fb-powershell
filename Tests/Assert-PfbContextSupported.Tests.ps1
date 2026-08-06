#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Covers the Fusion context gates in Private/Assert-PfbContextSupported.ps1.
#>

BeforeAll {
    Import-Module "$PSScriptRoot/../PureStorageFlashBladePowerShell.psd1" -Force
}

# InModuleScope inside each It (Describe-level fails at discovery here -- see Global
# Constraints). The fixtures are rebuilt per It as plain LOCALS rather than shared from a
# BeforeEach: $ctx needs the private New-PfbContext so it has to be inside module scope, and a
# `$script:` fixture inside InModuleScope would write to the MODULE's script scope and leak past
# the file. The repetition is deliberate and is the price of the block actually running.
Describe 'Assert-PfbContextCapability' {
    It 'allows an endpoint whose entry lists context_names' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $ctx = New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-B'))
            $map = [PSCustomObject]@{
                generatedFrom = @('2.0', '2.26')
                parameterComponentDefaults = [PSCustomObject]@{}
                endpoints = [PSCustomObject]@{
                    'GET /file-systems'   = [PSCustomObject]@{ parameters = [PSCustomObject]@{ context_names = '2.23'; allow_errors = '2.23' }; contextScope = [PSCustomObject]@{ scope = 'array'; provenance = 'default' } }
                    'GET /alert-watchers' = [PSCustomObject]@{ parameters = [PSCustomObject]@{ names = '2.0' };                                 contextScope = [PSCustomObject]@{ scope = 'array'; provenance = 'default' } }
                }
            }
            $fb = [PSCustomObject]@{ Endpoint = 'fb.example'; ApiVersion = '2.26' }
            { Assert-PfbContextCapability -Array $fb -Method 'GET' -Endpoint 'file-systems' -Context $ctx -CapabilityMap $map } |
                Should -Not -Throw
        }
    }
    It 'throws when the entry exists but lacks context_names (the likeliest staleness case)' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $ctx = New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-B'))
            $map = [PSCustomObject]@{
                generatedFrom = @('2.0', '2.26')
                parameterComponentDefaults = [PSCustomObject]@{}
                endpoints = [PSCustomObject]@{
                    'GET /file-systems'   = [PSCustomObject]@{ parameters = [PSCustomObject]@{ context_names = '2.23'; allow_errors = '2.23' }; contextScope = [PSCustomObject]@{ scope = 'array'; provenance = 'default' } }
                    'GET /alert-watchers' = [PSCustomObject]@{ parameters = [PSCustomObject]@{ names = '2.0' };                                 contextScope = [PSCustomObject]@{ scope = 'array'; provenance = 'default' } }
                }
            }
            $fb = [PSCustomObject]@{ Endpoint = 'fb.example'; ApiVersion = '2.26' }
            { Assert-PfbContextCapability -Array $fb -Method 'GET' -Endpoint 'alert-watchers' -Context $ctx -CapabilityMap $map } |
                Should -Throw -ExpectedMessage '*GET /alert-watchers*does not support*'
        }
    }
    It 'throws when there is no entry at all, within the scanned range' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $ctx = New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-B'))
            $map = [PSCustomObject]@{
                generatedFrom = @('2.0', '2.26')
                parameterComponentDefaults = [PSCustomObject]@{}
                endpoints = [PSCustomObject]@{
                    'GET /file-systems'   = [PSCustomObject]@{ parameters = [PSCustomObject]@{ context_names = '2.23'; allow_errors = '2.23' }; contextScope = [PSCustomObject]@{ scope = 'array'; provenance = 'default' } }
                    'GET /alert-watchers' = [PSCustomObject]@{ parameters = [PSCustomObject]@{ names = '2.0' };                                 contextScope = [PSCustomObject]@{ scope = 'array'; provenance = 'default' } }
                }
            }
            $fb = [PSCustomObject]@{ Endpoint = 'fb.example'; ApiVersion = '2.26' }
            { Assert-PfbContextCapability -Array $fb -Method 'GET' -Endpoint 'not-in-map' -Context $ctx -CapabilityMap $map } |
                Should -Throw -ExpectedMessage '*GET /not-in-map*'
        }
    }
    It 'stays permissive when the array is NEWER than the scanned range' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $ctx = New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-B'))
            $map = [PSCustomObject]@{
                generatedFrom = @('2.0', '2.26')
                parameterComponentDefaults = [PSCustomObject]@{}
                endpoints = [PSCustomObject]@{
                    'GET /file-systems'   = [PSCustomObject]@{ parameters = [PSCustomObject]@{ context_names = '2.23'; allow_errors = '2.23' }; contextScope = [PSCustomObject]@{ scope = 'array'; provenance = 'default' } }
                    'GET /alert-watchers' = [PSCustomObject]@{ parameters = [PSCustomObject]@{ names = '2.0' };                                 contextScope = [PSCustomObject]@{ scope = 'array'; provenance = 'default' } }
                }
            }
            # 2.40 is beyond generatedFrom's upper bound, so the map cannot be authoritative.
            $fb = [PSCustomObject]@{ Endpoint = 'fb.example'; ApiVersion = '2.40' }
            { Assert-PfbContextCapability -Array $fb -Method 'GET' -Endpoint 'not-in-map' -Context $ctx -CapabilityMap $map } |
                Should -Not -Throw
            { Assert-PfbContextCapability -Array $fb -Method 'GET' -Endpoint 'alert-watchers' -Context $ctx -CapabilityMap $map } |
                Should -Not -Throw
        }
    }
    It 'treats a local-array context as a context and still throws' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            # Deliberate divergence from the server, which short-circuits a local context
            # before validating. A cmdlet that works only SOME of the time depending on which
            # array the context names is a worse contract than one that fails consistently.
            $map = [PSCustomObject]@{
                generatedFrom = @('2.0', '2.26')
                parameterComponentDefaults = [PSCustomObject]@{}
                endpoints = [PSCustomObject]@{
                    'GET /file-systems'   = [PSCustomObject]@{ parameters = [PSCustomObject]@{ context_names = '2.23'; allow_errors = '2.23' }; contextScope = [PSCustomObject]@{ scope = 'array'; provenance = 'default' } }
                    'GET /alert-watchers' = [PSCustomObject]@{ parameters = [PSCustomObject]@{ names = '2.0' };                                 contextScope = [PSCustomObject]@{ scope = 'array'; provenance = 'default' } }
                }
            }
            $fb = [PSCustomObject]@{ Endpoint = 'fb.example'; ApiVersion = '2.26' }
            $local = New-PfbContext -Entries @((New-PfbContextEntry -Name 'fb.example'))
            { Assert-PfbContextCapability -Array $fb -Method 'GET' -Endpoint 'alert-watchers' -Context $local -CapabilityMap $map } |
                Should -Throw -ExpectedMessage '*does not support*'
        }
    }
    It 'applies the throw to GET as uniformly as to a mutation' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $ctx = New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-B'))
            $map = [PSCustomObject]@{
                generatedFrom = @('2.0', '2.26')
                parameterComponentDefaults = [PSCustomObject]@{}
                endpoints = [PSCustomObject]@{
                    'GET /file-systems'   = [PSCustomObject]@{ parameters = [PSCustomObject]@{ context_names = '2.23'; allow_errors = '2.23' }; contextScope = [PSCustomObject]@{ scope = 'array'; provenance = 'default' } }
                    'GET /alert-watchers' = [PSCustomObject]@{ parameters = [PSCustomObject]@{ names = '2.0' };                                 contextScope = [PSCustomObject]@{ scope = 'array'; provenance = 'default' } }
                }
            }
            $fb = [PSCustomObject]@{ Endpoint = 'fb.example'; ApiVersion = '2.26' }
            foreach ($m in 'GET', 'POST', 'PATCH', 'PUT', 'DELETE') {
                { Assert-PfbContextCapability -Array $fb -Method $m -Endpoint 'alert-watchers' -Context $ctx -CapabilityMap $map } |
                    Should -Throw -ExpectedMessage '*does not support*'
            }
        }
    }
}

# Same It-level InModuleScope rule as above: New-PfbContext, Get-PfbCapabilityMap and
# Assert-PfbContextCardinality are all private, so without module scope every It here raises
# CommandNotFoundException -- which would silently satisfy the throw test below.
Describe 'Assert-PfbContextCardinality' {
    It 'throws for a multi-value context on a non-capable endpoint, naming the narrowing fix' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $multi = New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-B'), (New-PfbContextEntry -Name 'FB-C'))
            $map = Get-PfbCapabilityMap
            { Assert-PfbContextCardinality -Method 'GET' -Endpoint 'presets/workload' -Context $multi -CapabilityMap $map } |
                Should -Throw -ExpectedMessage '*accepts only one context*'
        }
    }
    It 'allows a multi-value context on a capable endpoint' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $multi = New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-B'), (New-PfbContextEntry -Name 'FB-C'))
            $map = Get-PfbCapabilityMap
            { Assert-PfbContextCardinality -Method 'GET' -Endpoint 'file-systems' -Context $multi -CapabilityMap $map } |
                Should -Not -Throw
        }
    }
    It 'never throws for a single-value context, capable or not' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $single = New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-B'))
            $map = Get-PfbCapabilityMap
            { Assert-PfbContextCardinality -Method 'GET' -Endpoint 'presets/workload' -Context $single -CapabilityMap $map } |
                Should -Not -Throw
        }
    }
    # Fix round 1, Important 1. Resolve-PfbParameterComponent returns the map's DEFAULT component
    # for the 256 entries that do not declare context_names, so without a precondition the
    # cardinality rule reads $false for them and this gate advised "narrow the context to a single
    # name" for an endpoint that takes no context at all -- and it fired precisely where
    # Assert-PfbContextCapability deliberately abstains (array beyond the map's scanned range).
    It 'stays silent for an entry that declares no context_names, even beyond map coverage' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $multi = New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-B'), (New-PfbContextEntry -Name 'FB-C'))
            $map = [PSCustomObject]@{
                generatedFrom = @('2.0', '2.28')
                parameterComponentDefaults = [PSCustomObject]@{ context_names = 'Context_names' }
                endpoints = [PSCustomObject]@{
                    'GET /active-directory' = [PSCustomObject]@{ parameters = [PSCustomObject]@{ names = '2.0' } }
                }
            }
            { Assert-PfbContextCardinality -Method 'GET' -Endpoint 'active-directory' -Context $multi -CapabilityMap $map } |
                Should -Not -Throw
        }
    }
    It 'stays silent for an endpoint absent from the map, in either gate order' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $multi = New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-B'), (New-PfbContextEntry -Name 'FB-C'))
            $map = [PSCustomObject]@{
                generatedFrom = @('2.0', '2.28')
                parameterComponentDefaults = [PSCustomObject]@{ context_names = 'Context_names' }
                endpoints = [PSCustomObject]@{}
            }
            { Assert-PfbContextCardinality -Method 'GET' -Endpoint 'not-an-endpoint' -Context $multi -CapabilityMap $map } |
                Should -Not -Throw
        }
    }
}

Describe 'Test-PfbEndpointDeclaresContextNames' {
    It 'is true only when the parameters collection actually lists context_names' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $declares = [PSCustomObject]@{ parameters = [PSCustomObject]@{ context_names = '2.23'; allow_errors = '2.23' } }
            $lacks    = [PSCustomObject]@{ parameters = [PSCustomObject]@{ names = '2.0' } }
            $noParams = [PSCustomObject]@{ contextScope = [PSCustomObject]@{ scope = 'array' } }

            Test-PfbEndpointDeclaresContextNames -EndpointEntry $declares | Should -BeTrue
            Test-PfbEndpointDeclaresContextNames -EndpointEntry $lacks    | Should -BeFalse
            Test-PfbEndpointDeclaresContextNames -EndpointEntry $noParams | Should -BeFalse
            Test-PfbEndpointDeclaresContextNames -EndpointEntry $null     | Should -BeFalse
        }
    }
    It 'ignores a resolvable default component -- only the parameters collection is evidence' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            # The exact confusion behind Important 1: a component resolves for this entry, yet
            # the endpoint declares no context_names.
            $lacks = [PSCustomObject]@{ parameters = [PSCustomObject]@{ names = '2.0' } }
            $defaults = [PSCustomObject]@{ context_names = 'Context_names' }
            $component = Resolve-PfbParameterComponent -EndpointEntry $lacks `
                -ParameterName $script:PfbContextParameterName -ParameterComponentDefaults $defaults
            $component | Should -Be 'Context_names'   # a component IS resolved...
            Test-PfbEndpointDeclaresContextNames -EndpointEntry $lacks | Should -BeFalse   # ...and means nothing
        }
    }
}
