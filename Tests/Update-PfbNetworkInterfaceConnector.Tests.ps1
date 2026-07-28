#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Update-PfbNetworkInterfaceConnector - typed body parameters (#31)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'typed parameters build the body' {
        It 'sends lane_speed and port_speed as body fields' {
            Update-PfbNetworkInterfaceConnector -Name 'CH1.FM1.ETH1' -LaneSpeed 10000000000 -PortSpeed 40000000000 `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Endpoint -eq 'network-interfaces/connectors' -and
                $QueryParams['names'] -eq 'CH1.FM1.ETH1' -and
                $Body['lane_speed'] -eq 10000000000 -and
                $Body['port_speed'] -eq 40000000000
            }
        }

        It 'sends lanes_per_port and port_count as body fields' {
            Update-PfbNetworkInterfaceConnector -Name 'CH1.FM1.ETH1' -LanesPerPort 4 -PortCount 1 `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['lanes_per_port'] -eq 4 -and $Body['port_count'] -eq 1
            }
        }

        It 'sends an explicit -LaneSpeed 0 rather than dropping it (constraint 2, integer field)' {
            Update-PfbNetworkInterfaceConnector -Name 'CH1.FM1.ETH1' -LaneSpeed 0 -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('lane_speed') -and $Body['lane_speed'] -eq 0
            }
        }

        It 'sends an explicit -PortCount 0 rather than dropping it (constraint 2, integer field)' {
            Update-PfbNetworkInterfaceConnector -Name 'CH1.FM1.ETH1' -PortCount 0 -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('port_count') -and $Body['port_count'] -eq 0
            }
        }

        It 'omits lane_speed entirely when -LaneSpeed is not supplied' {
            Update-PfbNetworkInterfaceConnector -Name 'CH1.FM1.ETH1' -PortSpeed 1 -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                -not $Body.ContainsKey('lane_speed')
            }
        }

        It 'omits every body key when no typed body parameter is supplied (constraint 19, empty body permitted)' {
            Update-PfbNetworkInterfaceConnector -Name 'CH1.FM1.ETH1' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.Count -eq 0
            }
        }

        It 'targets the connector by id when -Id is used' {
            Update-PfbNetworkInterfaceConnector -Id 'conn-1' -LaneSpeed 10000000000 -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['ids'] -eq 'conn-1' -and -not $QueryParams.ContainsKey('names')
            }
        }
    }

    Context '-Attributes remains supported and is mutually exclusive' {
        It 'still sends a raw -Attributes body' {
            Update-PfbNetworkInterfaceConnector -Name 'CH1.FM1.ETH1' -Attributes @{ port_speed = 40000000000 } `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['port_speed'] -eq 40000000000
            }
        }

        It 'rejects -Attributes combined with a typed parameter at bind time' {
            { Update-PfbNetworkInterfaceConnector -Name 'CH1.FM1.ETH1' -LaneSpeed 1 -Attributes @{ lane_speed = 2 } `
                -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'
        }
    }

    Context 'constraint compliance' {
        It 'puts no ValidateSet on any new parameter (constraint 3, no spec enum)' -ForEach @(
            @{ Parameter = 'LaneSpeed' }
            @{ Parameter = 'LanesPerPort' }
            @{ Parameter = 'PortCount' }
            @{ Parameter = 'PortSpeed' }
        ) {
            $attrs = (Get-Command Update-PfbNetworkInterfaceConnector).Parameters[$Parameter].Attributes
            @($attrs | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).Count |
                Should -Be 0
        }

        It 'exposes every settable body field the endpoint accepts' {
            $keys = (Get-Command Update-PfbNetworkInterfaceConnector).Parameters.Keys
            foreach ($p in 'LaneSpeed','LanesPerPort','PortCount','PortSpeed') {
                $keys | Should -Contain $p
            }
        }
    }
}
