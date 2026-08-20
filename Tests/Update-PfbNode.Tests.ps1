#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Update-PfbNode - typed body parameters (#31)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'typed parameters build the body' {
        It 'sends management_address and serial_number as body fields' {
            Update-PfbNode -Name 'CH1.FB1' -ManagementAddress '10.0.0.5' -SerialNumber 'SN12345' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Endpoint -eq 'nodes' -and
                $QueryParams['names'] -eq 'CH1.FB1' -and
                $Body['management_address'] -eq '10.0.0.5' -and
                $Body['serial_number'] -eq 'SN12345'
            }
        }

        It 'sends node_key as a body field' {
            Update-PfbNode -Name 'CH1.FB1' -NodeKey 'bootstrap-key' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['node_key'] -eq 'bootstrap-key'
            }
        }

        It 'sends -NewName as the name body field (exception: name -> -NewName)' {
            Update-PfbNode -Name 'CH1.FB1' -NewName 'CH1.FB1-renamed' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['name'] -eq 'CH1.FB1-renamed'
            }
        }

        It 'sends an EMPTY string for -ManagementAddress "" rather than dropping the key' {
            Update-PfbNode -Name 'CH1.FB1' -ManagementAddress '' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('management_address') -and $Body['management_address'] -eq ''
            }
        }

        It 'omits every body key when no typed body parameter is supplied (constraint 19, empty body permitted)' {
            Update-PfbNode -Name 'CH1.FB1' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.Count -eq 0
            }
        }

        It 'targets the node by id when -Id is used' {
            Update-PfbNode -Id 'node-1' -NodeKey 'k' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['ids'] -eq 'node-1' -and -not $QueryParams.ContainsKey('names')
            }
        }
    }

    Context '-Attributes remains supported and is mutually exclusive' {
        It 'still sends a raw -Attributes body' {
            Update-PfbNode -Name 'CH1.FB1' -Attributes @{ identify_enabled = $true } -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['identify_enabled'] -eq $true
            }
        }

        It 'rejects -Attributes combined with a typed parameter at bind time' {
            { Update-PfbNode -Name 'CH1.FB1' -NodeKey 'k' -Attributes @{ node_key = 'other' } `
                -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'
        }
    }

    Context 'constraint compliance' {
        It 'puts no ValidateSet on any new parameter (constraint 3, no spec enum)' -ForEach @(
            @{ Parameter = 'ManagementAddress' }
            @{ Parameter = 'NewName' }
            @{ Parameter = 'NodeKey' }
            @{ Parameter = 'SerialNumber' }
        ) {
            $attrs = (Get-Command Update-PfbNode).Parameters[$Parameter].Attributes
            @($attrs | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).Count |
                Should -Be 0
        }

        It 'exposes every settable body field the endpoint accepts' {
            $keys = (Get-Command Update-PfbNode).Parameters.Keys
            foreach ($p in 'ManagementAddress','NewName','NodeKey','SerialNumber') {
                $keys | Should -Contain $p
            }
        }
    }
}
