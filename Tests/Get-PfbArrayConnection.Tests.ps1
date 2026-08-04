#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Get-PfbArrayConnection - selector query keys (#64)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    It 'sends remote_names, never names' {
        Get-PfbArrayConnection -RemoteName 'FB-B' -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'GET' -and $Endpoint -eq 'array-connections' -and
            $QueryParams['remote_names'] -eq 'FB-B' -and -not $QueryParams.ContainsKey('names')
        }
    }

    It 'still binds -Name through the alias, and emits remote_names for it' {
        Get-PfbArrayConnection -Name 'FB-B' -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['remote_names'] -eq 'FB-B' -and -not $QueryParams.ContainsKey('names')
        }
    }

    It 'declares Name as an alias of -RemoteName' {
        (Get-Command Get-PfbArrayConnection).Parameters['RemoteName'].Aliases | Should -Contain 'Name'
    }

    It 'comma-joins multiple remote names into one key' {
        Get-PfbArrayConnection -RemoteName 'FB-B','FB-C' -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['remote_names'] -eq 'FB-B,FB-C'
        }
    }

    It 'accumulates remote names piped by value into a single request' {
        'FB-B','FB-C' | Get-PfbArrayConnection -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['remote_names'] -eq 'FB-B,FB-C'
        }
    }

    It 'sends ids when -Id is used, and no remote_names' {
        Get-PfbArrayConnection -Id 'conn-1','conn-2' -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['ids'] -eq 'conn-1,conn-2' -and -not $QueryParams.ContainsKey('remote_names')
        }
    }

    It 'binds piped connection objects by id' {
        @([PSCustomObject]@{ id = 'conn-1' }, [PSCustomObject]@{ id = 'conn-2' }) |
            Get-PfbArrayConnection -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['ids'] -eq 'conn-1,conn-2' -and -not $QueryParams.ContainsKey('remote_names')
        }
    }

    It 'binds -RemoteName by property name from a user-built object' {
        [pscustomobject]@{ RemoteName = 'FB-B' } | Get-PfbArrayConnection -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['remote_names'] -eq 'FB-B' -and -not $QueryParams.ContainsKey('ids')
        }
    }

    It 'binds by property name through the Name alias' {
        [pscustomobject]@{ Name = 'FB-B' } | Get-PfbArrayConnection -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['remote_names'] -eq 'FB-B' -and -not $QueryParams.ContainsKey('ids')
        }
    }

    It 'still routes filter/sort/limit through the common helper' {
        Get-PfbArrayConnection -Filter "status='connected'" -Sort 'name' -Limit 10 -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['filter'] -eq "status='connected'" -and
            $QueryParams['sort'] -eq 'name' -and $QueryParams['limit'] -eq 10
        }
    }

    It 'sends no selector key at all when listing everything' {
        Get-PfbArrayConnection -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            -not $QueryParams.ContainsKey('remote_names') -and
            -not $QueryParams.ContainsKey('names') -and -not $QueryParams.ContainsKey('ids')
        }
    }
}
