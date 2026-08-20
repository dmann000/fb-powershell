#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.25'; AuthToken = 'x' }
}

Describe 'Get-PfbUserGroupQuotaPolicyMember' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    It 'GETs user-group-quota-policies/members with AutoPaginate' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ arr = $fakeArray } {
            param($arr)
            Get-PfbUserGroupQuotaPolicyMember -Array $arr
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'GET' -and $Endpoint -eq 'user-group-quota-policies/members' -and $AutoPaginate -eq $true
        }
    }

    It 'filters by -PolicyName and -MemberName' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ arr = $fakeArray } {
            param($arr)
            Get-PfbUserGroupQuotaPolicyMember -PolicyName 'pol-1' -MemberName 'fs1' -Array $arr
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['policy_names'] -eq 'pol-1' -and $QueryParams['member_names'] -eq 'fs1'
        }
    }

    It 'passes -Limit through' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ arr = $fakeArray } {
            param($arr)
            Get-PfbUserGroupQuotaPolicyMember -Limit 10 -Array $arr
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['limit'] -eq 10
        }
    }

    It 'honors falsy -Limit 0 and empty -Filter instead of dropping them' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ arr = $fakeArray } {
            param($arr)
            Get-PfbUserGroupQuotaPolicyMember -Filter '' -Limit 0 -Array $arr
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams.ContainsKey('filter') -and $QueryParams['filter'] -eq '' -and
            $QueryParams.ContainsKey('limit') -and $QueryParams['limit'] -eq 0
        }
    }

    It 'does not expose -TotalOnly (user-group-quota-policies/members does not declare total_only, #102)' {
        (Get-Command Get-PfbUserGroupQuotaPolicyMember).Parameters.Keys | Should -Not -Contain 'TotalOnly'

        { Get-PfbUserGroupQuotaPolicyMember -TotalOnly -Array $fakeArray } |
            Should -Throw -ExpectedMessage '*TotalOnly*'
    }
}
