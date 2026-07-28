#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'New-PfbApiToken - query parameters (#31)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'admin selector uses the real wire names (regression: was names/ids)' {
        It 'sends -Name as admin_names, NOT names' {
            New-PfbApiToken -Name 'ops-admin' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Endpoint -eq 'admins/api-tokens' -and
                $QueryParams['admin_names'] -eq 'ops-admin' -and
                -not $QueryParams.ContainsKey('names')
            }
        }

        It 'sends -Id as admin_ids, NOT ids' {
            New-PfbApiToken -Id 'admin-1' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['admin_ids'] -eq 'admin-1' -and
                -not $QueryParams.ContainsKey('ids')
            }
        }

        It 'accepts -AdminNames as an alias of -Name' {
            New-PfbApiToken -AdminNames 'ops-admin' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['admin_names'] -eq 'ops-admin'
            }
        }

        It 'accepts -AdminIds as an alias of -Id' {
            New-PfbApiToken -AdminIds 'admin-1' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['admin_ids'] -eq 'admin-1'
            }
        }

        It 'exposes no separate -AdminNames/-AdminIds parameters (they are aliases only)' {
            $params = (Get-Command New-PfbApiToken).Parameters
            $params.Keys | Should -Not -Contain 'AdminNames'
            $params.Keys | Should -Not -Contain 'AdminIds'
            $params['Name'].Aliases | Should -Contain 'AdminNames'
            $params['Id'].Aliases   | Should -Contain 'AdminIds'
        }
    }

    Context '-Timeout query parameter' {
        It 'sends timeout when supplied' {
            New-PfbApiToken -Name 'ops-admin' -Timeout 86400000 -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['timeout'] -eq 86400000
            }
        }

        It 'omits timeout entirely when not supplied' {
            New-PfbApiToken -Name 'ops-admin' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                -not $QueryParams.ContainsKey('timeout')
            }
        }

        It 'accepts a value beyond Int32 range (spec type is int64)' {
            New-PfbApiToken -Name 'ops-admin' -Timeout 3000000000 -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['timeout'] -eq 3000000000
            }
        }
    }
}
