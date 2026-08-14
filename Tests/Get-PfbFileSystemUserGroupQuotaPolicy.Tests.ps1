#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.25'; AuthToken = 'x' }
}

Describe 'Get-PfbFileSystemUserGroupQuotaPolicy' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    It 'GETs file-systems/user-group-quota-policies with AutoPaginate' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ arr = $fakeArray } {
            param($arr)
            Get-PfbFileSystemUserGroupQuotaPolicy -Array $arr
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'GET' -and $Endpoint -eq 'file-systems/user-group-quota-policies' -and $AutoPaginate -eq $true
        }
    }

    It 'filters by -MemberName (the file system) and -PolicyName' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ arr = $fakeArray } {
            param($arr)
            Get-PfbFileSystemUserGroupQuotaPolicy -MemberName 'fs1' -PolicyName 'pol-1' -Array $arr
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['member_names'] -eq 'fs1' -and $QueryParams['policy_names'] -eq 'pol-1'
        }
    }

    It 'filters by -PolicyId and -MemberId' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ arr = $fakeArray } {
            param($arr)
            Get-PfbFileSystemUserGroupQuotaPolicy -PolicyId 'pid-1' -MemberId 'mid-1' -Array $arr
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['policy_ids'] -eq 'pid-1' -and $QueryParams['member_ids'] -eq 'mid-1'
        }
    }

    It 'passes -Filter, -Sort, and -Limit through' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ arr = $fakeArray } {
            param($arr)
            Get-PfbFileSystemUserGroupQuotaPolicy -Filter "name='pol-1'" -Sort 'name-' -Limit 5 -Array $arr
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['filter'] -eq "name='pol-1'" -and $QueryParams['sort'] -eq 'name-' -and $QueryParams['limit'] -eq 5
        }
    }

    It 'honors falsy -Limit 0 and empty -Filter instead of dropping them' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ arr = $fakeArray } {
            param($arr)
            Get-PfbFileSystemUserGroupQuotaPolicy -Filter '' -Limit 0 -Array $arr
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams.ContainsKey('filter') -and $QueryParams['filter'] -eq '' -and
            $QueryParams.ContainsKey('limit') -and $QueryParams['limit'] -eq 0
        }
    }

    It 'does not expose -TotalOnly (file-systems/user-group-quota-policies does not declare total_only, #102)' {
        (Get-Command Get-PfbFileSystemUserGroupQuotaPolicy).Parameters.Keys | Should -Not -Contain 'TotalOnly'

        { Get-PfbFileSystemUserGroupQuotaPolicy -TotalOnly -Array $fakeArray } |
            Should -Throw -ExpectedMessage '*TotalOnly*'
    }
}
