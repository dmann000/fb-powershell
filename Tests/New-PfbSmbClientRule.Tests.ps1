#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'New-PfbSmbClientRule - typed body/query params (#31)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'existing -Attributes path still works' {
        It 'POSTs with -Attributes hashtable unchanged' {
            New-PfbSmbClientRule -PolicyName 'smb-client-01' -Attributes @{ client = '*' } -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Endpoint -eq 'smb-client-policies/rules' -and
                $QueryParams['policy_names'] -eq 'smb-client-01' -and $Body['client'] -eq '*'
            }
        }
    }

    Context 'typed body parameters' {
        It 'sends -Client as client' {
            New-PfbSmbClientRule -PolicyName 'p1' -Client '10.0.0.0/8' -Confirm:$false -Array $fakeArray
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter { $Body['client'] -eq '10.0.0.0/8' }
        }

        It 'sends -Encryption as encryption' {
            New-PfbSmbClientRule -PolicyName 'p1' -Encryption 'required' -Confirm:$false -Array $fakeArray
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter { $Body['encryption'] -eq 'required' }
        }

        It 'rejects an -Encryption value outside the enum' {
            { New-PfbSmbClientRule -PolicyName 'p1' -Encryption 'bogus' -Confirm:$false -Array $fakeArray } | Should -Throw
        }

        It 'sends -Index as index, including an explicit 0 (constraint 2, integer field)' {
            New-PfbSmbClientRule -PolicyName 'p1' -Index 0 -Confirm:$false -Array $fakeArray
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('index') -and $Body['index'] -eq 0
            }
        }

        It 'sends -Permission as permission' {
            New-PfbSmbClientRule -PolicyName 'p1' -Permission 'ro' -Confirm:$false -Array $fakeArray
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter { $Body['permission'] -eq 'ro' }
        }

        It 'rejects a -Permission value outside the enum' {
            { New-PfbSmbClientRule -PolicyName 'p1' -Permission 'bogus' -Confirm:$false -Array $fakeArray } | Should -Throw
        }
    }

    Context 'typed query parameters' {
        It 'sends -BeforeRuleId as before_rule_id' {
            New-PfbSmbClientRule -PolicyName 'p1' -BeforeRuleId 'rule-1' -Confirm:$false -Array $fakeArray
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter { $QueryParams['before_rule_id'] -eq 'rule-1' }
        }

        It 'sends -BeforeRuleName as before_rule_name' {
            New-PfbSmbClientRule -PolicyName 'p1' -BeforeRuleName 'rule-name' -Confirm:$false -Array $fakeArray
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter { $QueryParams['before_rule_name'] -eq 'rule-name' }
        }

        It 'sends -Versions as a joined versions query param' {
            New-PfbSmbClientRule -PolicyName 'p1' -Versions @('5', '6') -Confirm:$false -Array $fakeArray
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter { $QueryParams['versions'] -eq '5,6' }
        }

        It 'allows a query parameter alongside -Attributes (constraint 17)' {
            New-PfbSmbClientRule -PolicyName 'p1' -Attributes @{ client = 'x' } -BeforeRuleId 'rule-1' -Confirm:$false -Array $fakeArray
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['before_rule_id'] -eq 'rule-1' -and $Body['client'] -eq 'x'
            }
        }
    }

    Context 'parameter set mutual exclusion' {
        It 'rejects mixing a typed body parameter with -Attributes' {
            { New-PfbSmbClientRule -PolicyName 'p1' -Client 'x' -Attributes @{ client = 'x' } -Confirm:$false -Array $fakeArray } |
                Should -Throw '*Parameter set cannot be resolved*'
        }
    }

    Context 'ById selector still works' {
        It 'supports -PolicyId with typed params' {
            New-PfbSmbClientRule -PolicyId 'pid-1' -Client 'x' -Confirm:$false -Array $fakeArray
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['policy_ids'] -eq 'pid-1' -and $Body['client'] -eq 'x'
            }
        }
    }
}
