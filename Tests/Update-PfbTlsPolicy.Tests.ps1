#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Update-PfbTlsPolicy - typed body parameters (#31)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'typed parameters build the body' {
        It 'builds appliance_certificate as a name-reference object' {
            Update-PfbTlsPolicy -Name 'tls-strict' -ApplianceCertificate 'cert-1' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Endpoint -eq 'tls-policies' -and
                $QueryParams['names'] -eq 'tls-strict' -and
                $Body['appliance_certificate'].name -eq 'cert-1'
            }
        }

        It 'sends an explicit -ClientCertificatesRequired:$false (ContainsKey semantics, not truthiness)' {
            Update-PfbTlsPolicy -Name 'tls-strict' -ClientCertificatesRequired $false -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('client_certificates_required') -and $Body['client_certificates_required'] -eq $false
            }
        }

        It 'sends disabled_tls_ciphers as a plain string array' {
            Update-PfbTlsPolicy -Name 'tls-strict' -DisabledTlsCiphers 'RC4','3DES' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                @($Body['disabled_tls_ciphers']).Count -eq 2 -and
                $Body['disabled_tls_ciphers'][0] -eq 'RC4' -and
                $Body['disabled_tls_ciphers'][1] -eq '3DES'
            }
        }

        It 'sends an EMPTY array for -DisabledTlsCiphers @() so a list can be cleared' {
            Update-PfbTlsPolicy -Name 'tls-strict' -DisabledTlsCiphers @() -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('disabled_tls_ciphers') -and
                @($Body['disabled_tls_ciphers']).Count -eq 0
            }
        }

        It 'sends enabled as a body field' {
            Update-PfbTlsPolicy -Name 'tls-strict' -Enabled $true -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['enabled'] -eq $true
            }
        }

        It 'sends enabled_tls_ciphers as a plain string array' {
            Update-PfbTlsPolicy -Name 'tls-strict' -EnabledTlsCiphers 'TLS_AES_128_GCM_SHA256' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                @($Body['enabled_tls_ciphers']).Count -eq 1 -and
                $Body['enabled_tls_ciphers'][0] -eq 'TLS_AES_128_GCM_SHA256'
            }
        }

        It 'sends an EMPTY array for -EnabledTlsCiphers @() so a list can be cleared' {
            Update-PfbTlsPolicy -Name 'tls-strict' -EnabledTlsCiphers @() -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('enabled_tls_ciphers') -and
                @($Body['enabled_tls_ciphers']).Count -eq 0
            }
        }

        It 'builds location as a name-reference object' {
            Update-PfbTlsPolicy -Name 'tls-strict' -Location 'array-1' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['location'].name -eq 'array-1'
            }
        }

        It 'sends min_tls_version as a body field' {
            Update-PfbTlsPolicy -Name 'tls-strict' -MinTlsVersion '1.3' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['min_tls_version'] -eq '1.3'
            }
        }

        It 'sends -NewName as the name body field (rename exception, not -TlsPolicyName)' {
            Update-PfbTlsPolicy -Name 'tls-strict' -NewName 'tls-modern' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['name'] -eq 'tls-modern'
            }
        }

        It 'builds trusted_client_certificate_authority as a name-reference object' {
            Update-PfbTlsPolicy -Name 'tls-strict' -TrustedClientCertificateAuthority 'ca-group-1' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['trusted_client_certificate_authority'].name -eq 'ca-group-1'
            }
        }

        It 'sends an explicit -VerifyClientCertificateTrust:$false (ContainsKey semantics, not truthiness)' {
            Update-PfbTlsPolicy -Name 'tls-strict' -VerifyClientCertificateTrust $false -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('verify_client_certificate_trust') -and $Body['verify_client_certificate_trust'] -eq $false
            }
        }

        It 'omits every body key when no typed body parameter is supplied' {
            Update-PfbTlsPolicy -Name 'tls-strict' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.Count -eq 0
            }
        }

        It 'targets the policy by id when -Id is used' {
            Update-PfbTlsPolicy -Id 'policy-1' -Enabled $true -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['ids'] -eq 'policy-1' -and -not $QueryParams.ContainsKey('names')
            }
        }
    }

    Context '-Attributes remains supported and is mutually exclusive' {
        It 'still sends a raw -Attributes body' {
            Update-PfbTlsPolicy -Name 'tls-strict' -Attributes @{ min_tls_version = '1.2' } -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['min_tls_version'] -eq '1.2'
            }
        }

        It 'rejects -Attributes combined with a typed parameter at bind time' {
            { Update-PfbTlsPolicy -Name 'tls-strict' -Enabled $true -Attributes @{ enabled = $false } `
                -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'
        }
    }

    Context 'read-only fields are never exposed (constraint 11)' {
        It 'has no -IsLocal or -PolicyType parameter' {
            $keys = (Get-Command Update-PfbTlsPolicy).Parameters.Keys
            $keys | Should -Not -Contain 'IsLocal'
            $keys | Should -Not -Contain 'PolicyType'
        }
    }

    Context 'constraint compliance' {
        It 'puts no ValidateSet on -<Parameter> (constraint 3, no spec enum)' -ForEach @(
            @{ Parameter = 'ApplianceCertificate' }
            @{ Parameter = 'ClientCertificatesRequired' }
            @{ Parameter = 'DisabledTlsCiphers' }
            @{ Parameter = 'Enabled' }
            @{ Parameter = 'EnabledTlsCiphers' }
            @{ Parameter = 'Location' }
            @{ Parameter = 'MinTlsVersion' }
            @{ Parameter = 'NewName' }
            @{ Parameter = 'TrustedClientCertificateAuthority' }
            @{ Parameter = 'VerifyClientCertificateTrust' }
        ) {
            $attrs = (Get-Command Update-PfbTlsPolicy).Parameters[$Parameter].Attributes
            @($attrs | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).Count |
                Should -Be 0
        }

        It 'exposes every settable body field the endpoint accepts' {
            $keys = (Get-Command Update-PfbTlsPolicy).Parameters.Keys
            foreach ($p in 'ApplianceCertificate','ClientCertificatesRequired','DisabledTlsCiphers','Enabled',
                           'EnabledTlsCiphers','Location','MinTlsVersion','NewName',
                           'TrustedClientCertificateAuthority','VerifyClientCertificateTrust') {
                $keys | Should -Contain $p
            }
        }
    }
}
