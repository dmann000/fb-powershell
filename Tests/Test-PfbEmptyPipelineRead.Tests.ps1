#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) `
            'PureStorageFlashBladePowerShell.psd1') -Force
}

Describe 'Test-PfbEmptyPipelineRead' {
    It 'returns true for a piped invocation whose final query is empty' {
        InModuleScope PureStorageFlashBladePowerShell {
            function Invoke-PredicateFixture {
                [CmdletBinding()]
                param([Parameter(ValueFromPipeline)][string]$Name)
                begin { $queryParams = @{} }
                process { if ($Name) { $queryParams['names'] = $Name } }
                end { Test-PfbEmptyPipelineRead -Caller $PSCmdlet -QueryParams $queryParams }
            }

            @() | Invoke-PredicateFixture | Should -BeTrue
        }
    }

    It 'returns false for a direct invocation whose final query is empty' {
        InModuleScope PureStorageFlashBladePowerShell {
            function Invoke-PredicateFixture {
                [CmdletBinding()]
                param([Parameter(ValueFromPipeline)][string]$Name)
                end { Test-PfbEmptyPipelineRead -Caller $PSCmdlet -QueryParams @{} }
            }

            Invoke-PredicateFixture | Should -BeFalse
        }
    }

    It 'returns false when a piped invocation has a surviving final query key' {
        InModuleScope PureStorageFlashBladePowerShell {
            function Invoke-PredicateFixture {
                [CmdletBinding()]
                param([Parameter(ValueFromPipeline)][string]$Name)
                end {
                    Test-PfbEmptyPipelineRead -Caller $PSCmdlet `
                        -QueryParams @{ filter = "name='kept'" }
                }
            }

            @() | Invoke-PredicateFixture | Should -BeFalse
        }
    }

    It 'treats a null query hashtable as empty without throwing under StrictMode' {
        InModuleScope PureStorageFlashBladePowerShell {
            function Invoke-PredicateFixture {
                [CmdletBinding()]
                param([Parameter(ValueFromPipeline)][string]$Name)
                end { Test-PfbEmptyPipelineRead -Caller $PSCmdlet -QueryParams $null }
            }

            @() | Invoke-PredicateFixture | Should -BeTrue
        }
    }
}