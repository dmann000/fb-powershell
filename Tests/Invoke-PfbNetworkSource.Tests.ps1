#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    Import-Module "$PSScriptRoot/../PureStorageFlashBladePowerShell.psd1" -Force
    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Network source query key (issue #119)' {
    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'Invoke-PfbNetworkPing' {
        It 'sends -SourceName under the declared query key source' {
            Invoke-PfbNetworkPing -Destination '10.0.0.1' -SourceName 'mgmt-vip' -Array $fakeArray
            Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'GET' -and
                $Endpoint -eq 'network-interfaces/ping' -and
                $QueryParams['source'] -eq 'mgmt-vip'
            }
        }

        It 'never sends the unknown query key source.name' {
            Invoke-PfbNetworkPing -Destination '10.0.0.1' -SourceName 'mgmt-vip' -Array $fakeArray
            Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
                -not $QueryParams.ContainsKey('source.name')
            }
        }

        It 'leaves destination, count and packet size unchanged' {
            Invoke-PfbNetworkPing -Destination '10.0.0.1' -SourceName 'mgmt-vip' -Count 5 -PacketSize 1400 -Array $fakeArray
            Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
                $QueryParams['destination'] -eq '10.0.0.1' -and
                $QueryParams['count'] -eq 5 -and
                $QueryParams['packet_size'] -eq 1400
            }
        }

        It 'omits the source key entirely when -SourceName is not supplied' {
            Invoke-PfbNetworkPing -Destination '10.0.0.1' -Array $fakeArray
            Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
                (-not $QueryParams.ContainsKey('source')) -and (-not $QueryParams.ContainsKey('source.name'))
            }
        }
    }

    Context 'Invoke-PfbNetworkTrace' {
        It 'sends -SourceName under the declared query key source' {
            Invoke-PfbNetworkTrace -Destination '10.0.0.1' -SourceName 'mgmt-vip' -Array $fakeArray
            Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'GET' -and
                $Endpoint -eq 'network-interfaces/trace' -and
                $QueryParams['source'] -eq 'mgmt-vip'
            }
        }

        It 'never sends the unknown query key source.name' {
            Invoke-PfbNetworkTrace -Destination '10.0.0.1' -SourceName 'mgmt-vip' -Array $fakeArray
            Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
                -not $QueryParams.ContainsKey('source.name')
            }
        }

        It 'leaves destination and trace method unchanged' {
            Invoke-PfbNetworkTrace -Destination '10.0.0.1' -SourceName 'mgmt-vip' -Method 'udp' -Array $fakeArray
            Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
                $QueryParams['destination'] -eq '10.0.0.1' -and
                $QueryParams['method'] -eq 'udp'
            }
        }

        It 'omits the source key entirely when -SourceName is not supplied' {
            Invoke-PfbNetworkTrace -Destination '10.0.0.1' -Array $fakeArray
            Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
                (-not $QueryParams.ContainsKey('source')) -and (-not $QueryParams.ContainsKey('source.name'))
            }
        }
    }
}
