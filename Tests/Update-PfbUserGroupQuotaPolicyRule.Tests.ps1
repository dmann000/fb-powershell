#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.25'; AuthToken = 'x' }
}

Describe 'Update-PfbUserGroupQuotaPolicyRule' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    It 'PATCHes user-group-quota-policies/rules by -Name with only quota_limit/notifications in the body' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ arr = $fakeArray } {
            param($arr)
            Update-PfbUserGroupQuotaPolicyRule -Name 'rule-1' -QuotaLimit 2147483648 -Notifications 'None' -Confirm:$false -Array $arr
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'PATCH' -and
            $Endpoint -eq 'user-group-quota-policies/rules' -and
            $QueryParams['names'] -eq 'rule-1' -and
            $Body['quota_limit'] -eq 2147483648 -and
            $Body['notifications'] -eq 'None' -and
            $Body.Keys.Count -eq 2
        }
    }

    It 'targets by -Id instead of -Name' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ arr = $fakeArray } {
            param($arr)
            Update-PfbUserGroupQuotaPolicyRule -Id 'rid-1' -QuotaLimit 100 -Confirm:$false -Array $arr
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['ids'] -eq 'rid-1' -and -not $QueryParams.ContainsKey('names')
        }
    }

    It 'sends ignore_usage when -IgnoreUsage is set' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ arr = $fakeArray } {
            param($arr)
            Update-PfbUserGroupQuotaPolicyRule -Name 'rule-1' -QuotaLimit 100 -IgnoreUsage -Confirm:$false -Array $arr
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['ignore_usage'] -eq 'true'
        }
    }

    It '-Attributes overrides the constructed body verbatim' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ arr = $fakeArray } {
            param($arr)
            Update-PfbUserGroupQuotaPolicyRule -Name 'rule-1' -Attributes @{ quota_limit = 7 } -Confirm:$false -Array $arr
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $Body.Keys.Count -eq 1 -and $Body['quota_limit'] -eq 7
        }
    }
}
