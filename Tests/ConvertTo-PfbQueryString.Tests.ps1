#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule
}

Describe 'ConvertTo-PfbQueryString' {
    Context 'Boolean values' {
        It 'serializes $true as lowercase true, not True' {
            InModuleScope PureStorageFlashBladePowerShell {
                $result = ConvertTo-PfbQueryString -Parameters @{ enabled = $true }
                $result | Should -Be '?enabled=true'
            }
        }

        It 'serializes $false as lowercase false, not False' {
            InModuleScope PureStorageFlashBladePowerShell {
                $result = ConvertTo-PfbQueryString -Parameters @{ enabled = $false }
                $result | Should -Be '?enabled=false'
            }
        }
    }

    Context 'Array values' {
        It 'joins array values with commas' {
            InModuleScope PureStorageFlashBladePowerShell {
                $result = ConvertTo-PfbQueryString -Parameters @{ names = @('a', 'b', 'c') }
                $result | Should -Be '?names=a%2Cb%2Cc'
            }
        }
    }

    Context 'Scalar values' {
        It 'passes through string values unchanged' {
            InModuleScope PureStorageFlashBladePowerShell {
                $result = ConvertTo-PfbQueryString -Parameters @{ name = 'foo' }
                $result | Should -Be '?name=foo'
            }
        }

        It 'passes through integer values unchanged' {
            InModuleScope PureStorageFlashBladePowerShell {
                $result = ConvertTo-PfbQueryString -Parameters @{ limit = 0 }
                $result | Should -Be '?limit=0'
            }
        }
    }

    Context 'Null and empty handling' {
        It 'returns an empty string for null or empty parameters' {
            InModuleScope PureStorageFlashBladePowerShell {
                ConvertTo-PfbQueryString -Parameters @{} | Should -Be ''
                ConvertTo-PfbQueryString -Parameters $null | Should -Be ''
            }
        }

        It 'skips null and empty-string values but keeps other keys' {
            InModuleScope PureStorageFlashBladePowerShell {
                $result = ConvertTo-PfbQueryString -Parameters @{ a = $null; b = ''; c = 'x' }
                $result | Should -Be '?c=x'
            }
        }
    }
}
