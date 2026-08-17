#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Get-PfbArrayConnectionKey - name selector and coercion guard (#90)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    It 'rejects a piped object carrying neither name nor id instead of stringifying it into -Name' {
        # The self-chain shape: connection-key items carry only connection_key/created/expires.
        {
            [PSCustomObject]@{ connection_key = 'abc123'; created = 1; expires = 2 } |
                Get-PfbArrayConnectionKey -Array $fakeArray -ErrorAction Stop
        } | Should -Throw -ExpectedMessage '*stringified object*'
    }

    It 'issues no request at all when the guard trips' {
        try {
            [PSCustomObject]@{ connection_key = 'abc123'; created = 1; expires = 2 } |
                Get-PfbArrayConnectionKey -Array $fakeArray -ErrorAction Stop
        } catch {
            # Expected: the guard throws terminatingly, so the end block never runs.
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
    }

    It 'still binds a bare string to -Name by value and sends names' {
        'remote-fb-dc2' | Get-PfbArrayConnectionKey -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['names'] -eq 'remote-fb-dc2' -and -not $QueryParams.ContainsKey('ids')
        }
    }

    It 'still sends names when -Name is passed explicitly' {
        Get-PfbArrayConnectionKey -Name 'remote-fb-dc2','remote-fb-dc3' -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['names'] -eq 'remote-fb-dc2,remote-fb-dc3' -and -not $QueryParams.ContainsKey('ids')
        }
    }

    It 'binds -Name alongside -Filter and -Limit and emits all three wire keys' {
        Get-PfbArrayConnectionKey -Name 'remote-fb-dc2' -Filter "expires>0" -Limit 3 -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['names'] -eq 'remote-fb-dc2' -and $QueryParams['filter'] -eq "expires>0" -and
            $QueryParams['limit'] -eq 3 -and -not $QueryParams.ContainsKey('ids')
        }
    }

    It 'still routes filter/sort/limit through the common helper with no selector key' {
        Get-PfbArrayConnectionKey -Filter "expires>0" -Sort 'created' -Limit 5 -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['filter'] -eq "expires>0" -and $QueryParams['sort'] -eq 'created' -and
            $QueryParams['limit'] -eq 5 -and
            -not $QueryParams.ContainsKey('names') -and -not $QueryParams.ContainsKey('ids')
        }
    }

    It 'sends no selector key at all when listing everything' {
        Get-PfbArrayConnectionKey -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            -not $QueryParams.ContainsKey('names') -and -not $QueryParams.ContainsKey('ids')
        }
    }
}
