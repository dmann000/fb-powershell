#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.25'; AuthToken = 'x' }
}

Describe 'New-PfbFileSystemUserGroupQuotaPolicy' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    It 'POSTs file-systems/user-group-quota-policies with policy and member query params' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ fakeArray = $fakeArray } {
            param($fakeArray)
            New-PfbFileSystemUserGroupQuotaPolicy -PolicyName 'pol-1' -MemberName 'fs1' -Confirm:$false -Array $fakeArray
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'POST' -and
            $Endpoint -eq 'file-systems/user-group-quota-policies' -and
            $QueryParams['policy_names'] -eq 'pol-1' -and
            $QueryParams['member_names'] -eq 'fs1'
        }
    }

    It 'sends delete_existing_user_group_quota_settings and ignore_usage when requested' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ fakeArray = $fakeArray } {
            param($fakeArray)
            New-PfbFileSystemUserGroupQuotaPolicy -PolicyName 'pol-1' -MemberName 'fs1' -DeleteExistingUserGroupQuotaSettings -IgnoreUsage -Confirm:$false -Array $fakeArray
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['delete_existing_user_group_quota_settings'] -eq 'true' -and $QueryParams['ignore_usage'] -eq 'true'
        }
    }

    It 'throws when neither -PolicyName nor -PolicyId is supplied' {
        { InModuleScope PureStorageFlashBladePowerShell -Parameters @{ fakeArray = $fakeArray } {
            param($fakeArray)
            New-PfbFileSystemUserGroupQuotaPolicy -MemberName 'fs1' -Confirm:$false -Array $fakeArray
        } } | Should -Throw
    }

    It 'throws when neither -MemberName nor -MemberId is supplied' {
        { InModuleScope PureStorageFlashBladePowerShell -Parameters @{ fakeArray = $fakeArray } {
            param($fakeArray)
            New-PfbFileSystemUserGroupQuotaPolicy -PolicyName 'pol-1' -Confirm:$false -Array $fakeArray
        } } | Should -Throw
    }

    It 'does not call the API under -WhatIf' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ fakeArray = $fakeArray } {
            param($fakeArray)
            New-PfbFileSystemUserGroupQuotaPolicy -PolicyName 'pol-1' -MemberName 'fs1' -WhatIf -Array $fakeArray
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0
    }
}
