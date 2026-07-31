#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'New-PfbNfsExportRule - typed body/query params (#31)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'existing -Attributes path still works' {
        It 'POSTs with -Attributes hashtable unchanged' {
            New-PfbNfsExportRule -PolicyName 'nfs-export-01' -Attributes @{ client = '*'; access = 'root-squash' } -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Endpoint -eq 'nfs-export-policies/rules' -and
                $QueryParams['policy_names'] -eq 'nfs-export-01' -and
                $Body['client'] -eq '*' -and $Body['access'] -eq 'root-squash'
            }
        }
    }

    Context 'typed body parameters - strings and enums' {
        It 'sends -Client as client' {
            New-PfbNfsExportRule -PolicyName 'p1' -Client '10.0.0.0/8' -Confirm:$false -Array $fakeArray
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter { $Body['client'] -eq '10.0.0.0/8' }
        }

        It 'sends -Access as access' {
            New-PfbNfsExportRule -PolicyName 'p1' -Access 'no-squash' -Confirm:$false -Array $fakeArray
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter { $Body['access'] -eq 'no-squash' }
        }

        It 'rejects an -Access value outside the enum' {
            { New-PfbNfsExportRule -PolicyName 'p1' -Access 'bogus' -Confirm:$false -Array $fakeArray } | Should -Throw
        }

        It 'sends -Permission as permission' {
            New-PfbNfsExportRule -PolicyName 'p1' -Permission 'ro' -Confirm:$false -Array $fakeArray
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter { $Body['permission'] -eq 'ro' }
        }

        It 'rejects a -Permission value outside the enum' {
            { New-PfbNfsExportRule -PolicyName 'p1' -Permission 'bogus' -Confirm:$false -Array $fakeArray } | Should -Throw
        }

        It 'sends -RequiredTransportSecurity as required_transport_security (3-value enum, not boolean)' {
            New-PfbNfsExportRule -PolicyName 'p1' -RequiredTransportSecurity 'mutual-tls' -Confirm:$false -Array $fakeArray
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter { $Body['required_transport_security'] -eq 'mutual-tls' }
        }

        It 'rejects a -RequiredTransportSecurity value outside the 3-value enum' {
            { New-PfbNfsExportRule -PolicyName 'p1' -RequiredTransportSecurity 'bogus' -Confirm:$false -Array $fakeArray } | Should -Throw
        }
    }

    Context 'typed body parameters - integers (constraint 2: explicit 0)' {
        It 'sends -Anongid as anongid, including an explicit 0 (root)' {
            New-PfbNfsExportRule -PolicyName 'p1' -Anongid 0 -Confirm:$false -Array $fakeArray
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('anongid') -and $Body['anongid'] -eq 0
            }
        }

        It 'sends -Anonuid as anonuid, including an explicit 0 (root)' {
            New-PfbNfsExportRule -PolicyName 'p1' -Anonuid 0 -Confirm:$false -Array $fakeArray
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('anonuid') -and $Body['anonuid'] -eq 0
            }
        }

        It 'sends -Index as index, including an explicit 0' {
            New-PfbNfsExportRule -PolicyName 'p1' -Index 0 -Confirm:$false -Array $fakeArray
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('index') -and $Body['index'] -eq 0
            }
        }

        It 'accepts -Anonuid values beyond Int32 range (spec type is int64)' {
            New-PfbNfsExportRule -PolicyName 'p1' -Anonuid 3000000000 -Confirm:$false -Array $fakeArray
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter { $Body['anonuid'] -eq 3000000000 }
        }
    }

    Context 'typed body parameters - booleans (explicit $false must reach the wire)' {
        It 'sends -Atime $false explicitly' {
            New-PfbNfsExportRule -PolicyName 'p1' -Atime $false -Confirm:$false -Array $fakeArray
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('atime') -and $Body['atime'] -eq $false
            }
        }

        It 'sends -Fileid32bit $false explicitly' {
            New-PfbNfsExportRule -PolicyName 'p1' -Fileid32bit $false -Confirm:$false -Array $fakeArray
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('fileid_32bit') -and $Body['fileid_32bit'] -eq $false
            }
        }

        It 'sends -Secure $false explicitly' {
            New-PfbNfsExportRule -PolicyName 'p1' -Secure $false -Confirm:$false -Array $fakeArray
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('secure') -and $Body['secure'] -eq $false
            }
        }
    }

    Context 'typed body parameters - array (constraint 2: explicit @())' {
        It 'sends -Security as security' {
            New-PfbNfsExportRule -PolicyName 'p1' -Security @('sys', 'krb5') -Confirm:$false -Array $fakeArray
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['security'].Count -eq 2 -and $Body['security'][0] -eq 'sys' -and $Body['security'][1] -eq 'krb5'
            }
        }

        It 'sends an explicit empty -Security @()' {
            New-PfbNfsExportRule -PolicyName 'p1' -Security @() -Confirm:$false -Array $fakeArray
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('security') -and $Body['security'].Count -eq 0
            }
        }
    }

    Context 'typed body parameter - scalar reference (constraint 8a)' {
        It 'sends -Policy as a { name = ... } reference object' {
            New-PfbNfsExportRule -PolicyName 'p1' -Policy 'other-policy' -Confirm:$false -Array $fakeArray
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['policy']['name'] -eq 'other-policy'
            }
        }
    }

    Context 'typed query parameters' {
        It 'sends -BeforeRuleId as before_rule_id' {
            New-PfbNfsExportRule -PolicyName 'p1' -BeforeRuleId 'rule-1' -Confirm:$false -Array $fakeArray
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter { $QueryParams['before_rule_id'] -eq 'rule-1' }
        }

        It 'sends -BeforeRuleName as before_rule_name' {
            New-PfbNfsExportRule -PolicyName 'p1' -BeforeRuleName 'rule-name' -Confirm:$false -Array $fakeArray
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter { $QueryParams['before_rule_name'] -eq 'rule-name' }
        }

        It 'sends -Versions as a joined versions query param' {
            New-PfbNfsExportRule -PolicyName 'p1' -Versions @('3', '4') -Confirm:$false -Array $fakeArray
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter { $QueryParams['versions'] -eq '3,4' }
        }

        It 'allows a query parameter alongside -Attributes (constraint 17)' {
            New-PfbNfsExportRule -PolicyName 'p1' -Attributes @{ client = 'x' } -BeforeRuleId 'rule-1' -Confirm:$false -Array $fakeArray
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['before_rule_id'] -eq 'rule-1' -and $Body['client'] -eq 'x'
            }
        }
    }

    Context 'parameter set mutual exclusion' {
        It 'rejects mixing a typed body parameter with -Attributes' {
            { New-PfbNfsExportRule -PolicyName 'p1' -Client 'x' -Attributes @{ client = 'x' } -Confirm:$false -Array $fakeArray } |
                Should -Throw '*Parameter set cannot be resolved*'
        }
    }

    Context 'ById selector still works' {
        It 'supports -PolicyId with typed params' {
            New-PfbNfsExportRule -PolicyId 'pid-1' -Client 'x' -Confirm:$false -Array $fakeArray
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['policy_ids'] -eq 'pid-1' -and $Body['client'] -eq 'x'
            }
        }
    }
}
