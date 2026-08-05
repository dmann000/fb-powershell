#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    Import-Module "$PSScriptRoot/../PureStorageFlashBladePowerShell.psd1" -Force
}

Describe 'PfbContext object' {
    Context 'wire composition' {
        It 'renders a bare name for Array/Object' {
            InModuleScope PureStorageFlashBladePowerShell {
                $e = New-PfbContextEntry -Name 'FB-B' -Kind 'Array' -Form 'Object'
                ConvertTo-PfbContextWireValue -Entry $e | Should -Be 'FB-B'
            }
        }
        It 'renders a bare name for Fleet/Object' {
            InModuleScope PureStorageFlashBladePowerShell {
                $e = New-PfbContextEntry -Name 'cc-test-fleet' -Kind 'Fleet' -Form 'Object'
                ConvertTo-PfbContextWireValue -Entry $e | Should -Be 'cc-test-fleet'
            }
        }
        It 'appends .arrays for Fleet/AllArrays' {
            InModuleScope PureStorageFlashBladePowerShell {
                $e = New-PfbContextEntry -Name 'cc-test-fleet' -Kind 'Fleet' -Form 'AllArrays'
                ConvertTo-PfbContextWireValue -Entry $e | Should -Be 'cc-test-fleet.arrays'
            }
        }
        It 'appends .arrays for TopologyGroup/AllArrays' {
            InModuleScope PureStorageFlashBladePowerShell {
                $e = New-PfbContextEntry -Name 'region-1' -Kind 'TopologyGroup' -Form 'AllArrays'
                ConvertTo-PfbContextWireValue -Entry $e | Should -Be 'region-1.arrays'
            }
        }
        It 'uses a lower-case .arrays suffix, which is case-sensitive on the wire' {
            InModuleScope PureStorageFlashBladePowerShell {
                $e = New-PfbContextEntry -Name 'x' -Kind 'Fleet' -Form 'AllArrays'
                ConvertTo-PfbContextWireValue -Entry $e | Should -MatchExactly '\.arrays$'
            }
        }
    }
    Context 'invalid compositions' {
        It 'rejects Array + AllArrays because an array has no members' {
            InModuleScope PureStorageFlashBladePowerShell {
                $e = New-PfbContextEntry -Name 'FB-B' -Kind 'Array' -Form 'AllArrays'
                { Assert-PfbContextEntryComposition -Entry $e } | Should -Throw -ExpectedMessage '*an array has no members*'
            }
        }
        It 'rejects TopologyGroup + Object because no endpoint accepts a bare group name' {
            InModuleScope PureStorageFlashBladePowerShell {
                $e = New-PfbContextEntry -Name 'region-1' -Kind 'TopologyGroup' -Form 'Object'
                { Assert-PfbContextEntryComposition -Entry $e } | Should -Throw -ExpectedMessage '*<name>.arrays*'
            }
        }
        It 'accepts every valid pair' {
            InModuleScope PureStorageFlashBladePowerShell {
                foreach ($pair in @(@('Array','Object'), @('Fleet','Object'), @('Fleet','AllArrays'), @('TopologyGroup','AllArrays'))) {
                    $e = New-PfbContextEntry -Name 'n' -Kind $pair[0] -Form $pair[1]
                    { Assert-PfbContextEntryComposition -Entry $e } | Should -Not -Throw
                }
            }
        }
    }
    Context 'defaults and shape' {
        It 'defaults Kind to Array and Form to Object' {
            InModuleScope PureStorageFlashBladePowerShell {
                $e = New-PfbContextEntry -Name 'FB-B'
                $e.Kind | Should -Be 'Array'
                $e.Form | Should -Be 'Object'
            }
        }
        It 'keeps Kind per-entry, not one scalar for the context' {
            InModuleScope PureStorageFlashBladePowerShell {
                $c = New-PfbContext -Entries @(
                    (New-PfbContextEntry -Name 'FB-B' -Kind 'Array'),
                    (New-PfbContextEntry -Name 'f' -Kind 'Fleet')
                )
                @($c.Entries).Count | Should -Be 2
                $c.Entries[0].Kind   | Should -Be 'Array'
                $c.Entries[1].Kind   | Should -Be 'Fleet'
            }
        }
        It 'reserves AllowErrors as tri-state, defaulting to null (Phase 2 surfaces it)' {
            InModuleScope PureStorageFlashBladePowerShell {
                (New-PfbContext -Entries @((New-PfbContextEntry -Name 'x'))).AllowErrors | Should -BeNullOrEmpty
            }
        }
        It 'normalises a string[] into entries of one kind' {
            InModuleScope PureStorageFlashBladePowerShell {
                $entries = ConvertTo-PfbContextEntryList -Name @('FB-B','FB-C') -Kind 'Array' -Form 'Object'
                @($entries).Count            | Should -Be 2
                $entries[1].Name             | Should -Be 'FB-C'
            }
        }
    }
}
