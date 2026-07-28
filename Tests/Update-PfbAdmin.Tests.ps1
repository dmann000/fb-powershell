#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Update-PfbAdmin - typed body parameters (#31)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'typed parameters build the body' {
        It 'sends password and public_key as body fields' {
            Update-PfbAdmin -Name 'ops' -Password 'N3wP@ss!' -PublicKey 'ssh-rsa AAAA' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Endpoint -eq 'admins' -and
                $QueryParams['names'] -eq 'ops' -and
                $Body['password'] -eq 'N3wP@ss!' -and
                $Body['public_key'] -eq 'ssh-rsa AAAA'
            }
        }

        It 'sends authorization_model and old_password as body fields' {
            Update-PfbAdmin -Name 'ops' -AuthorizationModel 'static' -OldPassword '0ld!' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['authorization_model'] -eq 'static' -and
                $Body['old_password'] -eq '0ld!'
            }
        }

        It 'sends an explicit -Locked:$false (ContainsKey semantics, not truthiness)' {
            Update-PfbAdmin -Name 'ops' -Locked $false -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('locked') -and $Body['locked'] -eq $false
            }
        }

        It 'omits locked entirely when -Locked is not supplied' {
            Update-PfbAdmin -Name 'ops' -Password 'x' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                -not $Body.ContainsKey('locked')
            }
        }

        It 'builds management_access_policies as name-reference objects' {
            Update-PfbAdmin -Name 'ops' -ManagementAccessPolicies 'pol-a','pol-b' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['management_access_policies'].Count -eq 2 -and
                $Body['management_access_policies'][0].name -eq 'pol-a' -and
                $Body['management_access_policies'][1].name -eq 'pol-b'
            }
        }

        It 'sends an EMPTY array for -ManagementAccessPolicies @() so a list can be cleared' {
            Update-PfbAdmin -Name 'ops' -ManagementAccessPolicies @() -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('management_access_policies') -and
                @($Body['management_access_policies']).Count -eq 0
            }
        }

        It 'sends an EMPTY string for -Password "" rather than dropping the key' {
            Update-PfbAdmin -Name 'ops' -Password '' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('password') -and $Body['password'] -eq ''
            }
        }

        It 'omits every body key when no typed body parameter is supplied' {
            Update-PfbAdmin -Name 'ops' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.Count -eq 0
            }
        }

        It 'targets the admin by id when -Id is used' {
            Update-PfbAdmin -Id 'admin-1' -Password 'x' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['ids'] -eq 'admin-1' -and -not $QueryParams.ContainsKey('names')
            }
        }
    }

    Context '-Attributes remains supported and is mutually exclusive' {
        It 'still sends a raw -Attributes body' {
            Update-PfbAdmin -Name 'ops' -Attributes @{ password = 'raw' } `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['password'] -eq 'raw'
            }
        }

        It 'rejects -Attributes combined with a typed parameter at bind time' {
            { Update-PfbAdmin -Name 'ops' -Password 'x' -Attributes @{ password = 'y' } `
                -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'
        }
    }

    Context 'deprecated fields are not exposed (constraint 9)' {
        It 'has no -Role parameter' {
            (Get-Command Update-PfbAdmin).Parameters.Keys | Should -Not -Contain 'Role'
        }
    }
}
