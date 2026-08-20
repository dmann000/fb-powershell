#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule
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
            # Measured: Set-StrictMode in the It's own scope does NOT cross into the module's
            # session state -- with it set only there, deleting the $null clause from
            # Private/Test-PfbEmptyPipelineRead.ps1 leaves all four tests green on both editions.
            # It has to be set HERE, inside InModuleScope, to reach the callee.
            Set-StrictMode -Version Latest
            function Invoke-PredicateFixture {
                [CmdletBinding()]
                param([Parameter(ValueFromPipeline)][string]$Name)
                end { Test-PfbEmptyPipelineRead -Caller $PSCmdlet -QueryParams $null }
            }

            @() | Invoke-PredicateFixture | Should -BeTrue
        }
    }

    It 'keys off ExpectingInput: one fixture, one empty query, opposite answers' {
        # The ExpectingInput half rested on a single direct-invocation case. This holds the
        # fixture and the final query identical and varies only the invocation form, so
        # deleting the ExpectingInput short-circuit flips the direct half and reds this test.
        InModuleScope PureStorageFlashBladePowerShell {
            function Invoke-PredicateFixture {
                [CmdletBinding()]
                param([Parameter(ValueFromPipeline)][string]$Name)
                begin { $queryParams = @{} }
                process { if ($Name) { $queryParams['names'] = $Name } }
                end { Test-PfbEmptyPipelineRead -Caller $PSCmdlet -QueryParams $queryParams }
            }

            Invoke-PredicateFixture | Should -BeFalse
            @() | Invoke-PredicateFixture | Should -BeTrue
        }
    }
}
