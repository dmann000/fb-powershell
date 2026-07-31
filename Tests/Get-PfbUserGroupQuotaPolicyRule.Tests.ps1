#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.25'; AuthToken = 'x' }
}

Describe 'Get-PfbUserGroupQuotaPolicyRule' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    It 'GETs user-group-quota-policies/rules with AutoPaginate and no filters by default' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ arr = $fakeArray } {
            param($arr)
            Get-PfbUserGroupQuotaPolicyRule -Array $arr
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'GET' -and $Endpoint -eq 'user-group-quota-policies/rules' -and $AutoPaginate -eq $true
        }
    }

    It 'scopes by -PolicyName via the policy_names query param' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ arr = $fakeArray } {
            param($arr)
            Get-PfbUserGroupQuotaPolicyRule -PolicyName 'pol-1' -Array $arr
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['policy_names'] -eq 'pol-1'
        }
    }

    It 'accepts -PolicyName from the pipeline and joins multiple values' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ arr = $fakeArray } {
            param($arr)
            'pol-1', 'pol-2' | Get-PfbUserGroupQuotaPolicyRule -Array $arr
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['policy_names'] -eq 'pol-1,pol-2'
        }
    }

    It 'scopes by -PolicyId via the policy_ids query param' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ arr = $fakeArray } {
            param($arr)
            Get-PfbUserGroupQuotaPolicyRule -PolicyId 'pid-1' -Array $arr
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['policy_ids'] -eq 'pid-1'
        }
    }

    It 'filters by the rule''s own -Name/-Id independent of policy scoping' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ arr = $fakeArray } {
            param($arr)
            Get-PfbUserGroupQuotaPolicyRule -PolicyName 'pol-1' -Name 'rule-1' -Array $arr
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['policy_names'] -eq 'pol-1' -and $QueryParams['names'] -eq 'rule-1'
        }
    }

    It 'passes -Filter, -Sort, and -Limit through' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ arr = $fakeArray } {
            param($arr)
            Get-PfbUserGroupQuotaPolicyRule -Filter "quota_type='user'" -Sort 'name-' -Limit 5 -Array $arr
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['filter'] -eq "quota_type='user'" -and $QueryParams['sort'] -eq 'name-' -and $QueryParams['limit'] -eq 5
        }
    }
}
