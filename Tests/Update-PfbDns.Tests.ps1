#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Update-PfbDns - typed body and query parameters (#31)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'pre-existing typed parameters now guarded by ContainsKey (constraint 16 fix)' {
        It 'sends domain and nameservers as body fields' {
            Update-PfbDns -Domain 'example.com' -Nameservers '10.0.0.1', '10.0.0.2' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Endpoint -eq 'dns' -and
                $Body['domain'] -eq 'example.com' -and
                @($Body['nameservers']).Count -eq 2
            }
        }

        It 'sends an EMPTY array for -Nameservers @() so the list can be cleared' {
            Update-PfbDns -Nameservers @() -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('nameservers') -and @($Body['nameservers']).Count -eq 0
            }
        }

        It 'accepts -Domain/-Nameservers positionally (whole-branch review finding I-1: adding a parameter set disables ALL implicit positional binding, so this must stay explicit)' {
            Update-PfbDns 'example.com' @('10.0.0.1', '10.0.0.2') -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['domain'] -eq 'example.com' -and @($Body['nameservers']).Count -eq 2
            }
        }

        It 'accepts -Attributes positionally' {
            Update-PfbDns @{ domain = 'example.com' } -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['domain'] -eq 'example.com'
            }
        }

        It 'rejects -Domain combined with -Attributes at bind time (moved into Individual set)' {
            { Update-PfbDns -Domain 'example.com' -Attributes @{ domain = 'other.com' } `
                -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'
        }
    }

    Context 'new typed body parameters (missing body properties)' {
        It 'sends ca_certificate as a name-reference object' {
            Update-PfbDns -CaCertificate 'my-ca-cert' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['ca_certificate'].name -eq 'my-ca-cert'
            }
        }

        It 'sends ca_certificate_group as a name-reference object' {
            Update-PfbDns -CaCertificateGroup 'my-ca-group' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['ca_certificate_group'].name -eq 'my-ca-group'
            }
        }

        It 'sends -NewName as the name body field (exception: name -> -NewName)' {
            Update-PfbDns -NewName 'mgmt-dns' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['name'] -eq 'mgmt-dns'
            }
        }

        It 'has no -Name body-rename parameter (only the -Name query selector exists)' {
            $params = (Get-Command Update-PfbDns).Parameters
            $params['Name'].ParameterType.Name | Should -Be 'String'
            $params.Keys | Should -Contain 'NewName'
        }

        It 'sends services as a plain string array' {
            Update-PfbDns -Services 'management', 'data' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                @($Body['services']) -join ',' -eq 'management,data'
            }
        }

        It 'sends an EMPTY array for -Services @() so the list can be cleared' {
            Update-PfbDns -Services @() -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('services') -and @($Body['services']).Count -eq 0
            }
        }

        It 'builds sources as an array of name-reference objects (constraint 8b)' {
            Update-PfbDns -Sources 'vir0', 'vir1' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['sources'].Count -eq 2 -and
                $Body['sources'][0].name -eq 'vir0' -and
                $Body['sources'][1].name -eq 'vir1'
            }
        }

        It 'sends an EMPTY array for -Sources @() so the list can be cleared' {
            Update-PfbDns -Sources @() -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('sources') -and @($Body['sources']).Count -eq 0
            }
        }
    }

    Context '-Name / -Id query parameters, declared bare (constraint 17)' {
        It 'sends -Name as names' {
            Update-PfbDns -Name 'mgmt-dns' -Domain 'example.com' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['names'] -eq 'mgmt-dns'
            }
        }

        It 'sends -Id as ids' {
            Update-PfbDns -Id 'dns-1' -Domain 'example.com' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['ids'] -eq 'dns-1'
            }
        }

        It 'combines -Name with -Attributes without a parameter-set conflict (bare, orthogonal to the body)' {
            Update-PfbDns -Name 'mgmt-dns' -Attributes @{ domain = 'example.com' } -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['names'] -eq 'mgmt-dns' -and $Body['domain'] -eq 'example.com'
            }
        }

        It 'omits names/ids when neither is supplied' {
            Update-PfbDns -Domain 'example.com' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                -not $QueryParams.ContainsKey('names') -and -not $QueryParams.ContainsKey('ids')
            }
        }
    }

    Context 'constraint compliance' {
        It 'puts no ValidateSet on any new parameter (constraint 3, no spec enum)' -ForEach @(
            @{ Parameter = 'CaCertificate' }
            @{ Parameter = 'CaCertificateGroup' }
            @{ Parameter = 'NewName' }
            @{ Parameter = 'Services' }
            @{ Parameter = 'Sources' }
        ) {
            $attrs = (Get-Command Update-PfbDns).Parameters[$Parameter].Attributes
            @($attrs | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).Count |
                Should -Be 0
        }

        It 'exposes every settable body field the endpoint accepts' {
            $keys = (Get-Command Update-PfbDns).Parameters.Keys
            foreach ($p in 'Domain','Nameservers','CaCertificate','CaCertificateGroup','NewName','Services','Sources') {
                $keys | Should -Contain $p
            }
        }

        It 'omits every body key when no typed body parameter is supplied (constraint 19, empty body permitted)' {
            Update-PfbDns -Name 'mgmt-dns' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.Count -eq 0
            }
        }
    }
}
