#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'New-PfbCertificateCertificateGroup - query parameters (#31)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'existing name-based query parameters (confirmed already correct, not touched)' {
        It 'still sends -CertificateName as certificate_names' {
            New-PfbCertificateCertificateGroup -CertificateName 'cert-prod' -CertificateGroupName 'group-prod' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Endpoint -eq 'certificates/certificate-groups' -and
                $QueryParams['certificate_names'] -eq 'cert-prod' -and
                $QueryParams['certificate_group_names'] -eq 'group-prod'
            }
        }
    }

    Context '-CertificateId and -CertificateGroupId query parameters' {
        It 'sends -CertificateId as certificate_ids' {
            New-PfbCertificateCertificateGroup -CertificateId 'cert-1' -CertificateGroupName 'group-prod' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['certificate_ids'] -eq 'cert-1' -and -not $QueryParams.ContainsKey('certificate_names')
            }
        }

        It 'sends -CertificateGroupId as certificate_group_ids' {
            New-PfbCertificateCertificateGroup -CertificateName 'cert-prod' -CertificateGroupId 'group-1' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['certificate_group_ids'] -eq 'group-1' -and -not $QueryParams.ContainsKey('certificate_group_names')
            }
        }

        It 'sends both id-based selectors together' {
            New-PfbCertificateCertificateGroup -CertificateId 'cert-1' -CertificateGroupId 'group-1' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['certificate_ids'] -eq 'cert-1' -and $QueryParams['certificate_group_ids'] -eq 'group-1'
            }
        }

        It 'omits certificate_ids and certificate_group_ids entirely when not supplied' {
            New-PfbCertificateCertificateGroup -CertificateName 'cert-prod' -CertificateGroupName 'group-prod' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                -not $QueryParams.ContainsKey('certificate_ids') -and -not $QueryParams.ContainsKey('certificate_group_ids')
            }
        }
    }
}
