#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.25'; AuthToken = 'x' }
}

Describe 'Remove-PfbUserGroupQuotaPolicyRule' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    It 'DELETEs user-group-quota-policies/rules by -Name' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ arr = $fakeArray } {
            param($arr)
            Remove-PfbUserGroupQuotaPolicyRule -Name 'rule-1' -Confirm:$false -Array $arr
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'DELETE' -and $Endpoint -eq 'user-group-quota-policies/rules' -and $QueryParams['names'] -eq 'rule-1'
        }
    }

    It 'deletes by -PolicyName alone (clears all of a policy''s rules)' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ arr = $fakeArray } {
            param($arr)
            Remove-PfbUserGroupQuotaPolicyRule -PolicyName 'pol-1' -Confirm:$false -Array $arr
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['policy_names'] -eq 'pol-1' -and -not $QueryParams.ContainsKey('names')
        }
    }

    It 'joins multiple -Id values with commas' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ arr = $fakeArray } {
            param($arr)
            Remove-PfbUserGroupQuotaPolicyRule -Id 'rid-1', 'rid-2' -Confirm:$false -Array $arr
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['ids'] -eq 'rid-1,rid-2'
        }
    }

    It 'rejects a -Name that looks like a wildcard' {
        { InModuleScope PureStorageFlashBladePowerShell -Parameters @{ arr = $fakeArray } {
            param($arr)
            Remove-PfbUserGroupQuotaPolicyRule -Name '*' -Confirm:$false -Array $arr
        } } | Should -Throw
    }

    It 'rejects a -PolicyName that looks like a wildcard' {
        { InModuleScope PureStorageFlashBladePowerShell -Parameters @{ arr = $fakeArray } {
            param($arr)
            Remove-PfbUserGroupQuotaPolicyRule -PolicyName '*' -Confirm:$false -Array $arr
        } } | Should -Throw
    }

    It 'throws when none of -Name/-Id/-PolicyName/-PolicyId is supplied' {
        { InModuleScope PureStorageFlashBladePowerShell -Parameters @{ arr = $fakeArray } {
            param($arr)
            Remove-PfbUserGroupQuotaPolicyRule -Confirm:$false -Array $arr
        } } | Should -Throw
    }

    It 'does not call the API under -WhatIf' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ arr = $fakeArray } {
            param($arr)
            Remove-PfbUserGroupQuotaPolicyRule -Name 'rule-1' -WhatIf -Array $arr
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0
    }

    It 'validates arguments before connecting when none of -Name/-Id/-PolicyName/-PolicyId is supplied' {
        { InModuleScope PureStorageFlashBladePowerShell -Parameters @{ arr = $fakeArray } {
            param($arr)
            Remove-PfbUserGroupQuotaPolicyRule -Confirm:$false -Array $arr
        } } | Should -Throw

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection -Times 0
    }

    It 'combines -Name and -PolicyName as AND: both filters are sent in a single request' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ arr = $fakeArray } {
            param($arr)
            Remove-PfbUserGroupQuotaPolicyRule -Name 'rule-1' -PolicyName 'pol-1' -Confirm:$false -Array $arr
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['names'] -eq 'rule-1' -and $QueryParams['policy_names'] -eq 'pol-1'
        }
    }
}
