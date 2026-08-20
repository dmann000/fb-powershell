#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'New-PfbS3ExportRule - typed body/query params (#31)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'existing -Attributes path still works' {
        It 'POSTs with -Attributes hashtable unchanged' {
            New-PfbS3ExportRule -PolicyName 's3-export-01' -Name 'rule-1' -Attributes @{ effect = 'allow' } -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Endpoint -eq 's3-export-policies/rules' -and
                $QueryParams['policy_names'] -eq 's3-export-01' -and
                $Body['effect'] -eq 'allow'
            }
        }
    }

    Context 'required -Name query parameter (the endpoint requires the new rule name)' {
        It 'sends -Name as a joined names query param' {
            New-PfbS3ExportRule -PolicyName 'p1' -Name 'rule-1' -Confirm:$false -Array $fakeArray
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter { $QueryParams['names'] -eq 'rule-1' }
        }

        It 'throws before any API call when -Name is not supplied' {
            { New-PfbS3ExportRule -PolicyName 'p1' -Effect 'allow' -Confirm:$false -Array $fakeArray } | Should -Throw
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
        }
    }

    Context 'typed body parameters - arrays (constraint 2: explicit @())' {
        It 'sends -Actions as actions' {
            New-PfbS3ExportRule -PolicyName 'p1' -Name 'rule-1' -Actions @('s3:GetObject', 's3:PutObject') -Confirm:$false -Array $fakeArray
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['actions'].Count -eq 2 -and $Body['actions'][0] -eq 's3:GetObject'
            }
        }

        It 'sends an explicit empty -Actions @()' {
            New-PfbS3ExportRule -PolicyName 'p1' -Name 'rule-1' -Actions @() -Confirm:$false -Array $fakeArray
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('actions') -and $Body['actions'].Count -eq 0
            }
        }

        It 'sends -Resources as resources' {
            New-PfbS3ExportRule -PolicyName 'p1' -Name 'rule-1' -Resources @('bucket1/*') -Confirm:$false -Array $fakeArray
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['resources'].Count -eq 1 -and $Body['resources'][0] -eq 'bucket1/*'
            }
        }

        It 'sends an explicit empty -Resources @()' {
            New-PfbS3ExportRule -PolicyName 'p1' -Name 'rule-1' -Resources @() -Confirm:$false -Array $fakeArray
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('resources') -and $Body['resources'].Count -eq 0
            }
        }
    }

    Context 'typed body parameter - effect string' {
        It 'sends -Effect as effect' {
            New-PfbS3ExportRule -PolicyName 'p1' -Name 'rule-1' -Effect 'allow' -Confirm:$false -Array $fakeArray
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter { $Body['effect'] -eq 'allow' }
        }
    }

    Context 'parameter set mutual exclusion' {
        It 'rejects mixing a typed body parameter with -Attributes' {
            { New-PfbS3ExportRule -PolicyName 'p1' -Name 'rule-1' -Effect 'allow' -Attributes @{ effect = 'allow' } -Confirm:$false -Array $fakeArray } |
                Should -Throw '*Parameter set cannot be resolved*'
        }
    }

    Context 'ById selector still works' {
        It 'supports -PolicyId with typed params' {
            New-PfbS3ExportRule -PolicyId 'pid-1' -Name 'rule-1' -Effect 'allow' -Confirm:$false -Array $fakeArray
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['policy_ids'] -eq 'pid-1' -and $Body['effect'] -eq 'allow'
            }
        }
    }
}
