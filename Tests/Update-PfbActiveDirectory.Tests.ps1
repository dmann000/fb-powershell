#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Update-PfbActiveDirectory - typed body parameters (#31)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'typed parameters build the body' {
        It 'sends ca_certificate and ca_certificate_group as name-reference objects' {
            Update-PfbActiveDirectory -Name 'ad1' -CaCertificate 'ca1' -CaCertificateGroup 'cagrp1' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Endpoint -eq 'active-directory' -and
                $QueryParams['names'] -eq 'ad1' -and
                $Body['ca_certificate'].name -eq 'ca1' -and
                $Body['ca_certificate_group'].name -eq 'cagrp1'
            }
        }

        It 'sends join_ou as a plain body field' {
            Update-PfbActiveDirectory -Name 'ad1' -JoinOu 'OU=Storage,DC=corp,DC=example,DC=com' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['join_ou'] -eq 'OU=Storage,DC=corp,DC=example,DC=com'
            }
        }

        It 'sends directory_servers, fqdns, global_catalog_servers, kerberos_servers, and service_principal_names as arrays' {
            Update-PfbActiveDirectory -Name 'ad1' `
                -DirectoryServers 'dc1.corp.example.com','dc2.corp.example.com' `
                -Fqdns 'fb.corp.example.com' `
                -GlobalCatalogServers 'gc1.corp.example.com' `
                -KerberosServers 'kdc1.corp.example.com' `
                -ServicePrincipalNames 'HOST/fb1','HOST/fb2' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                @($Body['directory_servers']).Count -eq 2 -and $Body['directory_servers'][0] -eq 'dc1.corp.example.com' -and
                @($Body['fqdns']) -contains 'fb.corp.example.com' -and
                @($Body['global_catalog_servers']) -contains 'gc1.corp.example.com' -and
                @($Body['kerberos_servers']) -contains 'kdc1.corp.example.com' -and
                @($Body['service_principal_names']).Count -eq 2
            }
        }

        It 'sends an EMPTY array for -DirectoryServers @() so a list can be cleared' {
            Update-PfbActiveDirectory -Name 'ad1' -DirectoryServers @() -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('directory_servers') -and @($Body['directory_servers']).Count -eq 0
            }
        }

        It 'sends encryption_types from the fixed enum set' {
            Update-PfbActiveDirectory -Name 'ad1' -EncryptionTypes 'aes256-cts-hmac-sha1-96','arcfour-hmac' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                @($Body['encryption_types']) -contains 'aes256-cts-hmac-sha1-96' -and
                @($Body['encryption_types']) -contains 'arcfour-hmac'
            }
        }

        It 'rejects an -EncryptionTypes value outside the fixed enum set' {
            { Update-PfbActiveDirectory -Name 'ad1' -EncryptionTypes 'des-cbc-crc' `
                -Confirm:$false -Array $fakeArray -ErrorAction Stop } | Should -Throw
        }

        It 'omits every body key when no typed body parameter is supplied' {
            Update-PfbActiveDirectory -Name 'ad1' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.Count -eq 0
            }
        }

        It 'targets the configuration by id when -Id is used' {
            Update-PfbActiveDirectory -Id 'ad-1' -JoinOu 'OU=Storage' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['ids'] -eq 'ad-1' -and -not $QueryParams.ContainsKey('names')
            }
        }
    }

    Context '-Attributes remains supported and is mutually exclusive' {
        It 'still sends a raw -Attributes body' {
            Update-PfbActiveDirectory -Name 'ad1' -Attributes @{ join_ou = 'OU=Raw' } `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['join_ou'] -eq 'OU=Raw'
            }
        }

        It 'rejects -Attributes combined with a typed parameter at bind time' {
            { Update-PfbActiveDirectory -Name 'ad1' -JoinOu 'OU=X' -Attributes @{ join_ou = 'OU=Y' } `
                -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'
        }
    }

    Context 'constraint compliance' {
        It 'puts no ValidateSet on -<Parameter> (constraint 3, no spec enum)' -ForEach @(
            @{ Parameter = 'CaCertificate' }
            @{ Parameter = 'CaCertificateGroup' }
            @{ Parameter = 'DirectoryServers' }
            @{ Parameter = 'Fqdns' }
            @{ Parameter = 'GlobalCatalogServers' }
            @{ Parameter = 'JoinOu' }
            @{ Parameter = 'KerberosServers' }
            @{ Parameter = 'ServicePrincipalNames' }
        ) {
            $attrs = (Get-Command Update-PfbActiveDirectory).Parameters[$Parameter].Attributes
            @($attrs | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).Count |
                Should -Be 0
        }

        It 'puts the exact fixed ValidateSet on -EncryptionTypes' {
            $attrs = (Get-Command Update-PfbActiveDirectory).Parameters['EncryptionTypes'].Attributes
            $validateSet = $attrs | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet.ValidValues | Should -Be @('aes256-cts-hmac-sha1-96', 'aes128-cts-hmac-sha1-96', 'arcfour-hmac')
        }

        It 'exposes every settable body field the endpoint accepts' {
            $keys = (Get-Command Update-PfbActiveDirectory).Parameters.Keys
            foreach ($p in 'CaCertificate','CaCertificateGroup','DirectoryServers','EncryptionTypes','Fqdns',
                           'GlobalCatalogServers','JoinOu','KerberosServers','ServicePrincipalNames') {
                $keys | Should -Contain $p
            }
        }
    }
}
