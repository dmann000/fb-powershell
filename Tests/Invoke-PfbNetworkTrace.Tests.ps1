#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule
    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Invoke-PfbNetworkTrace' {
    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    It 'restricts -Method to the three real spec-documented values' {
        $attr = (Get-Command Invoke-PfbNetworkTrace).Parameters['Method'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
        $attr | Should -Not -BeNullOrEmpty
        $attr.ValidValues | Should -Be @('icmp', 'tcp', 'udp')
    }

    It 'rejects an invalid -Method value before making any API call' {
        { Invoke-PfbNetworkTrace -Destination '10.0.0.1' -Method 'bogus' -Array $fakeArray } | Should -Throw
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 0 -Exactly
    }

    It 'passes a valid -Method through to the query string' {
        Invoke-PfbNetworkTrace -Destination '10.0.0.1' -Method 'tcp' -Array $fakeArray
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'GET' -and $Endpoint -eq 'network-interfaces/trace' -and $QueryParams['method'] -eq 'tcp'
        }
    }

    It 'omits -Method from the query string when not specified' {
        Invoke-PfbNetworkTrace -Destination '10.0.0.1' -Array $fakeArray
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            -not $QueryParams.ContainsKey('method')
        }
    }
}
