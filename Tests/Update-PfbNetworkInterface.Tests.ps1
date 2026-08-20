#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Update-PfbNetworkInterface - typed body parameters (#31)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'pre-existing -Address now guarded by ContainsKey and in the Individual set (constraint 16 fix)' {
        It 'sends address as a body field' {
            Update-PfbNetworkInterface -Name 'vir0' -Address '10.0.0.101' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Endpoint -eq 'network-interfaces' -and
                $QueryParams['names'] -eq 'vir0' -and
                $Body['address'] -eq '10.0.0.101'
            }
        }

        It 'sends an EMPTY string for -Address "" rather than dropping the key' {
            Update-PfbNetworkInterface -Name 'vir0' -Address '' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('address') -and $Body['address'] -eq ''
            }
        }

        It 'rejects -Address combined with -Attributes at bind time (real bug: was silently discarding -Address before)' {
            { Update-PfbNetworkInterface -Name 'vir0' -Address '10.0.0.101' -Attributes @{ services = @('data') } `
                -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'
        }
    }

    Context 'new typed body parameters (missing body properties)' {
        It 'builds attached_servers as an array of name-reference objects (constraint 8b)' {
            Update-PfbNetworkInterface -Name 'vir0' -AttachedServers 'CH1.FM1', 'CH1.FM2' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['attached_servers'].Count -eq 2 -and
                $Body['attached_servers'][0].name -eq 'CH1.FM1' -and
                $Body['attached_servers'][1].name -eq 'CH1.FM2'
            }
        }

        It 'sends an EMPTY array for -AttachedServers @() so the list can be cleared' {
            Update-PfbNetworkInterface -Name 'vir0' -AttachedServers @() -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('attached_servers') -and @($Body['attached_servers']).Count -eq 0
            }
        }

        It 'sends an explicit -RdmaEnabled:$false (ContainsKey semantics, not truthiness)' {
            Update-PfbNetworkInterface -Name 'vir0' -RdmaEnabled $false -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('rdma_enabled') -and $Body['rdma_enabled'] -eq $false
            }
        }

        It 'omits rdma_enabled entirely when -RdmaEnabled is not supplied' {
            Update-PfbNetworkInterface -Name 'vir0' -Address '10.0.0.101' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                -not $Body.ContainsKey('rdma_enabled')
            }
        }

        It 'sends services as a plain string array' {
            Update-PfbNetworkInterface -Name 'vir0' -Services 'data', 'management' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                @($Body['services']) -join ',' -eq 'data,management'
            }
        }

        It 'sends an EMPTY array for -Services @() so the list can be cleared' {
            Update-PfbNetworkInterface -Name 'vir0' -Services @() -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('services') -and @($Body['services']).Count -eq 0
            }
        }
    }

    Context '-Attributes remains supported and is mutually exclusive' {
        It 'still sends a raw -Attributes body' {
            Update-PfbNetworkInterface -Name 'vir0' -Attributes @{ address = '10.0.0.99' } -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['address'] -eq '10.0.0.99'
            }
        }

        It 'targets the interface by id when -Id is used' {
            Update-PfbNetworkInterface -Id 'iface-1' -Attributes @{ address = '10.0.0.99' } -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['ids'] -eq 'iface-1' -and -not $QueryParams.ContainsKey('names')
            }
        }
    }

    Context 'constraint compliance' {
        It 'puts no ValidateSet on any new parameter (constraint 3, no spec enum)' -ForEach @(
            @{ Parameter = 'AttachedServers' }
            @{ Parameter = 'RdmaEnabled' }
            @{ Parameter = 'Services' }
        ) {
            $attrs = (Get-Command Update-PfbNetworkInterface).Parameters[$Parameter].Attributes
            @($attrs | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).Count |
                Should -Be 0
        }

        It 'exposes every settable body field the endpoint accepts' {
            $keys = (Get-Command Update-PfbNetworkInterface).Parameters.Keys
            foreach ($p in 'Address','AttachedServers','RdmaEnabled','Services') {
                $keys | Should -Contain $p
            }
        }

        It 'omits every body key when no typed body parameter is supplied (constraint 19, empty body permitted)' {
            Update-PfbNetworkInterface -Name 'vir0' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.Count -eq 0
            }
        }
    }
}
