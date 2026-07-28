#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'New-PfbArrayConnection - typed body parameters (#31)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'pre-existing typed parameters (constraint 16 -- were in NO parameter set)' {
        It 'sends management_address, replication_addresses and connection_key together' {
            New-PfbArrayConnection -ManagementAddress '10.0.2.100' -ReplicationAddress '10.0.3.100' `
                -ConnectionKey 'key-123' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Endpoint -eq 'array-connections' -and
                $Body['management_address'] -eq '10.0.2.100' -and
                @($Body['replication_addresses'])[0] -eq '10.0.3.100' -and
                $Body['connection_key'] -eq 'key-123'
            }
        }

        It 'no longer silently discards -ManagementAddress when combined with -Attributes (regression: was a silent override, now an ambiguous-set error)' {
            { New-PfbArrayConnection -ManagementAddress '10.0.2.100' -Attributes @{ connection_key = 'y' } `
                -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'
        }

        It 'accepts -ManagementAddress/-ReplicationAddress/-ConnectionKey positionally (whole-branch review finding I-1: adding a parameter set disables ALL implicit positional binding, so this must stay explicit)' {
            New-PfbArrayConnection '10.0.2.100' '10.0.3.100' 'key-123' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['management_address'] -eq '10.0.2.100' -and
                @($Body['replication_addresses'])[0] -eq '10.0.3.100' -and
                $Body['connection_key'] -eq 'key-123'
            }
        }

        It 'accepts -Attributes positionally' {
            New-PfbArrayConnection @{ management_address = '10.0.2.100'; connection_key = 'k' } -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['management_address'] -eq '10.0.2.100'
            }
        }
    }

    Context 'new typed parameters' {
        It 'sends encrypted as a body field (ContainsKey semantics, not truthiness)' {
            New-PfbArrayConnection -ManagementAddress '10.0.2.100' -ConnectionKey 'k' -Encrypted $false `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('encrypted') -and $Body['encrypted'] -eq $false
            }
        }

        It 'omits encrypted entirely when not supplied' {
            New-PfbArrayConnection -ManagementAddress '10.0.2.100' -ConnectionKey 'k' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                -not $Body.ContainsKey('encrypted')
            }
        }

        It 'builds ca_certificate_group as a name-reference object (constraint 8a, scalar reference)' {
            New-PfbArrayConnection -ManagementAddress '10.0.2.100' -ConnectionKey 'k' -CaCertificateGroup 'my-certs' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['ca_certificate_group'].name -eq 'my-certs'
            }
        }

        It 'builds remote as a name-reference object (constraint 8a, scalar reference)' {
            New-PfbArrayConnection -ManagementAddress '10.0.2.100' -ConnectionKey 'k' -Remote 'remote-fb' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['remote'].name -eq 'remote-fb'
            }
        }

        It 'passes throttle straight through as a composite hashtable (constraint 8c)' {
            New-PfbArrayConnection -ManagementAddress '10.0.2.100' -ConnectionKey 'k' `
                -Throttle @{ default_limit = 1073741824 } -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['throttle']['default_limit'] -eq 1073741824
            }
        }
    }

    Context '-Attributes remains supported and is mutually exclusive' {
        It 'still sends a raw -Attributes body' {
            New-PfbArrayConnection -Attributes @{ management_address = '10.0.2.100'; connection_key = 'k' } `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['management_address'] -eq '10.0.2.100'
            }
        }

        It 'rejects -Attributes combined with a typed parameter at bind time' {
            { New-PfbArrayConnection -ConnectionKey 'k' -Attributes @{ connection_key = 'y' } `
                -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'
        }
    }

    Context 'constraint compliance' {
        It 'puts no ValidateSet on -<Parameter> (constraint 3, no spec enum)' -ForEach @(
            @{ Parameter = 'ManagementAddress' }
            @{ Parameter = 'ReplicationAddress' }
            @{ Parameter = 'ConnectionKey' }
            @{ Parameter = 'CaCertificateGroup' }
            @{ Parameter = 'Encrypted' }
            @{ Parameter = 'Remote' }
            @{ Parameter = 'Throttle' }
        ) {
            $attrs = (Get-Command New-PfbArrayConnection).Parameters[$Parameter].Attributes
            @($attrs | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).Count |
                Should -Be 0
        }
    }
}
