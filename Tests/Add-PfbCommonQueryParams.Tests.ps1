#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    Import-Module "$PSScriptRoot/../PureStorageFlashBladePowerShell.psd1" -Force
}

Describe 'Add-PfbCommonQueryParams' {
    Context 'Filter parameter' {
        It 'adds Filter to $Into when present in BoundParameters' {
            InModuleScope PureStorageFlashBladePowerShell -Parameters @{
                Into = @{}
                BoundParameters = @{ Filter = 'name=~foo' }
            } {
                param($Into, $BoundParameters)
                Add-PfbCommonQueryParams -Into $Into -BoundParameters $BoundParameters
                $Into.ContainsKey('filter') | Should -BeTrue
                $Into['filter'] | Should -Be 'name=~foo'
            }
        }

        It 'does not add Filter to $Into when absent from BoundParameters' {
            InModuleScope PureStorageFlashBladePowerShell -Parameters @{
                Into = @{}
                BoundParameters = @{}
            } {
                param($Into, $BoundParameters)
                Add-PfbCommonQueryParams -Into $Into -BoundParameters $BoundParameters
                $Into.ContainsKey('filter') | Should -BeFalse
            }
        }

        It 'adds empty-string Filter when explicitly passed' {
            InModuleScope PureStorageFlashBladePowerShell -Parameters @{
                Into = @{}
                BoundParameters = @{ Filter = '' }
            } {
                param($Into, $BoundParameters)
                Add-PfbCommonQueryParams -Into $Into -BoundParameters $BoundParameters
                $Into.ContainsKey('filter') | Should -BeTrue
                $Into['filter'] | Should -Be ''
            }
        }
    }

    Context 'Sort parameter' {
        It 'adds Sort to $Into when present in BoundParameters' {
            InModuleScope PureStorageFlashBladePowerShell -Parameters @{
                Into = @{}
                BoundParameters = @{ Sort = 'name' }
            } {
                param($Into, $BoundParameters)
                Add-PfbCommonQueryParams -Into $Into -BoundParameters $BoundParameters
                $Into.ContainsKey('sort') | Should -BeTrue
                $Into['sort'] | Should -Be 'name'
            }
        }

        It 'does not add Sort to $Into when absent from BoundParameters' {
            InModuleScope PureStorageFlashBladePowerShell -Parameters @{
                Into = @{}
                BoundParameters = @{}
            } {
                param($Into, $BoundParameters)
                Add-PfbCommonQueryParams -Into $Into -BoundParameters $BoundParameters
                $Into.ContainsKey('sort') | Should -BeFalse
            }
        }
    }

    Context 'Limit parameter' {
        It 'adds Limit to $Into when present in BoundParameters' {
            InModuleScope PureStorageFlashBladePowerShell -Parameters @{
                Into = @{}
                BoundParameters = @{ Limit = 100 }
            } {
                param($Into, $BoundParameters)
                Add-PfbCommonQueryParams -Into $Into -BoundParameters $BoundParameters
                $Into.ContainsKey('limit') | Should -BeTrue
                $Into['limit'] | Should -Be 100
            }
        }

        It 'does not add Limit to $Into when absent from BoundParameters' {
            InModuleScope PureStorageFlashBladePowerShell -Parameters @{
                Into = @{}
                BoundParameters = @{}
            } {
                param($Into, $BoundParameters)
                Add-PfbCommonQueryParams -Into $Into -BoundParameters $BoundParameters
                $Into.ContainsKey('limit') | Should -BeFalse
            }
        }

        It 'adds Limit 0 when explicitly passed (proves ContainsKey semantics, not truthiness)' {
            InModuleScope PureStorageFlashBladePowerShell -Parameters @{
                Into = @{}
                BoundParameters = @{ Limit = 0 }
            } {
                param($Into, $BoundParameters)
                Add-PfbCommonQueryParams -Into $Into -BoundParameters $BoundParameters
                $Into.ContainsKey('limit') | Should -BeTrue
                $Into['limit'] | Should -Be 0
            }
        }
    }

    Context 'TotalOnly parameter' {
        It 'adds total_only = true to $Into when TotalOnly is present in BoundParameters' {
            InModuleScope PureStorageFlashBladePowerShell -Parameters @{
                Into = @{}
                BoundParameters = @{ TotalOnly = $true }
            } {
                param($Into, $BoundParameters)
                Add-PfbCommonQueryParams -Into $Into -BoundParameters $BoundParameters
                $Into.ContainsKey('total_only') | Should -BeTrue
                $Into['total_only'] | Should -Be 'true'
            }
        }

        It 'does not add total_only to $Into when TotalOnly is absent from BoundParameters' {
            InModuleScope PureStorageFlashBladePowerShell -Parameters @{
                Into = @{}
                BoundParameters = @{}
            } {
                param($Into, $BoundParameters)
                Add-PfbCommonQueryParams -Into $Into -BoundParameters $BoundParameters
                $Into.ContainsKey('total_only') | Should -BeFalse
            }
        }
    }

    Context 'Names parameter' {
        It 'adds names joined by comma when Names are provided' {
            InModuleScope PureStorageFlashBladePowerShell -Parameters @{
                Into = @{}
                BoundParameters = @{}
                Names = @('fs1', 'fs2', 'fs3')
            } {
                param($Into, $BoundParameters, $Names)
                Add-PfbCommonQueryParams -Into $Into -BoundParameters $BoundParameters -Names $Names
                $Into.ContainsKey('names') | Should -BeTrue
                $Into['names'] | Should -Be 'fs1,fs2,fs3'
            }
        }

        It 'does not add names when Names are not provided' {
            InModuleScope PureStorageFlashBladePowerShell -Parameters @{
                Into = @{}
                BoundParameters = @{}
            } {
                param($Into, $BoundParameters)
                Add-PfbCommonQueryParams -Into $Into -BoundParameters $BoundParameters
                $Into.ContainsKey('names') | Should -BeFalse
            }
        }

        It 'does not add names when Names is an empty array' {
            InModuleScope PureStorageFlashBladePowerShell -Parameters @{
                Into = @{}
                BoundParameters = @{}
                Names = @()
            } {
                param($Into, $BoundParameters, $Names)
                Add-PfbCommonQueryParams -Into $Into -BoundParameters $BoundParameters -Names $Names
                $Into.ContainsKey('names') | Should -BeFalse
            }
        }

        It 'adds single Name when only one is provided' {
            InModuleScope PureStorageFlashBladePowerShell -Parameters @{
                Into = @{}
                BoundParameters = @{}
                Names = @('fs1')
            } {
                param($Into, $BoundParameters, $Names)
                Add-PfbCommonQueryParams -Into $Into -BoundParameters $BoundParameters -Names $Names
                $Into.ContainsKey('names') | Should -BeTrue
                $Into['names'] | Should -Be 'fs1'
            }
        }
    }

    Context 'Ids parameter' {
        It 'adds ids joined by comma when Ids are provided' {
            InModuleScope PureStorageFlashBladePowerShell -Parameters @{
                Into = @{}
                BoundParameters = @{}
                Ids = @('id1', 'id2', 'id3')
            } {
                param($Into, $BoundParameters, $Ids)
                Add-PfbCommonQueryParams -Into $Into -BoundParameters $BoundParameters -Ids $Ids
                $Into.ContainsKey('ids') | Should -BeTrue
                $Into['ids'] | Should -Be 'id1,id2,id3'
            }
        }

        It 'does not add ids when Ids are not provided' {
            InModuleScope PureStorageFlashBladePowerShell -Parameters @{
                Into = @{}
                BoundParameters = @{}
            } {
                param($Into, $BoundParameters)
                Add-PfbCommonQueryParams -Into $Into -BoundParameters $BoundParameters
                $Into.ContainsKey('ids') | Should -BeFalse
            }
        }

        It 'does not add ids when Ids is an empty array' {
            InModuleScope PureStorageFlashBladePowerShell -Parameters @{
                Into = @{}
                BoundParameters = @{}
                Ids = @()
            } {
                param($Into, $BoundParameters, $Ids)
                Add-PfbCommonQueryParams -Into $Into -BoundParameters $BoundParameters -Ids $Ids
                $Into.ContainsKey('ids') | Should -BeFalse
            }
        }

        It 'adds single Id when only one is provided' {
            InModuleScope PureStorageFlashBladePowerShell -Parameters @{
                Into = @{}
                BoundParameters = @{}
                Ids = @('id1')
            } {
                param($Into, $BoundParameters, $Ids)
                Add-PfbCommonQueryParams -Into $Into -BoundParameters $BoundParameters -Ids $Ids
                $Into.ContainsKey('ids') | Should -BeTrue
                $Into['ids'] | Should -Be 'id1'
            }
        }
    }

    Context 'Names and Ids independence' {
        It 'adds only Names when only Names are provided' {
            InModuleScope PureStorageFlashBladePowerShell -Parameters @{
                Into = @{}
                BoundParameters = @{}
                Names = @('fs1', 'fs2')
            } {
                param($Into, $BoundParameters, $Names)
                Add-PfbCommonQueryParams -Into $Into -BoundParameters $BoundParameters -Names $Names
                $Into.ContainsKey('names') | Should -BeTrue
                $Into['names'] | Should -Be 'fs1,fs2'
                $Into.ContainsKey('ids') | Should -BeFalse
            }
        }

        It 'adds only Ids when only Ids are provided' {
            InModuleScope PureStorageFlashBladePowerShell -Parameters @{
                Into = @{}
                BoundParameters = @{}
                Ids = @('id1', 'id2')
            } {
                param($Into, $BoundParameters, $Ids)
                Add-PfbCommonQueryParams -Into $Into -BoundParameters $BoundParameters -Ids $Ids
                $Into.ContainsKey('ids') | Should -BeTrue
                $Into['ids'] | Should -Be 'id1,id2'
                $Into.ContainsKey('names') | Should -BeFalse
            }
        }

        It 'adds both Names and Ids when both are provided' {
            InModuleScope PureStorageFlashBladePowerShell -Parameters @{
                Into = @{}
                BoundParameters = @{}
                Names = @('fs1', 'fs2')
                Ids = @('id1', 'id2')
            } {
                param($Into, $BoundParameters, $Names, $Ids)
                Add-PfbCommonQueryParams -Into $Into -BoundParameters $BoundParameters -Names $Names -Ids $Ids
                $Into.ContainsKey('names') | Should -BeTrue
                $Into['names'] | Should -Be 'fs1,fs2'
                $Into.ContainsKey('ids') | Should -BeTrue
                $Into['ids'] | Should -Be 'id1,id2'
            }
        }
    }

    Context 'In-place mutation' {
        It 'mutates the $Into hashtable in place' {
            InModuleScope PureStorageFlashBladePowerShell -Parameters @{
                Into = @{ existing_key = 'existing_value' }
                BoundParameters = @{ Filter = 'test'; Limit = 50 }
                Names = @('name1')
            } {
                param($Into, $BoundParameters, $Names)
                Add-PfbCommonQueryParams -Into $Into -BoundParameters $BoundParameters -Names $Names
                # Verify original key is still there
                $Into['existing_key'] | Should -Be 'existing_value'
                # Verify new keys were added
                $Into['filter'] | Should -Be 'test'
                $Into['limit'] | Should -Be 50
                $Into['names'] | Should -Be 'name1'
            }
        }

        It 'function returns nothing (hashtable is mutated, not returned)' {
            InModuleScope PureStorageFlashBladePowerShell -Parameters @{
                Into = @{}
                BoundParameters = @{ Filter = 'test' }
            } {
                param($Into, $BoundParameters)
                $result = Add-PfbCommonQueryParams -Into $Into -BoundParameters $BoundParameters
                $result | Should -BeNullOrEmpty
            }
        }
    }

    Context 'All parameters together' {
        It 'handles all four scalar parameters and both array parameters in one call' {
            InModuleScope PureStorageFlashBladePowerShell -Parameters @{
                Into = @{}
                BoundParameters = @{ Filter = 'name=test'; Sort = 'name'; Limit = 25; TotalOnly = $true }
                Names = @('fs1', 'fs2')
                Ids = @('id1')
            } {
                param($Into, $BoundParameters, $Names, $Ids)
                Add-PfbCommonQueryParams -Into $Into -BoundParameters $BoundParameters -Names $Names -Ids $Ids
                $Into['filter'] | Should -Be 'name=test'
                $Into['sort'] | Should -Be 'name'
                $Into['limit'] | Should -Be 25
                $Into['total_only'] | Should -Be 'true'
                $Into['names'] | Should -Be 'fs1,fs2'
                $Into['ids'] | Should -Be 'id1'
            }
        }
    }
}
