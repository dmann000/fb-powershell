#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    Import-Module "$PSScriptRoot/../PureStorageFlashBladePowerShell.psd1" -Force
}

Describe 'Invoke-PfbInContext' {
    BeforeEach {
        $script:fb = [PSCustomObject]@{
            PSTypeName = 'PureStorage.FlashBlade.Connection'; Endpoint = 'fb.example'
            DefaultContext = $null; ContextOverride = $null
        }
    }
    It 'restores the override to UNSET after the block' {
        # $null -eq, never -BeNullOrEmpty: a buggy restore that assigned @() instead of $null
        # would satisfy -BeNullOrEmpty, and @() is a DIFFERENT documented state (the
        # run-locally escape hatch asserted further down). The whole point of this Describe is
        # that those two are distinguishable, so its assertions must be able to tell them apart.
        Invoke-PfbInContext -Array $script:fb -Context 'FB-B' -ScriptBlock { $null }
        $null -eq $script:fb.ContextOverride | Should -BeTrue
    }
    It 'exposes the override to the block' {
        $captured = Invoke-PfbInContext -Array $script:fb -Context 'FB-B' -ScriptBlock { $script:fb.ContextOverride.Entries[0].Name }
        $captured | Should -Be 'FB-B'
    }
    It 'restores the override when the scriptblock throws partway through' {
        { Invoke-PfbInContext -Array $script:fb -Context 'FB-B' -ScriptBlock { throw 'boom' } } | Should -Throw 'boom'
        $null -eq $script:fb.ContextOverride | Should -BeTrue   # unset, NOT @()
    }
    It 'nests: the inner block restores the OUTER value, not null' {
        Invoke-PfbInContext -Array $script:fb -Context 'outer' -ScriptBlock {
            Invoke-PfbInContext -Array $script:fb -Context 'inner' -ScriptBlock {
                $script:fb.ContextOverride.Entries[0].Name | Should -Be 'inner'
            }
            $script:fb.ContextOverride.Entries[0].Name | Should -Be 'outer'
        }
        $null -eq $script:fb.ContextOverride | Should -BeTrue   # unset, NOT @()
    }
    It 'nests safely when the INNER block throws' {
        {
            Invoke-PfbInContext -Array $script:fb -Context 'outer' -ScriptBlock {
                Invoke-PfbInContext -Array $script:fb -Context 'inner' -ScriptBlock { throw 'inner boom' }
            }
        } | Should -Throw 'inner boom'
        $null -eq $script:fb.ContextOverride | Should -BeTrue   # unset, NOT @()
    }
    It 'accepts an empty collection as the explicit run-locally escape hatch' {
        $captured = Invoke-PfbInContext -Array $script:fb -Context @() -ScriptBlock { $script:fb.ContextOverride }
        @($captured.Entries).Count | Should -Be 0
        $null -ne $captured        | Should -BeTrue   # empty != unset: a context object EXISTS
    }
    It 'throws its own errors for missing arguments rather than prompting' {
        { Invoke-PfbInContext -Array $script:fb -Context 'FB-B' } | Should -Throw -ExpectedMessage '*-ScriptBlock*'
        { Invoke-PfbInContext -Context 'FB-B' -ScriptBlock {} }   | Should -Throw -ExpectedMessage '*-Array*'
    }
}
