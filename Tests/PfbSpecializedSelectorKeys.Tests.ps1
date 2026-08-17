#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{
        Endpoint  = 'fb.example.test'
        ApiVersion = '2.0'
        AuthToken = 'x'
    }

}

Describe 'Specialized selector query keys (#90)' {
    Context 'parameter metadata' {
        It 'removes -Name/-Id and exposes -CertificateName and -CertificateGroupId without legacy aliases' {
            $command = Get-Command -Name 'Get-PfbCertificateGroupCertificate'

            $command.Parameters.Keys | Should -Not -Contain 'Name'
            $command.Parameters.Keys | Should -Not -Contain 'Id'
            $command.Parameters.Keys | Should -Contain 'CertificateName'
            $command.Parameters.Keys | Should -Contain 'CertificateGroupId'
            $command.Parameters['CertificateName'].Aliases | Should -Not -Contain 'Name'
            $command.Parameters['CertificateGroupId'].Aliases | Should -Not -Contain 'Id'
        }

        It 'removes -Name and exposes -RealmName without a Name alias' {
            $command = Get-Command -Name 'Get-PfbRealmDefaults'

            $command.Parameters.Keys | Should -Not -Contain 'Name'
            $command.Parameters.Keys | Should -Contain 'RealmName'
            $command.Parameters['RealmName'].Aliases | Should -Not -Contain 'Name'
        }

        It 'removes -Name and exposes -LocalPortName without a Name alias' {
            $command = Get-Command -Name 'Get-PfbNetworkInterfaceNeighbor'

            $command.Parameters.Keys | Should -Not -Contain 'Name'
            $command.Parameters.Keys | Should -Contain 'LocalPortName'
            $command.Parameters['LocalPortName'].Aliases | Should -Not -Contain 'Name'
        }
    }

    Context 'query wire keys' {
        BeforeEach {
            Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
        }

        It 'emits certificate_names=management as the only query key' {
            Get-PfbCertificateGroupCertificate -CertificateName 'management' -Array $script:fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'GET' -and
                $Endpoint -eq 'certificate-groups/certificates' -and
                $QueryParams.Count -eq 1 -and
                $QueryParams['certificate_names'] -eq 'management' -and
                -not $QueryParams.ContainsKey('names') -and
                -not $QueryParams.ContainsKey('ids')
            }
        }

        It 'joins multiple certificate names into one certificate_names value' {
            Get-PfbCertificateGroupCertificate -CertificateName 'management', 'ad-cert' -Array $script:fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams.Count -eq 1 -and
                $QueryParams['certificate_names'] -eq 'management,ad-cert'
            }
        }

        It 'emits certificate_group_ids as the only query key' {
            Get-PfbCertificateGroupCertificate -CertificateGroupId '10314f42-020d-7080-8013-000ddd11003d' -Array $script:fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'GET' -and
                $Endpoint -eq 'certificate-groups/certificates' -and
                $QueryParams.Count -eq 1 -and
                $QueryParams['certificate_group_ids'] -eq '10314f42-020d-7080-8013-000ddd11003d' -and
                -not $QueryParams.ContainsKey('ids') -and
                -not $QueryParams.ContainsKey('names')
            }
        }

        It 'emits realm_names=pslivetest-realm-a as the only query key' {
            Get-PfbRealmDefaults -RealmName 'pslivetest-realm-a' -Array $script:fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'GET' -and
                $Endpoint -eq 'realms/defaults' -and
                $QueryParams.Count -eq 1 -and
                $QueryParams['realm_names'] -eq 'pslivetest-realm-a' -and
                -not $QueryParams.ContainsKey('names') -and
                -not $QueryParams.ContainsKey('ids')
            }
        }

        It 'emits local_port_names=ch0.eth0 as the only query key' {
            Get-PfbNetworkInterfaceNeighbor -LocalPortName 'ch0.eth0' -Array $script:fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'GET' -and
                $Endpoint -eq 'network-interfaces/neighbors' -and
                $QueryParams.Count -eq 1 -and
                $QueryParams['local_port_names'] -eq 'ch0.eth0' -and
                -not $QueryParams.ContainsKey('names') -and
                -not $QueryParams.ContainsKey('ids')
            }
        }

        It 'still emits the declared common keys alongside the specialized selector' {
            Get-PfbRealmDefaults -RealmName 'pslivetest-realm-a' -Filter "name='x'" -Sort 'name' -Limit 5 -Array $script:fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams.Count -eq 4 -and
                $QueryParams['realm_names'] -eq 'pslivetest-realm-a' -and
                $QueryParams['filter'] -eq "name='x'" -and
                $QueryParams['sort'] -eq 'name' -and
                $QueryParams['limit'] -eq 5
            }
        }

        It 'emits no selector key when no selector is supplied' {
            Get-PfbNetworkInterfaceNeighbor -Array $script:fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams.Count -eq 0
            }
        }

        It 'accepts pipeline input on the specialized certificate selector' {
            'management', 'ad-cert' | Get-PfbCertificateGroupCertificate -Array $script:fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['certificate_names'] -eq 'management,ad-cert'
            }
        }
    }
}
