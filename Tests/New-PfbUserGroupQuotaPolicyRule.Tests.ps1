#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.25'; AuthToken = 'x' }
}

Describe 'New-PfbUserGroupQuotaPolicyRule' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    It 'POSTs user-group-quota-policies/rules scoped to -PolicyName with a subject/quota body' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ fakeArray = $fakeArray } {
            param($fakeArray)
            New-PfbUserGroupQuotaPolicyRule -PolicyName 'pol-1' -Subject @{ name = 'jdoe' } -QuotaType 'user' -QuotaLimit 1073741824 -Confirm:$false -Array $fakeArray
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'POST' -and
            $Endpoint -eq 'user-group-quota-policies/rules' -and
            $QueryParams['policy_names'] -eq 'pol-1' -and
            $Body['subject']['name'] -eq 'jdoe' -and
            $Body['quota_type'] -eq 'user' -and
            $Body['quota_limit'] -eq 1073741824
        }
    }

    It 'scopes by -PolicyId instead of -PolicyName' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ fakeArray = $fakeArray } {
            param($fakeArray)
            New-PfbUserGroupQuotaPolicyRule -PolicyId 'pid-1' -QuotaType 'user-default' -QuotaLimit 100 -Confirm:$false -Array $fakeArray
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['policy_ids'] -eq 'pid-1' -and -not $QueryParams.ContainsKey('policy_names')
        }
    }

    It 'sends -Enforced and -Notifications when supplied' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ fakeArray = $fakeArray } {
            param($fakeArray)
            New-PfbUserGroupQuotaPolicyRule -PolicyName 'pol-1' -QuotaType 'user-default' -QuotaLimit 100 -Enforced:$true -Notifications 'None' -Confirm:$false -Array $fakeArray
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $Body['enforced'] -eq $true -and $Body['notifications'] -eq 'None'
        }
    }

    It 'sends ignore_usage when -IgnoreUsage is set' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ fakeArray = $fakeArray } {
            param($fakeArray)
            New-PfbUserGroupQuotaPolicyRule -PolicyName 'pol-1' -QuotaType 'user-default' -QuotaLimit 100 -IgnoreUsage -Confirm:$false -Array $fakeArray
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['ignore_usage'] -eq 'true'
        }
    }

    It 'rejects an invalid -QuotaType' {
        { InModuleScope PureStorageFlashBladePowerShell -Parameters @{ fakeArray = $fakeArray } {
            param($fakeArray)
            New-PfbUserGroupQuotaPolicyRule -PolicyName 'pol-1' -QuotaType 'bogus' -QuotaLimit 100 -Confirm:$false -Array $fakeArray
        } } | Should -Throw
    }

    It '-Attributes overrides the constructed body verbatim' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ fakeArray = $fakeArray } {
            param($fakeArray)
            New-PfbUserGroupQuotaPolicyRule -PolicyName 'pol-1' -Attributes @{ quota_limit = 42 } -Confirm:$false -Array $fakeArray
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $Body.Keys.Count -eq 1 -and $Body['quota_limit'] -eq 42
        }
    }

    It 'does not call the API under -WhatIf' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ fakeArray = $fakeArray } {
            param($fakeArray)
            New-PfbUserGroupQuotaPolicyRule -PolicyName 'pol-1' -QuotaType 'user-default' -QuotaLimit 100 -WhatIf -Array $fakeArray
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0
    }

    It 'rejects a -QuotaLimit of 0' {
        { InModuleScope PureStorageFlashBladePowerShell -Parameters @{ fakeArray = $fakeArray } {
            param($fakeArray)
            New-PfbUserGroupQuotaPolicyRule -PolicyName 'pol-1' -QuotaType 'user-default' -QuotaLimit 0 -Confirm:$false -Array $fakeArray
        } } | Should -Throw
    }

    It 'rejects -QuotaType user-default combined with -Subject' {
        { InModuleScope PureStorageFlashBladePowerShell -Parameters @{ fakeArray = $fakeArray } {
            param($fakeArray)
            New-PfbUserGroupQuotaPolicyRule -PolicyName 'pol-1' -Subject @{ name = 'jdoe' } -QuotaType 'user-default' -QuotaLimit 100 -Confirm:$false -Array $fakeArray
        } } | Should -Throw
    }
}
