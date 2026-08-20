#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Update-PfbSubnet - typed body parameters (#31)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'pre-existing typed parameters now guarded by ContainsKey and in the Individual set (constraint 16 fix)' {
        It 'sends prefix, gateway and mtu as body fields' {
            Update-PfbSubnet -Name 'subnet1' -Prefix '10.0.0.0/24' -Gateway '10.0.0.254' -Mtu 9000 `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Endpoint -eq 'subnets' -and
                $QueryParams['names'] -eq 'subnet1' -and
                $Body['prefix'] -eq '10.0.0.0/24' -and
                $Body['gateway'] -eq '10.0.0.254' -and
                $Body['mtu'] -eq 9000
            }
        }

        It 'sends an explicit -Mtu 0 rather than dropping it (constraint 2, integer field, was -gt 0)' {
            Update-PfbSubnet -Name 'subnet1' -Mtu 0 -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('mtu') -and $Body['mtu'] -eq 0
            }
        }

        It 'rejects -Prefix combined with -Attributes at bind time (real bug: was silently discarding -Prefix before)' {
            { Update-PfbSubnet -Name 'subnet1' -Prefix '10.0.0.0/24' -Attributes @{ mtu = 9000 } `
                -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'
        }
    }

    Context 'new typed body parameters (missing body properties)' {
        It 'builds link_aggregation_group as a name-reference object (constraint 8a)' {
            Update-PfbSubnet -Name 'subnet1' -LinkAggregationGroup 'lag1' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['link_aggregation_group'].name -eq 'lag1'
            }
        }

        It 'sends vlan as a body field' {
            Update-PfbSubnet -Name 'subnet1' -Vlan 100 -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['vlan'] -eq 100
            }
        }

        It 'sends an explicit -Vlan 0 rather than dropping it (constraint 2, integer field)' {
            Update-PfbSubnet -Name 'subnet1' -Vlan 0 -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('vlan') -and $Body['vlan'] -eq 0
            }
        }
    }

    Context '-Attributes remains supported and is mutually exclusive' {
        It 'still sends a raw -Attributes body' {
            Update-PfbSubnet -Name 'subnet1' -Attributes @{ mtu = 1500 } -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['mtu'] -eq 1500
            }
        }

        It 'targets the subnet by id when -Id is used' {
            Update-PfbSubnet -Id 'subnet-1' -Attributes @{ mtu = 1500 } -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['ids'] -eq 'subnet-1' -and -not $QueryParams.ContainsKey('names')
            }
        }
    }

    Context 'constraint compliance' {
        It 'puts no ValidateSet on any new parameter (constraint 3, no spec enum)' -ForEach @(
            @{ Parameter = 'LinkAggregationGroup' }
            @{ Parameter = 'Vlan' }
        ) {
            $attrs = (Get-Command Update-PfbSubnet).Parameters[$Parameter].Attributes
            @($attrs | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).Count |
                Should -Be 0
        }

        It 'exposes every settable body field the endpoint accepts' {
            $keys = (Get-Command Update-PfbSubnet).Parameters.Keys
            foreach ($p in 'Prefix','Gateway','Mtu','LinkAggregationGroup','Vlan') {
                $keys | Should -Contain $p
            }
        }

        It 'omits every body key when no typed body parameter is supplied (constraint 19, empty body permitted)' {
            Update-PfbSubnet -Name 'subnet1' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.Count -eq 0
            }
        }
    }
}
