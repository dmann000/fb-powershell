#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Update-PfbArrayConnection - typed body parameters (#31)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'typed parameters build the body' {
        It 'sends management_address as a body field' {
            Update-PfbArrayConnection -Name 'remote-fb-dc2' -ManagementAddress '10.0.2.101' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Endpoint -eq 'array-connections' -and
                $QueryParams['names'] -eq 'remote-fb-dc2' -and
                $Body['management_address'] -eq '10.0.2.101'
            }
        }

        It 'sends replication_addresses as an array (constraint 7 shape 2)' {
            Update-PfbArrayConnection -Name 'remote-fb-dr' -ReplicationAddresses '10.0.3.101','10.0.3.102' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                @($Body['replication_addresses']).Count -eq 2 -and
                @($Body['replication_addresses'])[1] -eq '10.0.3.102'
            }
        }

        It 'sends an EMPTY array for -ReplicationAddresses @() so the list can be cleared' {
            Update-PfbArrayConnection -Name 'remote-fb-dr' -ReplicationAddresses @() `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('replication_addresses') -and
                @($Body['replication_addresses']).Count -eq 0
            }
        }

        It 'sends an explicit -Encrypted:$false (ContainsKey semantics, not truthiness)' {
            Update-PfbArrayConnection -Name 'remote-fb-dc2' -Encrypted $false -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('encrypted') -and $Body['encrypted'] -eq $false
            }
        }

        It 'omits encrypted entirely when not supplied' {
            Update-PfbArrayConnection -Name 'remote-fb-dc2' -ManagementAddress '10.0.2.101' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                -not $Body.ContainsKey('encrypted')
            }
        }

        It 'builds ca_certificate_group as a name-reference object (constraint 8a)' {
            Update-PfbArrayConnection -Name 'remote-fb-dc2' -CaCertificateGroup 'my-certs' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['ca_certificate_group'].name -eq 'my-certs'
            }
        }

        It 'builds remote as a name-reference object (constraint 8a)' {
            Update-PfbArrayConnection -Name 'remote-fb-dc2' -Remote 'remote-fb' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['remote'].name -eq 'remote-fb'
            }
        }

        It 'passes throttle straight through as a composite hashtable (constraint 8c)' {
            Update-PfbArrayConnection -Name 'remote-fb-dc2' -Throttle @{ window_limit = 2097152 } `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['throttle']['window_limit'] -eq 2097152
            }
        }

        It 'omits every body key when no typed body parameter is supplied' {
            Update-PfbArrayConnection -Name 'remote-fb-dc2' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.Count -eq 0
            }
        }

        It 'targets the connection by id when -Id is used' {
            Update-PfbArrayConnection -Id 'conn-1' -ManagementAddress '10.0.2.101' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['ids'] -eq 'conn-1' -and -not $QueryParams.ContainsKey('names')
            }
        }
    }

    Context 'new query parameters (constraint 17 -- declared bare, not in the Individual sets)' {
        It 'sends remote_ids as a bare query parameter alongside -Attributes' {
            Update-PfbArrayConnection -Name 'remote-fb-dc2' -Attributes @{ management_address = '10.0.2.101' } `
                -RemoteId 'remote-1' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['remote_ids'] -eq 'remote-1'
            }
        }

        It 'sends remote_names as a bare query parameter alongside a typed parameter' {
            Update-PfbArrayConnection -Name 'remote-fb-dc2' -ManagementAddress '10.0.2.101' `
                -RemoteName 'remote-array' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['remote_names'] -eq 'remote-array'
            }
        }

        It 'omits remote_ids/remote_names entirely when not supplied' {
            Update-PfbArrayConnection -Name 'remote-fb-dc2' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                -not $QueryParams.ContainsKey('remote_ids') -and -not $QueryParams.ContainsKey('remote_names')
            }
        }
    }

    Context '-Attributes remains supported and is mutually exclusive' {
        It 'still sends a raw -Attributes body' {
            Update-PfbArrayConnection -Name 'remote-fb-dc2' -Attributes @{ management_address = '10.0.2.101' } `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['management_address'] -eq '10.0.2.101'
            }
        }

        It 'rejects -Attributes combined with a typed parameter at bind time' {
            { Update-PfbArrayConnection -Name 'remote-fb-dc2' -ManagementAddress '10.0.2.101' `
                -Attributes @{ management_address = 'y' } -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'
        }
    }

    Context 'constraint compliance' {
        It 'puts no ValidateSet on -<Parameter> (constraint 3, no spec enum)' -ForEach @(
            @{ Parameter = 'ManagementAddress' }
            @{ Parameter = 'ReplicationAddresses' }
            @{ Parameter = 'CaCertificateGroup' }
            @{ Parameter = 'Encrypted' }
            @{ Parameter = 'Remote' }
            @{ Parameter = 'Throttle' }
            @{ Parameter = 'RemoteId' }
            @{ Parameter = 'RemoteName' }
        ) {
            $attrs = (Get-Command Update-PfbArrayConnection).Parameters[$Parameter].Attributes
            @($attrs | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).Count |
                Should -Be 0
        }
    }
}
