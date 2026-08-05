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
}
