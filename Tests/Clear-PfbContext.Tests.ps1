#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule
}

Describe 'Clear-PfbContext' {
    It 'returns a new connection with no default context, original untouched' {
        $fb = [PSCustomObject]@{
            PSTypeName = 'PureStorage.FlashBlade.Connection'; Endpoint = 'fb.example'
            DefaultContext = ([PSCustomObject]@{ Entries = @([PSCustomObject]@{ Name = 'FB-B'; Kind = 'Array'; Form = 'Object' }); AllowErrors = $null })
            ContextOverride = $null
        }
        $new = Clear-PfbContext -Array $fb
        # -BeNullOrEmpty cannot tell $null (unset) from @() (explicit no-context), and @() has
        # a DIFFERENT documented meaning at the Invoke-PfbInContext layer -- so a change making
        # this cmdlet emit @() must red. Test the reference directly.
        $null -eq $new.DefaultContext | Should -BeTrue
        # The original connection's entries must be undisturbed -- assert the count AND the
        # identity of the entry, since a count alone would survive the list being rebuilt.
        @($fb.DefaultContext.Entries).Count | Should -Be 1
        $fb.DefaultContext.Entries[0].Name  | Should -Be 'FB-B'
    }

    It 'repoints the module caches at the copy' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $originalArrays = $script:PfbArrays; $originalDefault = $script:PfbDefaultArray
            try {
                $fb = [PSCustomObject]@{
                    PSTypeName = 'PureStorage.FlashBlade.Connection'; Endpoint = 'fb.example'
                    DefaultContext = (New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-B')))
                    ContextOverride = $null
                }
                $script:PfbArrays = @{ 'fb.example' = $fb }; $script:PfbDefaultArray = $fb
                $new = Clear-PfbContext -Array $fb
                [object]::ReferenceEquals($script:PfbDefaultArray, $new) | Should -BeTrue
                [object]::ReferenceEquals($script:PfbArrays['fb.example'], $new) | Should -BeTrue
            }
            finally { & { param($a, $d) $script:PfbArrays = $a; $script:PfbDefaultArray = $d } $originalArrays $originalDefault }
        }
    }
}
