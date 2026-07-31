#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'New-PfbNetworkAccessRule - typed body/query params (#31)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'existing -Attributes path still works' {
        It 'POSTs with -Attributes hashtable unchanged' {
            New-PfbNetworkAccessRule -PolicyName 'network-access-01' -Attributes @{ client = '10.0.0.0/8'; effect = 'allow' } -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Endpoint -eq 'network-access-policies/rules' -and
                $QueryParams['policy_names'] -eq 'network-access-01' -and
                $Body['client'] -eq '10.0.0.0/8' -and $Body['effect'] -eq 'allow'
            }
        }
    }

    Context 'typed body parameters' {
        It 'sends -Client as client' {
            New-PfbNetworkAccessRule -PolicyName 'p1' -Client '10.0.0.0/8' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['client'] -eq '10.0.0.0/8'
            }
        }

        It 'sends -Effect as effect' {
            New-PfbNetworkAccessRule -PolicyName 'p1' -Effect 'deny' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['effect'] -eq 'deny'
            }
        }

        It 'rejects an -Effect value outside the enum' {
            { New-PfbNetworkAccessRule -PolicyName 'p1' -Effect 'bogus' -Confirm:$false -Array $fakeArray } | Should -Throw
        }

        It 'sends -Index as index, including an explicit 0 (constraint 2, integer field)' {
            New-PfbNetworkAccessRule -PolicyName 'p1' -Index 0 -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('index') -and $Body['index'] -eq 0
            }
        }

        It 'sends -Interfaces as interfaces' {
            New-PfbNetworkAccessRule -PolicyName 'p1' -Interfaces @('management-ssh', 'snmp') -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['interfaces'].Count -eq 2 -and
                $Body['interfaces'][0] -eq 'management-ssh' -and
                $Body['interfaces'][1] -eq 'snmp'
            }
        }

        It 'sends an explicit empty -Interfaces @() (constraint 2, array field)' {
            New-PfbNetworkAccessRule -PolicyName 'p1' -Interfaces @() -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('interfaces') -and $Body['interfaces'].Count -eq 0
            }
        }

        It 'rejects an -Interfaces value outside the enum' {
            { New-PfbNetworkAccessRule -PolicyName 'p1' -Interfaces @('bogus') -Confirm:$false -Array $fakeArray } | Should -Throw
        }

        It 'omits fields that were not supplied' {
            New-PfbNetworkAccessRule -PolicyName 'p1' -Client 'x' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                -not $Body.ContainsKey('effect') -and -not $Body.ContainsKey('index') -and -not $Body.ContainsKey('interfaces')
            }
        }
    }

    Context 'typed query parameters' {
        It 'sends -BeforeRuleId as before_rule_id' {
            New-PfbNetworkAccessRule -PolicyName 'p1' -BeforeRuleId 'rule-1' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['before_rule_id'] -eq 'rule-1'
            }
        }

        It 'sends -BeforeRuleName as before_rule_name' {
            New-PfbNetworkAccessRule -PolicyName 'p1' -BeforeRuleName 'rule-name' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['before_rule_name'] -eq 'rule-name'
            }
        }

        It 'sends -Versions as a joined versions query param' {
            New-PfbNetworkAccessRule -PolicyName 'p1' -Versions @('1', '2') -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['versions'] -eq '1,2'
            }
        }

        It 'allows a query parameter alongside -Attributes (query is orthogonal to body, constraint 17)' {
            New-PfbNetworkAccessRule -PolicyName 'p1' -Attributes @{ client = 'x' } -BeforeRuleId 'rule-1' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['before_rule_id'] -eq 'rule-1' -and $Body['client'] -eq 'x'
            }
        }
    }

    Context 'parameter set mutual exclusion' {
        It 'rejects mixing a typed body parameter with -Attributes' {
            { New-PfbNetworkAccessRule -PolicyName 'p1' -Client 'x' -Attributes @{ client = 'x' } -Confirm:$false -Array $fakeArray } |
                Should -Throw '*Parameter set cannot be resolved*'
        }
    }

    Context 'ById selector still works' {
        It 'supports -PolicyId with typed params' {
            New-PfbNetworkAccessRule -PolicyId 'pid-1' -Client 'x' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['policy_ids'] -eq 'pid-1' -and $Body['client'] -eq 'x'
            }
        }
    }
}
