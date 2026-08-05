#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    Import-Module "$PSScriptRoot/../PureStorageFlashBladePowerShell.psd1" -Force
}

Describe 'Set-PfbContext' {
    BeforeEach {
        $script:fb = [PSCustomObject]@{
            PSTypeName = 'PureStorage.FlashBlade.Connection'
            Endpoint = 'fb.example'; ApiVersion = '2.26'
            DefaultContext = $null; ContextOverride = $null; AuthorizationModel = $null
        }
    }
    It 'returns a new connection and leaves the original untouched' {
        $new = Set-PfbContext -Array $script:fb -Context 'FB-B'
        $new.DefaultContext.Entries[0].Name | Should -Be 'FB-B'
        $script:fb.DefaultContext           | Should -BeNullOrEmpty
        [object]::ReferenceEquals($new, $script:fb) | Should -BeFalse
    }
    It 'emits exactly ONE connection for N piped members, scoped to the union' {
        $result = @('FB-B', 'FB-C') | Set-PfbContext -Array $script:fb
        @($result).Count                      | Should -Be 1
        @($result.DefaultContext.Entries).Count | Should -Be 2
        $result.DefaultContext.Entries.Name   | Should -Be @('FB-B', 'FB-C')
    }
    It 'binds MemberName by property name, so Get-PfbFleetMember pipes straight in' {
        $piped = @(
            [PSCustomObject]@{ MemberName = 'FB-B' },
            [PSCustomObject]@{ MemberName = 'FB-C' }
        )
        $result = $piped | Set-PfbContext -Array $script:fb
        $result.DefaultContext.Entries.Name | Should -Be @('FB-B', 'FB-C')
    }
    It 'binds Name by property name, for the eventual Get-PfbTopologyGroup contract (#38)' {
        $result = [PSCustomObject]@{ Name = 'region-1' } | Set-PfbContext -Array $script:fb -Kind 'TopologyGroup' -AllArrays
        $result.DefaultContext.Entries[0].Name | Should -Be 'region-1'
        $result.DefaultContext.Entries[0].Form | Should -Be 'AllArrays'
    }
    It 'rejects Array + -AllArrays' {
        { Set-PfbContext -Array $script:fb -Context 'FB-B' -AllArrays } |
            Should -Throw -ExpectedMessage '*an array has no members*'
    }
    It 'rejects TopologyGroup without -AllArrays' {
        { Set-PfbContext -Array $script:fb -Context 'region-1' -Kind 'TopologyGroup' } |
            Should -Throw -ExpectedMessage '*<name>.arrays*'
    }
    It 'throws its own error for a missing -Context rather than prompting' {
        # NOT [Parameter(Mandatory)] + Should -Throw: that hangs on the interactive prompt
        # under -NonInteractive.
        { Set-PfbContext -Array $script:fb } | Should -Throw -ExpectedMessage '*-Context*'
    }
    It 'makes no network call' {
        Mock -CommandName Invoke-PfbApiRequest -ModuleName 'PureStorageFlashBladePowerShell' -MockWith {}
        Mock -CommandName Invoke-RestMethod   -ModuleName 'PureStorageFlashBladePowerShell' -MockWith {}
        Set-PfbContext -Array $script:fb -Context 'no-such-array-at-all' | Out-Null
        Should -Invoke -CommandName Invoke-PfbApiRequest -ModuleName 'PureStorageFlashBladePowerShell' -Times 0
        Should -Invoke -CommandName Invoke-RestMethod   -ModuleName 'PureStorageFlashBladePowerShell' -Times 0
    }
    It 'repoints the module caches at the copy' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $originalArrays = $script:PfbArrays; $originalDefault = $script:PfbDefaultArray
            try {
                $fb = [PSCustomObject]@{ PSTypeName = 'PureStorage.FlashBlade.Connection'; Endpoint = 'fb.example'; DefaultContext = $null; ContextOverride = $null }
                $script:PfbArrays = @{ 'fb.example' = $fb }; $script:PfbDefaultArray = $fb
                $new = Set-PfbContext -Array $fb -Context 'FB-B'
                [object]::ReferenceEquals($script:PfbDefaultArray, $new) | Should -BeTrue
            }
            finally { & { param($a, $d) $script:PfbArrays = $a; $script:PfbDefaultArray = $d } $originalArrays $originalDefault }
        }
    }
}
