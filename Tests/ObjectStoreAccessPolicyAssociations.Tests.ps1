#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule
    # A throwaway connection object; Assert-PfbConnection is mocked so its contents don't matter.
    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'ObjectStore AccessPolicy `<-> Role association' {
    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { $Array.Value = $script:fakeArray }
    }

    It 'Get-PfbObjectStoreAccessPolicyRole flattens nested policy/member into top-level PolicyName/MemberName' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest {
            [pscustomobject]@{
                policy = [pscustomobject]@{ name = 'full-access-policy' }
                member = [pscustomobject]@{ name = 's3-admin-role' }
            }
        }
        $result = Get-PfbObjectStoreAccessPolicyRole
        $result.PolicyName | Should -Be 'full-access-policy'
        $result.MemberName | Should -Be 's3-admin-role'
    }

    It 'Get output pipes into Remove-* producing a DELETE with flattened values' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -ParameterFilter { $Method -eq 'GET' } {
            [pscustomobject]@{
                policy = [pscustomobject]@{ name = 'full-access-policy' }
                member = [pscustomobject]@{ name = 's3-admin-role' }
            }
        }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -ParameterFilter { $Method -ne 'GET' } { }
        Get-PfbObjectStoreAccessPolicyRole | Remove-PfbObjectStoreAccessPolicyRole -Confirm:$false
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'DELETE' -and $Endpoint -eq 'object-store-access-policies/object-store-roles' -and
            $QueryParams['policy_names'] -eq 'full-access-policy' -and $QueryParams['member_names'] -eq 's3-admin-role'
        }
    }

    It 'Get output pipes into New-* producing a POST with flattened values' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -ParameterFilter { $Method -eq 'GET' } {
            [pscustomobject]@{
                policy = [pscustomobject]@{ name = 'full-access-policy' }
                member = [pscustomobject]@{ name = 's3-admin-role' }
            }
        }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -ParameterFilter { $Method -ne 'GET' } { }
        Get-PfbObjectStoreAccessPolicyRole | New-PfbObjectStoreAccessPolicyRole -Confirm:$false
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'POST' -and $Endpoint -eq 'object-store-access-policies/object-store-roles' -and
            $QueryParams['policy_names'] -eq 'full-access-policy' -and $QueryParams['member_names'] -eq 's3-admin-role'
        }
    }

    It 'piping 2 associations into Remove-* calls the API twice' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
        @(
            [pscustomobject]@{ PolicyName = 'p1'; MemberName = 'r1' }
            [pscustomobject]@{ PolicyName = 'p1'; MemberName = 'r2' }
        ) | Remove-PfbObjectStoreAccessPolicyRole -Confirm:$false
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 2 -Exactly -ParameterFilter { $Method -eq 'DELETE' }
    }

    It 'explicit -PolicyName / -MemberName still works on both New and Remove' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
        New-PfbObjectStoreAccessPolicyRole -PolicyName 'p1' -MemberName 'r1' -Confirm:$false
        Remove-PfbObjectStoreAccessPolicyRole -PolicyName 'p1' -MemberName 'r1' -Confirm:$false
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter { $Method -eq 'POST' }
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter { $Method -eq 'DELETE' }
    }
}

Describe 'ObjectStore AccessPolicy `<-> User association' {
    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { $Array.Value = $script:fakeArray }
    }

    It 'Get-PfbObjectStoreAccessPolicyUser flattens nested policy/member' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest {
            [pscustomobject]@{
                policy = [pscustomobject]@{ name = 'full-access-policy' }
                member = [pscustomobject]@{ name = 'acct1/user1' }
            }
        }
        $result = Get-PfbObjectStoreAccessPolicyUser
        $result.PolicyName | Should -Be 'full-access-policy'
        $result.MemberName | Should -Be 'acct1/user1'
    }

    It 'Get output pipes into Remove-* producing a DELETE with flattened values' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -ParameterFilter { $Method -eq 'GET' } {
            [pscustomobject]@{
                policy = [pscustomobject]@{ name = 'full-access-policy' }
                member = [pscustomobject]@{ name = 'acct1/user1' }
            }
        }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -ParameterFilter { $Method -ne 'GET' } { }
        Get-PfbObjectStoreAccessPolicyUser | Remove-PfbObjectStoreAccessPolicyUser -Confirm:$false
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'DELETE' -and $Endpoint -eq 'object-store-access-policies/object-store-users' -and
            $QueryParams['policy_names'] -eq 'full-access-policy' -and $QueryParams['member_names'] -eq 'acct1/user1'
        }
    }

    It 'Get output pipes into New-* producing a POST with flattened values' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -ParameterFilter { $Method -eq 'GET' } {
            [pscustomobject]@{
                policy = [pscustomobject]@{ name = 'full-access-policy' }
                member = [pscustomobject]@{ name = 'acct1/user1' }
            }
        }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -ParameterFilter { $Method -ne 'GET' } { }
        Get-PfbObjectStoreAccessPolicyUser | New-PfbObjectStoreAccessPolicyUser -Confirm:$false
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'POST' -and $Endpoint -eq 'object-store-access-policies/object-store-users' -and
            $QueryParams['policy_names'] -eq 'full-access-policy' -and $QueryParams['member_names'] -eq 'acct1/user1'
        }
    }

    It 'piping 2 associations into Remove-* calls the API twice' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
        @(
            [pscustomobject]@{ PolicyName = 'p1'; MemberName = 'acct1/u1' }
            [pscustomobject]@{ PolicyName = 'p1'; MemberName = 'acct1/u2' }
        ) | Remove-PfbObjectStoreAccessPolicyUser -Confirm:$false
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 2 -Exactly -ParameterFilter { $Method -eq 'DELETE' }
    }

    It 'explicit -PolicyName / -MemberName still works on both New and Remove' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
        New-PfbObjectStoreAccessPolicyUser -PolicyName 'p1' -MemberName 'acct1/u1' -Confirm:$false
        Remove-PfbObjectStoreAccessPolicyUser -PolicyName 'p1' -MemberName 'acct1/u1' -Confirm:$false
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter { $Method -eq 'POST' }
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter { $Method -eq 'DELETE' }
    }
}

Describe 'ObjectStore User `<-> AccessPolicy association (reverse order)' {
    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { $Array.Value = $script:fakeArray }
    }

    It 'Get-PfbObjectStoreUserAccessPolicy flattens nested member/policy' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest {
            [pscustomobject]@{
                member = [pscustomobject]@{ name = 'acct1/user1' }
                policy = [pscustomobject]@{ name = 'full-access-policy' }
            }
        }
        $result = Get-PfbObjectStoreUserAccessPolicy
        $result.MemberName | Should -Be 'acct1/user1'
        $result.PolicyName | Should -Be 'full-access-policy'
    }

    It 'Get output pipes into Remove-* (reverse param order) producing a DELETE with flattened values' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -ParameterFilter { $Method -eq 'GET' } {
            [pscustomobject]@{
                member = [pscustomobject]@{ name = 'acct1/user1' }
                policy = [pscustomobject]@{ name = 'full-access-policy' }
            }
        }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -ParameterFilter { $Method -ne 'GET' } { }
        Get-PfbObjectStoreUserAccessPolicy | Remove-PfbObjectStoreUserAccessPolicy -Confirm:$false
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'DELETE' -and $Endpoint -eq 'object-store-users/object-store-access-policies' -and
            $QueryParams['member_names'] -eq 'acct1/user1' -and $QueryParams['policy_names'] -eq 'full-access-policy'
        }
    }

    It 'Get output pipes into New-* producing a POST with flattened values' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -ParameterFilter { $Method -eq 'GET' } {
            [pscustomobject]@{
                member = [pscustomobject]@{ name = 'acct1/user1' }
                policy = [pscustomobject]@{ name = 'full-access-policy' }
            }
        }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -ParameterFilter { $Method -ne 'GET' } { }
        Get-PfbObjectStoreUserAccessPolicy | New-PfbObjectStoreUserAccessPolicy -Confirm:$false
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'POST' -and $Endpoint -eq 'object-store-users/object-store-access-policies' -and
            $QueryParams['member_names'] -eq 'acct1/user1' -and $QueryParams['policy_names'] -eq 'full-access-policy'
        }
    }

    It 'piping 2 associations into Remove-* calls the API twice' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
        @(
            [pscustomobject]@{ MemberName = 'acct1/u1'; PolicyName = 'p1' }
            [pscustomobject]@{ MemberName = 'acct1/u2'; PolicyName = 'p1' }
        ) | Remove-PfbObjectStoreUserAccessPolicy -Confirm:$false
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 2 -Exactly -ParameterFilter { $Method -eq 'DELETE' }
    }

    It 'explicit -MemberName / -PolicyName still works on both New and Remove' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
        New-PfbObjectStoreUserAccessPolicy -MemberName 'acct1/u1' -PolicyName 'p1' -Confirm:$false
        Remove-PfbObjectStoreUserAccessPolicy -MemberName 'acct1/u1' -PolicyName 'p1' -Confirm:$false
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter { $Method -eq 'POST' }
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter { $Method -eq 'DELETE' }
    }
}
