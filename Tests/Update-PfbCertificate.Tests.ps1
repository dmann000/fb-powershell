#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Update-PfbCertificate - typed body parameters (#31)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'typed parameters build the body' {
        It 'sends certificate, certificate_type, common_name and country as body fields' {
            Update-PfbCertificate -Name 'web-cert' -Certificate '-----BEGIN CERTIFICATE-----' `
                -CertificateType 'appliance' -CommonName 'www.example.com' -Country 'Canada' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Endpoint -eq 'certificates' -and
                $QueryParams['names'] -eq 'web-cert' -and
                $Body['certificate'] -eq '-----BEGIN CERTIFICATE-----' -and
                $Body['certificate_type'] -eq 'appliance' -and
                $Body['common_name'] -eq 'www.example.com' -and
                $Body['country'] -eq 'Canada'
            }
        }

        It 'sends email, intermediate_certificate, key_algorithm and locality as body fields' {
            Update-PfbCertificate -Name 'web-cert' -Email 'ops@example.com' `
                -IntermediateCertificate '-----BEGIN CHAIN-----' -KeyAlgorithm 'rsa' -Locality 'Toronto' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['email'] -eq 'ops@example.com' -and
                $Body['intermediate_certificate'] -eq '-----BEGIN CHAIN-----' -and
                $Body['key_algorithm'] -eq 'rsa' -and
                $Body['locality'] -eq 'Toronto'
            }
        }

        It 'sends organization, organizational_unit, passphrase, private_key and state as body fields' {
            Update-PfbCertificate -Name 'web-cert' -Organization 'Veridian Dynamics' `
                -OrganizationalUnit 'R&D' -Passphrase 's3cr3t' -PrivateKey '-----BEGIN PRIVATE KEY-----' `
                -State 'Ontario' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['organization'] -eq 'Veridian Dynamics' -and
                $Body['organizational_unit'] -eq 'R&D' -and
                $Body['passphrase'] -eq 's3cr3t' -and
                $Body['private_key'] -eq '-----BEGIN PRIVATE KEY-----' -and
                $Body['state'] -eq 'Ontario'
            }
        }

        It 'sends an explicit -Days 0 rather than dropping it (constraint 2, integer field)' {
            Update-PfbCertificate -Name 'web-cert' -Days 0 -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('days') -and $Body['days'] -eq 0
            }
        }

        It 'sends an explicit -KeySize 0 rather than dropping it (constraint 2, integer field)' {
            Update-PfbCertificate -Name 'web-cert' -KeySize 0 -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('key_size') -and $Body['key_size'] -eq 0
            }
        }

        It 'omits days and key_size entirely when not supplied' {
            Update-PfbCertificate -Name 'web-cert' -Certificate 'x' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                -not $Body.ContainsKey('days') -and -not $Body.ContainsKey('key_size')
            }
        }

        It 'sends subject_alternative_names as a plain string array' {
            Update-PfbCertificate -Name 'web-cert' -SubjectAlternativeNames 'alt1.example.com', 'alt2.example.com' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                @($Body['subject_alternative_names']).Count -eq 2 -and
                $Body['subject_alternative_names'][0] -eq 'alt1.example.com'
            }
        }

        It 'sends an EMPTY array for -SubjectAlternativeNames @() so a list can be cleared' {
            Update-PfbCertificate -Name 'web-cert' -SubjectAlternativeNames @() -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('subject_alternative_names') -and
                @($Body['subject_alternative_names']).Count -eq 0
            }
        }

        It 'omits every body key when no typed body parameter is supplied' {
            Update-PfbCertificate -Name 'web-cert' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.Count -eq 0
            }
        }

        It 'targets the certificate by id when -Id is used' {
            Update-PfbCertificate -Id 'cert-1' -Certificate 'x' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['ids'] -eq 'cert-1' -and -not $QueryParams.ContainsKey('names')
            }
        }
    }

    Context '-GenerateNewKey query parameter (constraint 17: bare, not in *Individual sets)' {
        It 'sends generate_new_key when supplied' {
            Update-PfbCertificate -Name 'web-cert' -GenerateNewKey $true -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams.ContainsKey('generate_new_key') -and $QueryParams['generate_new_key'] -eq $true
            }
        }

        It 'sends an explicit -GenerateNewKey:$false rather than dropping it' {
            Update-PfbCertificate -Name 'web-cert' -GenerateNewKey $false -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams.ContainsKey('generate_new_key') -and $QueryParams['generate_new_key'] -eq $false
            }
        }

        It 'omits generate_new_key entirely when not supplied' {
            Update-PfbCertificate -Name 'web-cert' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                -not $QueryParams.ContainsKey('generate_new_key')
            }
        }

        It 'is usable alongside -Attributes without an AmbiguousParameterSet error (query params are orthogonal to the body)' {
            { Update-PfbCertificate -Name 'web-cert' -Attributes @{ certificate = 'x' } -GenerateNewKey $true `
                -Confirm:$false -Array $fakeArray -ErrorAction Stop } | Should -Not -Throw

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['generate_new_key'] -eq $true -and $Body['certificate'] -eq 'x'
            }
        }
    }

    Context '-Attributes remains supported and is mutually exclusive' {
        It 'still sends a raw -Attributes body' {
            Update-PfbCertificate -Name 'web-cert' -Attributes @{ certificate = 'raw-cert' } `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['certificate'] -eq 'raw-cert'
            }
        }

        It 'rejects -Attributes combined with a typed parameter at bind time' {
            { Update-PfbCertificate -Name 'web-cert' -Certificate 'x' -Attributes @{ certificate = 'y' } `
                -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'
        }
    }

    Context 'read-only fields are never added as parameters (constraint 11)' {
        It 'has no -<Parameter> parameter' -ForEach @(
            @{ Parameter = 'IssuedBy' }
            @{ Parameter = 'IssuedTo' }
            @{ Parameter = 'Realms' }
            @{ Parameter = 'Status' }
            @{ Parameter = 'ValidFrom' }
            @{ Parameter = 'ValidTo' }
        ) {
            (Get-Command Update-PfbCertificate).Parameters.Keys | Should -Not -Contain $Parameter
        }
    }

    Context 'constraint compliance' {
        It 'puts ValidateSet on -CertificateType with exactly appliance,external in order' {
            $validateSet = (Get-Command Update-PfbCertificate).Parameters['CertificateType'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet.ValidValues | Should -Be @('appliance', 'external')
        }

        It 'puts no ValidateSet on -<Parameter> (constraint 3, no spec enum)' -ForEach @(
            @{ Parameter = 'Certificate' }
            @{ Parameter = 'CommonName' }
            @{ Parameter = 'Country' }
            @{ Parameter = 'Days' }
            @{ Parameter = 'Email' }
            @{ Parameter = 'IntermediateCertificate' }
            @{ Parameter = 'KeyAlgorithm' }
            @{ Parameter = 'KeySize' }
            @{ Parameter = 'Locality' }
            @{ Parameter = 'Organization' }
            @{ Parameter = 'OrganizationalUnit' }
            @{ Parameter = 'Passphrase' }
            @{ Parameter = 'PrivateKey' }
            @{ Parameter = 'State' }
            @{ Parameter = 'SubjectAlternativeNames' }
        ) {
            $attrs = (Get-Command Update-PfbCertificate).Parameters[$Parameter].Attributes
            @($attrs | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).Count |
                Should -Be 0
        }

        It 'exposes every settable body field the endpoint accepts (constraint 11)' {
            $keys = (Get-Command Update-PfbCertificate).Parameters.Keys
            foreach ($p in 'Certificate', 'CertificateType', 'CommonName', 'Country', 'Days', 'Email',
                'IntermediateCertificate', 'KeyAlgorithm', 'KeySize', 'Locality', 'Organization',
                'OrganizationalUnit', 'Passphrase', 'PrivateKey', 'State', 'SubjectAlternativeNames') {
                $keys | Should -Contain $p
            }
        }
    }
}
