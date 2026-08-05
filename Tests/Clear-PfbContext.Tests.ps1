#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    Import-Module "$PSScriptRoot/../PureStorageFlashBladePowerShell.psd1" -Force
}

Describe 'Clear-PfbContext' {
    It 'returns a new connection with no default context, original untouched' {
        $fb = [PSCustomObject]@{
            PSTypeName = 'PureStorage.FlashBlade.Connection'; Endpoint = 'fb.example'
            DefaultContext = ([PSCustomObject]@{ Entries = @([PSCustomObject]@{ Name = 'FB-B'; Kind = 'Array'; Form = 'Object' }); AllowErrors = $null })
            ContextOverride = $null
        }
        $new = Clear-PfbContext -Array $fb
        $new.DefaultContext        | Should -BeNullOrEmpty
        $fb.DefaultContext.Entries | Should -Not -BeNullOrEmpty
    }
}
