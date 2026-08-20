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
        # Save and restore the two lazy caches: the helper nulls both on every call, so
        # merely running this test would otherwise leave them cold, and this test must not
        # decide what state a LATER container inherits.
        $savedCapability = & $module { $script:PfbCapabilityMap }
        $savedVersion = & $module { $script:PfbVersionMap }
        try {
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
        finally {
            # param()-passing, NOT .GetNewClosure(): a closure fails under StrictMode and
            # silently leaks the planted state instead.
            & $module {
                param($capability, $version)
                $script:PfbCapabilityMap = $capability
                $script:PfbVersionMap = $version
            } $savedCapability $savedVersion
        }
    }

    It 'clears both read-only JSON caches even on an ordinary reuse' {
        # The ordinary-reuse case is the one that matters here: nothing about the incoming
        # state hints that these caches need clearing, and they get cleared anyway. This
        # test exists to stop anyone reintroducing CONDITIONAL invalidation as a speed
        # optimisation. A conditional keyed on the incoming $script:PfbModuleRoot was tried
        # and was wrong: a container that is about to redirect the root needs the cache
        # empty, and no inspection of incoming state can predict that. See the long comment
        # in PfbTestModule.ps1 for the exact failure it caused.
        $module = Import-PfbTestModule
        $savedCapability = & $module { $script:PfbCapabilityMap }
        $savedVersion = & $module { $script:PfbVersionMap }
        try {
            & $module {
                $script:PfbCapabilityMap = 'warm-marker'
                $script:PfbVersionMap = 'warm-version-marker'
            }
            $module = Import-PfbTestModule
            (& $module { $script:PfbCapabilityMap }) | Should -BeNullOrEmpty
            (& $module { $script:PfbVersionMap }) | Should -BeNullOrEmpty
        }
        finally {
            & $module {
                param($capability, $version)
                $script:PfbCapabilityMap = $capability
                $script:PfbVersionMap = $version
            } $savedCapability $savedVersion
        }
    }

    It 'clears both caches when a synthetic module root was left behind too' {
        # A special case of the unconditional rule above, kept because it documents the
        # ORIGINAL hazard: a previous container leaves a TestDrive:\ root behind and the
        # caches it warmed are synthetic. The invalidation is not conditional on this --
        # the caches are cleared whatever the incoming root says -- but this combination is
        # the one that would corrupt real data if it ever stopped being covered.
        $module = Import-PfbTestModule
        $savedCapability = & $module { $script:PfbCapabilityMap }
        $savedVersion = & $module { $script:PfbVersionMap }
        try {
            & $module {
                $script:PfbCapabilityMap = 'synthetic-map'
                $script:PfbVersionMap = 'synthetic-version'
                $script:PfbModuleRoot = 'TestDrive:\redirected'
            }
            $module = Import-PfbTestModule
            (& $module { $script:PfbCapabilityMap }) | Should -BeNullOrEmpty
            (& $module { $script:PfbVersionMap }) | Should -BeNullOrEmpty
        }
        finally {
            & $module {
                param($capability, $version)
                $script:PfbCapabilityMap = $capability
                $script:PfbVersionMap = $version
            } $savedCapability $savedVersion
        }
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

    It 'accepts an explicit -ManifestPath and resolves the same already-prepared instance' {
        $null = Import-PfbTestModule
        $before = [int]$global:PfbTestModuleForceCount
        $module = Import-PfbTestModule -ManifestPath $script:manifest
        # Same manifest spelled explicitly must reach the SAME instance, i.e. cost no
        # rebuild -- otherwise a call site that passes -ManifestPath silently pays a
        # full import on every container.
        [int]$global:PfbTestModuleForceCount | Should -Be $before
        $module.Name | Should -Be 'PureStorageFlashBladePowerShell'
        (ConvertTo-PfbTestPathKey $module.ModuleBase) |
            Should -Be (ConvertTo-PfbTestPathKey $script:repoRoot)
    }
}
