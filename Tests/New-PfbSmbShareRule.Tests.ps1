#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'New-PfbSmbShareRule - typed body params (#31)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'existing -Attributes path still works' {
        It 'POSTs with -Attributes hashtable unchanged' {
            New-PfbSmbShareRule -PolicyName 'smb-share-01' -Attributes @{ principal = 'Everyone'; change = 'allow' } -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Endpoint -eq 'smb-share-policies/rules' -and
                $QueryParams['policy_names'] -eq 'smb-share-01' -and
                $Body['principal'] -eq 'Everyone' -and $Body['change'] -eq 'allow'
            }
        }
    }

    Context 'typed body parameters' {
        It 'sends -Principal as principal' {
            New-PfbSmbShareRule -PolicyName 'p1' -Principal 'DOMAIN\Admins' -Confirm:$false -Array $fakeArray
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter { $Body['principal'] -eq 'DOMAIN\Admins' }
        }

        It 'sends -Change as change' {
            New-PfbSmbShareRule -PolicyName 'p1' -Change 'allow' -Confirm:$false -Array $fakeArray
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter { $Body['change'] -eq 'allow' }
        }

        It 'rejects a -Change value outside the enum' {
            { New-PfbSmbShareRule -PolicyName 'p1' -Change 'bogus' -Confirm:$false -Array $fakeArray } | Should -Throw
        }

        It 'sends -FullControl as full_control' {
            New-PfbSmbShareRule -PolicyName 'p1' -FullControl 'deny' -Confirm:$false -Array $fakeArray
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter { $Body['full_control'] -eq 'deny' }
        }

        It 'rejects a -FullControl value outside the enum' {
            { New-PfbSmbShareRule -PolicyName 'p1' -FullControl 'bogus' -Confirm:$false -Array $fakeArray } | Should -Throw
        }

        It 'sends -Read as read' {
            New-PfbSmbShareRule -PolicyName 'p1' -Read 'allow' -Confirm:$false -Array $fakeArray
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter { $Body['read'] -eq 'allow' }
        }

        It 'rejects a -Read value outside the enum' {
            { New-PfbSmbShareRule -PolicyName 'p1' -Read 'bogus' -Confirm:$false -Array $fakeArray } | Should -Throw
        }

        It 'omits fields that were not supplied' {
            New-PfbSmbShareRule -PolicyName 'p1' -Principal 'x' -Confirm:$false -Array $fakeArray
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                -not $Body.ContainsKey('change') -and -not $Body.ContainsKey('full_control') -and -not $Body.ContainsKey('read')
            }
        }
    }

    Context 'parameter set mutual exclusion' {
        It 'rejects mixing a typed body parameter with -Attributes' {
            { New-PfbSmbShareRule -PolicyName 'p1' -Principal 'x' -Attributes @{ principal = 'x' } -Confirm:$false -Array $fakeArray } |
                Should -Throw '*Parameter set cannot be resolved*'
        }
    }

    Context 'ById selector still works' {
        It 'supports -PolicyId with typed params' {
            New-PfbSmbShareRule -PolicyId 'pid-1' -Principal 'x' -Confirm:$false -Array $fakeArray
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['policy_ids'] -eq 'pid-1' -and $Body['principal'] -eq 'x'
            }
        }
    }
}
