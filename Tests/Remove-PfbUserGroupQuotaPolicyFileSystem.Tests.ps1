#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.25'; AuthToken = 'x' }
}

Describe 'Remove-PfbUserGroupQuotaPolicyFileSystem' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    It 'DELETEs user-group-quota-policies/file-systems with policy and member query params' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ arr = $fakeArray } {
            param($arr)
            Remove-PfbUserGroupQuotaPolicyFileSystem -PolicyName 'pol-1' -MemberName 'fs1' -Confirm:$false -Array $arr
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'DELETE' -and
            $Endpoint -eq 'user-group-quota-policies/file-systems' -and
            $QueryParams['policy_names'] -eq 'pol-1' -and
            $QueryParams['member_names'] -eq 'fs1'
        }
    }

    It 'accepts -PolicyId/-MemberId instead of names' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ arr = $fakeArray } {
            param($arr)
            Remove-PfbUserGroupQuotaPolicyFileSystem -PolicyId 'pid-1' -MemberId 'mid-1' -Confirm:$false -Array $arr
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['policy_ids'] -eq 'pid-1' -and $QueryParams['member_ids'] -eq 'mid-1'
        }
    }

    It 'does not call the API under -WhatIf' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ arr = $fakeArray } {
            param($arr)
            Remove-PfbUserGroupQuotaPolicyFileSystem -PolicyName 'pol-1' -MemberName 'fs1' -WhatIf -Array $arr
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0
    }

    It 'throws when neither -PolicyName nor -PolicyId is supplied' {
        { InModuleScope PureStorageFlashBladePowerShell -Parameters @{ arr = $fakeArray } {
            param($arr)
            Remove-PfbUserGroupQuotaPolicyFileSystem -MemberName 'fs1' -Confirm:$false -Array $arr
        } } | Should -Throw 'You must supply either -PolicyName or -PolicyId.'
    }

    It 'throws when neither -MemberName nor -MemberId is supplied' {
        { InModuleScope PureStorageFlashBladePowerShell -Parameters @{ arr = $fakeArray } {
            param($arr)
            Remove-PfbUserGroupQuotaPolicyFileSystem -PolicyName 'pol-1' -Confirm:$false -Array $arr
        } } | Should -Throw 'You must supply either -MemberName or -MemberId.'
    }
}
