#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    Import-Module "$PSScriptRoot/../PureStorageFlashBladePowerShell.psd1" -Force
}

# InModuleScope goes INSIDE each It, never around the Describe body: Describe-level
# InModuleScope fails at discovery in this repo, and every passing test on this branch
# already uses the It-level form. The fixtures have to be built inside it too --
# New-PfbContext / New-PfbContextEntry / Resolve-PfbRequestContext are all private and
# do not exist outside module scope.
#
# Fixtures are plain locals ($fb), NOT $script: -- inside InModuleScope a $script:
# assignment writes to the MODULE's script scope, which is leaked module state that
# outlives the test file. Locals cost three lines of repetition per It and leak nothing.
Describe 'Resolve-PfbRequestContext' {
    It 'returns $null when nothing is set' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $fb = [PSCustomObject]@{ Endpoint = 'fb.example'; DefaultContext = $null; ContextOverride = $null }
            $null -eq (Resolve-PfbRequestContext -Array $fb -QueryParams $null) | Should -BeTrue
        }
    }
    It 'uses DefaultContext when only it is set' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $fb = [PSCustomObject]@{ Endpoint = 'fb.example'; DefaultContext = $null; ContextOverride = $null }
            $fb.DefaultContext = New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-B'))
            (Resolve-PfbRequestContext -Array $fb -QueryParams $null).Entries[0].Name | Should -Be 'FB-B'
        }
    }
    It 'prefers ContextOverride over DefaultContext' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $fb = [PSCustomObject]@{ Endpoint = 'fb.example'; DefaultContext = $null; ContextOverride = $null }
            $fb.DefaultContext  = New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-B'))
            $fb.ContextOverride = New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-C'))
            (Resolve-PfbRequestContext -Array $fb -QueryParams $null).Entries[0].Name | Should -Be 'FB-C'
        }
    }
    It 'prefers an explicit QueryParams context_names over both' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $fb = [PSCustomObject]@{ Endpoint = 'fb.example'; DefaultContext = $null; ContextOverride = $null }
            $fb.DefaultContext  = New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-B'))
            $fb.ContextOverride = New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-C'))
            $resolved = Resolve-PfbRequestContext -Array $fb -QueryParams @{ context_names = 'FB-D' }
            $resolved.Entries[0].Name | Should -Be 'FB-D'
        }
    }
    It 'distinguishes an explicit EMPTY override from unset' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $fb = [PSCustomObject]@{ Endpoint = 'fb.example'; DefaultContext = $null; ContextOverride = $null }
            $fb.DefaultContext  = New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-B'))
            $fb.ContextOverride = New-PfbContext -Entries @()
            $resolved = Resolve-PfbRequestContext -Array $fb -QueryParams $null
            $null -ne $resolved        | Should -BeTrue   # a context object EXISTS...
            @($resolved.Entries).Count | Should -Be 0     # ...it just carries no entries
        }
    }
    It 'does not treat an empty override as falsy and fall through to the default' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            # The whole point of the tri-state: a truthiness check here would silently
            # reinstate the session default and send the call to the wrong array.
            $fb = [PSCustomObject]@{ Endpoint = 'fb.example'; DefaultContext = $null; ContextOverride = $null }
            $fb.DefaultContext  = New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-B'))
            $fb.ContextOverride = New-PfbContext -Entries @()
            @((Resolve-PfbRequestContext -Array $fb -QueryParams $null).Entries).Count |
                Should -Be 0   # count, not -BeNullOrEmpty: proves empty rather than merely falsy
        }
    }
    It 'checks ContextOverride against $null rather than truthiness' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $fb = [PSCustomObject]@{ Endpoint = 'fb.example'; DefaultContext = $null; ContextOverride = $null }
            $fb.DefaultContext = New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-B'))
            # A deliberately FALSY-but-present override. A PfbContext is a PSCustomObject and so
            # is always truthy, which is why the empty-Entries fixtures above cannot express this;
            # a bare @() is $false in a boolean context but is NOT $null.
            #   under `$null -ne`  : the override wins. Returning a bare @() emits nothing, so the
            #                        call lands as $null -- and FB-B never appears.
            #   under truthiness   : the override is skipped and the FB-B DefaultContext comes back.
            # "Did FB-B leak through" is therefore the mutation detector.
            $fb.ContextOverride = @()
            $resolved = Resolve-PfbRequestContext -Array $fb -QueryParams $null
            $null -eq $resolved | Should -BeTrue
        }
    }
    It 'treats an explicit EMPTY QueryParams context_names as no-context, not unset' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $fb = [PSCustomObject]@{ Endpoint = 'fb.example'; DefaultContext = $null; ContextOverride = $null }
            $fb.DefaultContext = New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-B'))
            $resolved = Resolve-PfbRequestContext -Array $fb -QueryParams @{ context_names = @() }
            $null -ne $resolved        | Should -BeTrue   # explicit, so it does NOT fall through
            @($resolved.Entries).Count | Should -Be 0
        }
    }
}
