#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
    These tests drive the helper directly, including the paths no call site uses
    (-Fresh, shim detection). They are the only coverage -Fresh has.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:manifest = Join-Path $script:repoRoot 'PureStorageFlashBladePowerShell.psd1'
}

Describe 'Import-PfbTestModule' {
    It 'returns the live module and marks it prepared' {
        $module = Import-PfbTestModule
        $module | Should -Not -BeNullOrEmpty
        $module.Name | Should -Be 'PureStorageFlashBladePowerShell'
        (& $module { $script:PfbTestModulePrepared }) | Should -BeTrue
    }

    It 'does not rebuild an already prepared instance' {
        $first = Import-PfbTestModule
        & $first { $script:PfbTestModuleWitness = 'kept' }
        $before = [int]$global:PfbTestModuleForceCount
        $second = Import-PfbTestModule
        [int]$global:PfbTestModuleForceCount | Should -Be $before
        (& $second { $script:PfbTestModuleWitness }) | Should -Be 'kept'
    }

    It 'increments the call counter on every call' {
        $before = [int]$global:PfbTestModuleCallCount
        $null = Import-PfbTestModule
        [int]$global:PfbTestModuleCallCount | Should -Be ($before + 1)
    }

    It 'resets the connection state, the credential cache and the module root on every call' {
        $module = Import-PfbTestModule
        & $module {
            $script:PfbDefaultArray = 'dirty'
            $script:PfbArrays = @{ leaked = $true }
            $script:PfbCachedCredential = 'leaked-credential'
            $script:PfbModuleRoot = 'TestDrive:\nonexistent'
        }
        $module = Import-PfbTestModule
        (& $module { $script:PfbDefaultArray }) | Should -BeNullOrEmpty
        (& $module { $script:PfbArrays.Count }) | Should -Be 0
        (& $module { $script:PfbCachedCredential }) | Should -BeNullOrEmpty
        (& $module { $script:PfbModuleRoot }) | Should -Be $module.ModuleBase
    }

    It 'leaves the read-only JSON caches warm' {
        $module = Import-PfbTestModule
        & $module { $script:PfbCapabilityMap = 'warm-marker' }
        $module = Import-PfbTestModule
        (& $module { $script:PfbCapabilityMap }) | Should -Be 'warm-marker'
    }

    It '-Fresh rebuilds and deliberately does NOT mark the instance prepared' {
        $null = Import-PfbTestModule
        $before = [int]$global:PfbTestModuleForceCount
        $fresh = Import-PfbTestModule -Fresh
        [int]$global:PfbTestModuleForceCount | Should -Be ($before + 1)
        (& $fresh { $script:PfbTestModulePrepared }) | Should -BeNullOrEmpty
    }

    It 'force-reimports after an unmarked instance is installed by something else' {
        $null = Import-PfbTestModule
        $null = Import-Module -Name $script:manifest -Force -PassThru
        $before = [int]$global:PfbTestModuleForceCount
        $module = Import-PfbTestModule
        [int]$global:PfbTestModuleForceCount | Should -Be ($before + 1)
        (& $module { $script:PfbTestModulePrepared }) | Should -BeTrue
    }

    It 'force-reimports when a selector-probe shim is present in module scope' {
        $module = Import-PfbTestModule
        & $module {
            Set-Item -Path 'function:script:Invoke-PfbApiRequest' -Value {
                $null = 'PfbSelectorProbeCapture'
            }
        }
        $before = [int]$global:PfbTestModuleForceCount
        $module = Import-PfbTestModule
        [int]$global:PfbTestModuleForceCount | Should -Be ($before + 1)
        (& $module { (Get-Command Invoke-PfbApiRequest).Definition }) |
            Should -Not -Match 'PfbSelectorProbeCapture'
    }
}
