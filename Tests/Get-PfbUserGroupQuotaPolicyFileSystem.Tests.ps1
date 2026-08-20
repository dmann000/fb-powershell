#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.25'; AuthToken = 'x' }
}

Describe 'Get-PfbUserGroupQuotaPolicyFileSystem' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    It 'GETs user-group-quota-policies/file-systems with AutoPaginate' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ arr = $fakeArray } {
            param($arr)
            Get-PfbUserGroupQuotaPolicyFileSystem -Array $arr
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'GET' -and $Endpoint -eq 'user-group-quota-policies/file-systems' -and $AutoPaginate -eq $true
        }
    }

    It 'filters by -PolicyName and -MemberName' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ arr = $fakeArray } {
            param($arr)
            Get-PfbUserGroupQuotaPolicyFileSystem -PolicyName 'pol-1' -MemberName 'fs1' -Array $arr
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['policy_names'] -eq 'pol-1' -and $QueryParams['member_names'] -eq 'fs1'
        }
    }

    It 'filters by -PolicyId and -MemberId' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ arr = $fakeArray } {
            param($arr)
            Get-PfbUserGroupQuotaPolicyFileSystem -PolicyId 'pid-1' -MemberId 'mid-1' -Array $arr
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['policy_ids'] -eq 'pid-1' -and $QueryParams['member_ids'] -eq 'mid-1'
        }
    }

    It 'passes -Filter, -Sort, and -Limit through' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ arr = $fakeArray } {
            param($arr)
            Get-PfbUserGroupQuotaPolicyFileSystem -Filter "name='fs1'" -Sort 'name-' -Limit 5 -Array $arr
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['filter'] -eq "name='fs1'" -and $QueryParams['sort'] -eq 'name-' -and $QueryParams['limit'] -eq 5
        }
    }

    It 'honors falsy -Limit 0 and empty -Filter instead of dropping them' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ arr = $fakeArray } {
            param($arr)
            Get-PfbUserGroupQuotaPolicyFileSystem -Filter '' -Limit 0 -Array $arr
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams.ContainsKey('filter') -and $QueryParams['filter'] -eq '' -and
            $QueryParams.ContainsKey('limit') -and $QueryParams['limit'] -eq 0
        }
    }

    It 'does not expose -TotalOnly (user-group-quota-policies/file-systems does not declare total_only, #102)' {
        (Get-Command Get-PfbUserGroupQuotaPolicyFileSystem).Parameters.Keys | Should -Not -Contain 'TotalOnly'

        { Get-PfbUserGroupQuotaPolicyFileSystem -TotalOnly -Array $fakeArray } |
            Should -Throw -ExpectedMessage '*TotalOnly*'
    }
}
