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
                Should -Throw
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
                    Should -Throw
            }
        }
    }
}
