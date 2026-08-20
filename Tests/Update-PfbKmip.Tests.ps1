#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Update-PfbKmip - typed body parameters (#31)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'typed parameters build the body' {
        It 'sends -CaCertificate as a scalar name reference' {
            Update-PfbKmip -Name 'kmip-server-1' -CaCertificate 'cert-1' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Endpoint -eq 'kmip' -and
                $QueryParams['names'] -eq 'kmip-server-1' -and
                $Body['ca_certificate'].name -eq 'cert-1'
            }
        }

        It 'sends -CaCertificateGroup as a scalar name reference' {
            Update-PfbKmip -Name 'kmip-server-1' -CaCertificateGroup 'kmip-certs' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['ca_certificate_group'].name -eq 'kmip-certs'
            }
        }

        It 'sends -Uris as a plain string array' {
            Update-PfbKmip -Name 'kmip-server-1' -Uris 'kmip1.example.com:5696', 'kmip2.example.com:5696' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['uris'].Count -eq 2 -and
                $Body['uris'][0] -eq 'kmip1.example.com:5696' -and
                $Body['uris'][1] -eq 'kmip2.example.com:5696'
            }
        }

        It 'sends an EMPTY array for -Uris @() so the list can be cleared (constraint 2)' {
            Update-PfbKmip -Name 'kmip-server-1' -Uris @() -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('uris') -and @($Body['uris']).Count -eq 0
            }
        }

        It 'omits every body key when no typed body parameter is supplied' {
            Update-PfbKmip -Name 'kmip-server-1' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.Count -eq 0
            }
        }

        It 'targets the KMIP config by id when -Id is used' {
            Update-PfbKmip -Id 'kmip-1' -Uris 'kmip1.example.com:5696' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['ids'] -eq 'kmip-1' -and -not $QueryParams.ContainsKey('names')
            }
        }
    }

    Context '-Attributes remains supported and is mutually exclusive' {
        It 'still sends a raw -Attributes body' {
            Update-PfbKmip -Name 'kmip-server-1' -Attributes @{ uris = @('raw.example.com:5696') } `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['uris'][0] -eq 'raw.example.com:5696'
            }
        }

        It 'rejects -Attributes combined with a typed parameter at bind time' {
            { Update-PfbKmip -Name 'kmip-server-1' -Uris 'x.example.com:5696' -Attributes @{ uris = @('y') } `
                -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'
        }
    }
}
