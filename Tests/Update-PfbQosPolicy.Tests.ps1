#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Update-PfbQosPolicy - typed body parameters (#31)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'typed parameters build the body' {
        It 'sends enabled as a body field (ContainsKey semantics, not truthiness)' {
            Update-PfbQosPolicy -Name 'qos-gold' -Enabled $false -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Endpoint -eq 'qos-policies' -and
                $QueryParams['names'] -eq 'qos-gold' -and
                $Body.ContainsKey('enabled') -and $Body['enabled'] -eq $false
            }
        }

        It 'builds location as a name-reference object' {
            Update-PfbQosPolicy -Name 'qos-gold' -Location 'array-1' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['location'].name -eq 'array-1'
            }
        }

        It 'sends max_total_bytes_per_sec as a body field' {
            Update-PfbQosPolicy -Name 'qos-gold' -MaxTotalBytesPerSec 2147483648 -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['max_total_bytes_per_sec'] -eq 2147483648
            }
        }

        It 'sends an explicit -MaxTotalBytesPerSec 0 rather than dropping it (constraint 2: 0 means unlimited)' {
            Update-PfbQosPolicy -Name 'qos-gold' -MaxTotalBytesPerSec 0 -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('max_total_bytes_per_sec') -and $Body['max_total_bytes_per_sec'] -eq 0
            }
        }

        It 'sends an explicit -MaxTotalOpsPerSec 0 rather than dropping it (constraint 2: 0 means unlimited)' {
            Update-PfbQosPolicy -Name 'qos-gold' -MaxTotalOpsPerSec 0 -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('max_total_ops_per_sec') -and $Body['max_total_ops_per_sec'] -eq 0
            }
        }

        It 'omits max_total_ops_per_sec entirely when not supplied' {
            Update-PfbQosPolicy -Name 'qos-gold' -Enabled $true -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                -not $Body.ContainsKey('max_total_ops_per_sec')
            }
        }

        It 'sends -NewName as the name body field (rename exception, not -QosPolicyName)' {
            Update-PfbQosPolicy -Name 'qos-gold' -NewName 'qos-platinum' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['name'] -eq 'qos-platinum'
            }
        }

        It 'omits every body key when no typed body parameter is supplied' {
            Update-PfbQosPolicy -Name 'qos-gold' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.Count -eq 0
            }
        }

        It 'targets the policy by id when -Id is used' {
            Update-PfbQosPolicy -Id 'policy-1' -Enabled $true -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['ids'] -eq 'policy-1' -and -not $QueryParams.ContainsKey('names')
            }
        }
    }

    Context '-Attributes remains supported and is mutually exclusive' {
        It 'still sends a raw -Attributes body' {
            Update-PfbQosPolicy -Name 'qos-gold' -Attributes @{ enabled = $true } -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['enabled'] -eq $true
            }
        }

        It 'rejects -Attributes combined with a typed parameter at bind time' {
            { Update-PfbQosPolicy -Name 'qos-gold' -Enabled $true -Attributes @{ enabled = $false } `
                -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'
        }
    }

    Context 'read-only fields are never exposed (constraint 11)' {
        It 'has no -IsLocal or -PolicyType parameter' {
            $keys = (Get-Command Update-PfbQosPolicy).Parameters.Keys
            $keys | Should -Not -Contain 'IsLocal'
            $keys | Should -Not -Contain 'PolicyType'
        }
    }

    Context 'constraint compliance' {
        It 'puts no ValidateSet on -<Parameter> (constraint 3, no spec enum)' -ForEach @(
            @{ Parameter = 'Enabled' }
            @{ Parameter = 'Location' }
            @{ Parameter = 'MaxTotalBytesPerSec' }
            @{ Parameter = 'MaxTotalOpsPerSec' }
            @{ Parameter = 'NewName' }
        ) {
            $attrs = (Get-Command Update-PfbQosPolicy).Parameters[$Parameter].Attributes
            @($attrs | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).Count |
                Should -Be 0
        }

        It 'exposes every settable body field the endpoint accepts' {
            $keys = (Get-Command Update-PfbQosPolicy).Parameters.Keys
            foreach ($p in 'Enabled','Location','MaxTotalBytesPerSec','MaxTotalOpsPerSec','NewName') {
                $keys | Should -Contain $p
            }
        }
    }
}
