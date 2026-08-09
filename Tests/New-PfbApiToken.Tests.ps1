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

        It 'sends an explicit -Timeout 0 rather than dropping it (constraint 2, integer field)' {
            New-PfbApiToken -Name 'ops-admin' -Timeout 0 -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams.ContainsKey('timeout') -and $QueryParams['timeout'] -eq 0
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

    Context 'no request body reaches the wire (#99)' {

        It 'passes no -Body on a plain call' {
            New-PfbApiToken -Name 'ops-admin' -Confirm:$false -Array $fakeArray

            # $PSBoundParameters is NOT populated inside a Pester ParameterFilter -- it is
            # always empty, so a ContainsKey('Body') assertion would pass vacuously even
            # against code that does pass -Body. Assert on the bound $Body value instead.
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $null -eq $Body
            }
        }

        It 'passes no -Body even when -Attributes is supplied' {
            New-PfbApiToken -Name 'ops-admin' -Attributes @{ ignored = 'x' } -Confirm:$false -Array $fakeArray -WarningAction SilentlyContinue

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $null -eq $Body
            }
        }

        It 'warns that -Attributes is a no-op' {
            $warnings = @()
            New-PfbApiToken -Name 'ops-admin' -Attributes @{ ignored = 'x' } -Confirm:$false -Array $fakeArray -WarningVariable warnings -WarningAction SilentlyContinue

            $warnings | Should -Not -BeNullOrEmpty
            "$warnings" | Should -BeLike '*-Attributes*'
        }

        It 'warns once for the whole invocation, not once per piped name' {
            # -Attributes binds once for the whole invocation, so the warning lives in begin.
            # Emitted from process it would repeat per item in the bulk-rotation flow.
            $warnings = @()
            'ops-admin', 'svc-admin' | New-PfbApiToken -Attributes @{ ignored = 'x' } -Confirm:$false -Array $fakeArray -WarningVariable warnings -WarningAction SilentlyContinue

            @($warnings).Count | Should -Be 1
        }

        It 'does not warn when -Attributes is absent' {
            $warnings = @()
            New-PfbApiToken -Name 'ops-admin' -Confirm:$false -Array $fakeArray -WarningVariable warnings -WarningAction SilentlyContinue

            $warnings | Should -BeNullOrEmpty
        }
    }

    Context 'a request with no selector never reaches the wire (#99)' {

        # NOTE: the bare-call and -Timeout-only cases below are ALSO caught upstream by
        # AmbiguousParameterSet -- two parameter sets with no DefaultParameterSetName and no
        # set-unique bound parameter fail to resolve before `process` is entered, with or
        # without the Mandatory flags. They are kept as regression rails, but they do not
        # prove the Mandatory flags work.
        #
        # Neither do the empty-string tests at the end of this block. They are regressions
        # against the pre-fix behaviour -- where -Name '' bound legally to the ByName set,
        # `if ($Name)` was false, and an unfiltered POST went out -- but what stops them
        # today is Mandatory's own EmptyStringNotAllowed check at binding time, not the
        # in-process throw this Context is named after. That throw is unreachable from every
        # input (see the .DESCRIPTION note in New-PfbApiToken.ps1); it is kept as a backstop
        # and is not covered by any test here. The parameter-metadata test below is what
        # actually pins the Mandatory flags and the parameter sets in place.
        It 'throws on a bare call' {
            { New-PfbApiToken -Array $fakeArray -Confirm:$false -ErrorAction Stop } | Should -Throw
        }

        It 'issues no request on a bare call' {
            try { New-PfbApiToken -Array $fakeArray -Confirm:$false -ErrorAction Stop } catch { }

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
        }

        It 'issues no request when only -Timeout is supplied' {
            try { New-PfbApiToken -Timeout 86400000 -Array $fakeArray -Confirm:$false -ErrorAction Stop } catch { }

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
        }

        It 'throws when the selector is an empty string' {
            { New-PfbApiToken -Name '' -Array $fakeArray -Confirm:$false -ErrorAction Stop } | Should -Throw
        }

        It 'issues no request when the selector is an empty string' {
            try { New-PfbApiToken -Name '' -Array $fakeArray -Confirm:$false -ErrorAction Stop } catch { }

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
        }

        It 'declares -Name and -Id as mandatory in their parameter sets' {
            $cmd = Get-Command New-PfbApiToken
            foreach ($p in 'Name', 'Id') {
                $attr = $cmd.Parameters[$p].Attributes |
                    Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
                @($attr).Mandatory | Should -Contain $true
            }
        }
    }

    Context 'pipeline binding (#99)' {

        It 'binds -Name by value from a plain string' {
            'ops-admin' | New-PfbApiToken -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['admin_names'] -eq 'ops-admin'
            }
        }

        It 'issues one POST per piped name, in order' {
            'ops-admin', 'svc-admin' | New-PfbApiToken -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 2 -Exactly
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['admin_names'] -eq 'ops-admin'
            }
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['admin_names'] -eq 'svc-admin'
            }
        }

        It 'still binds -Name by property name from a Get-PfbAdmin-shaped object' {
            [PSCustomObject]@{ name = 'ops-admin' } | New-PfbApiToken -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['admin_names'] -eq 'ops-admin'
            }
        }

        It 'throws on a piped Get-PfbApiToken-shaped object' {
            {
                [PSCustomObject]@{ admin = [PSCustomObject]@{ name = 'ops-admin' }; api_token = @{} } |
                    New-PfbApiToken -Confirm:$false -Array $fakeArray -ErrorAction Stop
            } | Should -Throw -ExpectedMessage '*stringified object*'
        }

        It 'issues no request when the coercion guard fires' {
            try {
                [PSCustomObject]@{ admin = [PSCustomObject]@{ name = 'ops-admin' }; api_token = @{} } |
                    New-PfbApiToken -Confirm:$false -Array $fakeArray -ErrorAction Stop
            } catch { }

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
        }
    }
}
