#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Update-PfbObjectStoreRole - typed body parameters (#31)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'typed parameters build the body' {
        It 'builds account as a name-reference object (constraint 8a, scalar reference)' {
            Update-PfbObjectStoreRole -Name 's3-admin-role' -Account 'obj-account-1' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Endpoint -eq 'object-store-roles' -and
                $QueryParams['names'] -eq 's3-admin-role' -and
                $Body['account'].name -eq 'obj-account-1'
            }
        }

        It 'sends an explicit -MaxSessionDuration 0 rather than dropping it (constraint 2, integer field)' {
            Update-PfbObjectStoreRole -Name 's3-admin-role' -MaxSessionDuration 0 `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('max_session_duration') -and $Body['max_session_duration'] -eq 0
            }
        }

        It 'sends max_session_duration when supplied a non-zero value' {
            Update-PfbObjectStoreRole -Name 's3-admin-role' -MaxSessionDuration 3600000 `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['max_session_duration'] -eq 3600000
            }
        }

        It 'omits max_session_duration entirely when not supplied' {
            Update-PfbObjectStoreRole -Name 's3-admin-role' -Account 'obj-account-1' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                -not $Body.ContainsKey('max_session_duration')
            }
        }

        It 'omits every body key when no typed body parameter is supplied' {
            Update-PfbObjectStoreRole -Name 's3-admin-role' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.Count -eq 0
            }
        }

        It 'targets the role by id when -Id is used' {
            Update-PfbObjectStoreRole -Id 'role-id-1' -MaxSessionDuration 3600000 `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['ids'] -eq 'role-id-1' -and -not $QueryParams.ContainsKey('names')
            }
        }
    }

    Context '-Attributes remains supported and is mutually exclusive' {
        It 'still sends a raw -Attributes body' {
            Update-PfbObjectStoreRole -Name 's3-admin-role' -Attributes @{ max_session_duration = 7200000 } `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['max_session_duration'] -eq 7200000
            }
        }

        It 'rejects -Attributes combined with a typed parameter at bind time' {
            { Update-PfbObjectStoreRole -Name 's3-admin-role' -MaxSessionDuration 3600000 -Attributes @{ max_session_duration = 7200000 } `
                -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'
        }
    }

    Context 'deprecated / read-only fields are not exposed (constraint 9 and 11)' {
        It 'has no -Created/-Prn/-TrustedEntities parameter' {
            $keys = (Get-Command Update-PfbObjectStoreRole).Parameters.Keys
            foreach ($p in 'Created', 'Prn', 'TrustedEntities') {
                $keys | Should -Not -Contain $p
            }
        }
    }

    Context 'constraint compliance' {
        It 'puts no ValidateSet on -<Parameter> (constraint 3, no spec enum)' -ForEach @(
            @{ Parameter = 'Account' }
            @{ Parameter = 'MaxSessionDuration' }
        ) {
            $attrs = (Get-Command Update-PfbObjectStoreRole).Parameters[$Parameter].Attributes
            @($attrs | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).Count |
                Should -Be 0
        }

        It 'exposes every settable body field the endpoint accepts' {
            $keys = (Get-Command Update-PfbObjectStoreRole).Parameters.Keys
            foreach ($p in 'Account','MaxSessionDuration') {
                $keys | Should -Contain $p
            }
        }
    }
}
