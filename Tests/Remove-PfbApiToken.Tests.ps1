#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Remove-PfbApiToken (#99)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'admin selector uses the real wire names (regression: was names/ids)' {

        It 'sends -Name as admin_names, NOT names' {
            Remove-PfbApiToken -Name 'ops-admin' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'DELETE' -and $Endpoint -eq 'admins/api-tokens' -and
                $QueryParams['admin_names'] -eq 'ops-admin' -and
                -not $QueryParams.ContainsKey('names')
            }
        }

        It 'sends -Id as admin_ids, NOT ids' {
            Remove-PfbApiToken -Id 'admin-1' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['admin_ids'] -eq 'admin-1' -and
                -not $QueryParams.ContainsKey('ids')
            }
        }

        It 'accepts -AdminNames as an alias of -Name' {
            Remove-PfbApiToken -AdminNames 'ops-admin' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['admin_names'] -eq 'ops-admin'
            }
        }

        It 'accepts -AdminIds as an alias of -Id' {
            Remove-PfbApiToken -AdminIds 'admin-1' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['admin_ids'] -eq 'admin-1'
            }
        }

        It 'exposes no separate -AdminNames/-AdminIds parameters (they are aliases only)' {
            $params = (Get-Command Remove-PfbApiToken).Parameters
            $params.Keys | Should -Not -Contain 'AdminNames'
            $params.Keys | Should -Not -Contain 'AdminIds'
            $params['Name'].Aliases | Should -Contain 'AdminNames'
            $params['Id'].Aliases   | Should -Contain 'AdminIds'
        }
    }

    Context 'a request with no selector never reaches the wire' {

        It 'throws on a bare call' {
            { Remove-PfbApiToken -Array $fakeArray -Confirm:$false -ErrorAction Stop } | Should -Throw
        }

        It 'issues no request on a bare call' {
            try { Remove-PfbApiToken -Array $fakeArray -Confirm:$false -ErrorAction Stop } catch { }

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
        }

        It 'declares -Name and -Id as mandatory in their parameter sets' {
            $cmd = Get-Command Remove-PfbApiToken
            foreach ($p in 'Name', 'Id') {
                $attr = $cmd.Parameters[$p].Attributes |
                    Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
                @($attr).Mandatory | Should -Contain $true
            }
        }
    }

    Context 'pipeline binding' {

        It 'binds -Name by value from a plain string' {
            'ops-admin' | Remove-PfbApiToken -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['admin_names'] -eq 'ops-admin'
            }
        }

        It 'issues one DELETE per piped name' {
            'ops-admin', 'svc-admin' | Remove-PfbApiToken -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 2 -Exactly
        }

        It 'binds -Name by property name from a Get-PfbAdmin-shaped object' {
            [PSCustomObject]@{ name = 'ops-admin' } | Remove-PfbApiToken -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['admin_names'] -eq 'ops-admin'
            }
        }
    }

    Context 'coercion guard' {

        It 'throws on a piped Get-PfbApiToken-shaped object' {
            {
                [PSCustomObject]@{ admin = [PSCustomObject]@{ name = 'ops-admin' }; api_token = @{} } |
                    Remove-PfbApiToken -Confirm:$false -Array $fakeArray -ErrorAction Stop
            } | Should -Throw -ExpectedMessage '*stringified object*'
        }

        It 'issues no request when the guard fires' {
            try {
                [PSCustomObject]@{ admin = [PSCustomObject]@{ name = 'ops-admin' }; api_token = @{} } |
                    Remove-PfbApiToken -Confirm:$false -Array $fakeArray -ErrorAction Stop
            } catch { }

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
        }
    }

    Context 'ShouldProcess' {

        It 'issues no request under -WhatIf' {
            Remove-PfbApiToken -Name 'ops-admin' -WhatIf -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
        }

        It 'issues the request under -Confirm:$false' {
            Remove-PfbApiToken -Name 'ops-admin' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly
        }
    }
}
