#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Update-PfbLag - typed body parameters (#31)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'typed parameters build the body' {
        It 'builds ports as name-reference objects' {
            Update-PfbLag -Name 'lag1' -Ports 'CH1.FM1.ETH1', 'CH1.FM1.ETH3' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Endpoint -eq 'link-aggregation-groups' -and
                $QueryParams['names'] -eq 'lag1' -and
                $Body['ports'].Count -eq 2 -and
                $Body['ports'][0].name -eq 'CH1.FM1.ETH1' -and
                $Body['ports'][1].name -eq 'CH1.FM1.ETH3'
            }
        }

        It 'builds add_ports as name-reference objects' {
            Update-PfbLag -Name 'lag1' -AddPorts 'CH1.FM1.ETH5' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['add_ports'].Count -eq 1 -and $Body['add_ports'][0].name -eq 'CH1.FM1.ETH5'
            }
        }

        It 'builds remove_ports as name-reference objects' {
            Update-PfbLag -Name 'lag1' -RemovePorts 'CH1.FM1.ETH5' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['remove_ports'].Count -eq 1 -and $Body['remove_ports'][0].name -eq 'CH1.FM1.ETH5'
            }
        }

        It 'sends an EMPTY array for -Ports @() so a list can be cleared (constraint 2)' {
            Update-PfbLag -Name 'lag1' -Ports @() -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('ports') -and @($Body['ports']).Count -eq 0
            }
        }

        It 'omits every body key when no typed body parameter is supplied' {
            Update-PfbLag -Name 'lag1' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.Count -eq 0
            }
        }

        It 'targets the LAG by id when -Id is used' {
            Update-PfbLag -Id 'lag-1' -Ports 'CH1.FM1.ETH1' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['ids'] -eq 'lag-1' -and -not $QueryParams.ContainsKey('names')
            }
        }
    }

    Context '-Attributes remains supported and is mutually exclusive' {
        It 'still sends a raw -Attributes body' {
            Update-PfbLag -Name 'lag1' -Attributes @{ lacp_mode = 'passive' } `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['lacp_mode'] -eq 'passive'
            }
        }

        It 'rejects -Attributes combined with a typed parameter at bind time' {
            { Update-PfbLag -Name 'lag1' -Ports 'CH1.FM1.ETH1' -Attributes @{ ports = @() } `
                -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'
        }
    }
}
