#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Get-PfbApiToken (#99)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'admin selector uses the real wire names (regression: was names/ids)' {

        It 'sends -Name as admin_names, NOT names' {
            Get-PfbApiToken -Name 'ops-admin' -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'GET' -and $Endpoint -eq 'admins/api-tokens' -and
                $QueryParams['admin_names'] -eq 'ops-admin' -and
                -not $QueryParams.ContainsKey('names')
            }
        }

        It 'sends -Id as admin_ids, NOT ids' {
            Get-PfbApiToken -Id 'admin-1' -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['admin_ids'] -eq 'admin-1' -and
                -not $QueryParams.ContainsKey('ids')
            }
        }

        It 'joins multiple names into one comma-separated admin_names value' {
            Get-PfbApiToken -Name 'ops-admin', 'svc-admin' -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['admin_names'] -eq 'ops-admin,svc-admin'
            }
        }

        It 'accumulates piped names into a single request' {
            'ops-admin', 'svc-admin' | Get-PfbApiToken -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['admin_names'] -eq 'ops-admin,svc-admin'
            }
        }

        It 'accepts -AdminNames and -AdminIds as aliases' {
            Get-PfbApiToken -AdminNames 'ops-admin' -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['admin_names'] -eq 'ops-admin'
            }

            $params = (Get-Command Get-PfbApiToken).Parameters
            $params.Keys | Should -Not -Contain 'AdminNames'
            $params['Name'].Aliases | Should -Contain 'AdminNames'
            $params['Id'].Aliases   | Should -Contain 'AdminIds'
        }

        It 'sends no selector key at all on an unfiltered list call' {
            Get-PfbApiToken -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                -not $QueryParams.ContainsKey('admin_names') -and
                -not $QueryParams.ContainsKey('admin_ids') -and
                -not $QueryParams.ContainsKey('names') -and
                -not $QueryParams.ContainsKey('ids')
            }
        }
    }

    Context '-ExposeApiToken' {

        It 'sends expose_api_token=true when the switch is present' {
            Get-PfbApiToken -Name 'ops-admin' -ExposeApiToken -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['expose_api_token'] -eq 'true'
            }
        }

        It 'omits expose_api_token entirely when the switch is absent' {
            Get-PfbApiToken -Name 'ops-admin' -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                -not $QueryParams.ContainsKey('expose_api_token')
            }
        }

        It 'omits expose_api_token when explicitly disabled with -ExposeApiToken:$false' {
            Get-PfbApiToken -Name 'ops-admin' -ExposeApiToken:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                -not $QueryParams.ContainsKey('expose_api_token')
            }
        }
    }

    Context 'common query parameters still flow through the helper' {

        It 'sends filter, sort and limit' {
            Get-PfbApiToken -Filter "name='ops-admin'" -Sort 'name' -Limit 5 -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['filter'] -eq "name='ops-admin'" -and
                $QueryParams['sort']   -eq 'name' -and
                $QueryParams['limit']  -eq 5
            }
        }

        It 'requests auto-pagination' {
            Get-PfbApiToken -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $AutoPaginate -eq $true
            }
        }
    }
}
