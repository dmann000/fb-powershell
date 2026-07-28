#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Update-PfbHardwareConnector - typed body parameters (#31)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'typed parameters build the body' {
        It 'sends lane_speed, lanes_per_port, port_count and port_speed as body fields' {
            Update-PfbHardwareConnector -Name 'CH1.FM1.ETH1' -LaneSpeed 25000000000 -LanesPerPort 4 `
                -PortCount 1 -PortSpeed 100000000000 -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Endpoint -eq 'hardware-connectors' -and
                $QueryParams['names'] -eq 'CH1.FM1.ETH1' -and
                $Body['lane_speed'] -eq 25000000000 -and
                $Body['lanes_per_port'] -eq 4 -and
                $Body['port_count'] -eq 1 -and
                $Body['port_speed'] -eq 100000000000
            }
        }

        It 'sends an explicit -LaneSpeed 0 rather than dropping it (constraint 2, integer field)' {
            Update-PfbHardwareConnector -Name 'CH1.FM1.ETH1' -LaneSpeed 0 -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('lane_speed') -and $Body['lane_speed'] -eq 0
            }
        }

        It 'sends an explicit -LanesPerPort 0 rather than dropping it (constraint 2, integer field)' {
            Update-PfbHardwareConnector -Name 'CH1.FM1.ETH1' -LanesPerPort 0 -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('lanes_per_port') -and $Body['lanes_per_port'] -eq 0
            }
        }

        It 'sends an explicit -PortCount 0 rather than dropping it (constraint 2, integer field)' {
            Update-PfbHardwareConnector -Name 'CH1.FM1.ETH1' -PortCount 0 -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('port_count') -and $Body['port_count'] -eq 0
            }
        }

        It 'sends an explicit -PortSpeed 0 rather than dropping it (constraint 2, integer field)' {
            Update-PfbHardwareConnector -Name 'CH1.FM1.ETH1' -PortSpeed 0 -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('port_speed') -and $Body['port_speed'] -eq 0
            }
        }

        It 'omits every body key when no typed body parameter is supplied' {
            Update-PfbHardwareConnector -Name 'CH1.FM1.ETH1' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.Count -eq 0
            }
        }

        It 'targets the connector by id when -Id is used' {
            Update-PfbHardwareConnector -Id 'conn-1' -PortSpeed 40000000000 -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['ids'] -eq 'conn-1' -and -not $QueryParams.ContainsKey('names')
            }
        }
    }

    Context '-Attributes remains supported and is mutually exclusive' {
        It 'still sends a raw -Attributes body' {
            Update-PfbHardwareConnector -Name 'CH1.FM1.ETH1' -Attributes @{ port_speed = 40000000000 } `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['port_speed'] -eq 40000000000
            }
        }

        It 'rejects -Attributes combined with a typed parameter at bind time' {
            { Update-PfbHardwareConnector -Name 'CH1.FM1.ETH1' -PortSpeed 40000000000 -Attributes @{ port_speed = 1 } `
                -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'
        }
    }

    Context 'constraint compliance' {
        It 'puts no ValidateSet on -<Parameter> (constraint 3, no spec enum)' -ForEach @(
            @{ Parameter = 'LaneSpeed' }
            @{ Parameter = 'LanesPerPort' }
            @{ Parameter = 'PortCount' }
            @{ Parameter = 'PortSpeed' }
        ) {
            $attrs = (Get-Command Update-PfbHardwareConnector).Parameters[$Parameter].Attributes
            @($attrs | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).Count |
                Should -Be 0
        }

        It 'does not expose any of the 4 read-only fields as parameters (constraint 11)' {
            $keys = (Get-Command Update-PfbHardwareConnector).Parameters.Keys
            foreach ($ro in 'ConnectorType','TransceiverType') {
                $keys | Should -Not -Contain $ro
            }
        }
    }
}
