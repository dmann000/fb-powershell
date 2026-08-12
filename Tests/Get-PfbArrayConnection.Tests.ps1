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

    It 'sends remote_ids when -RemoteId is used, and no other selector key' {
        Get-PfbArrayConnection -RemoteId 'r-1' -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['remote_ids'] -eq 'r-1' -and
            -not $QueryParams.ContainsKey('remote_names') -and
            -not $QueryParams.ContainsKey('names') -and -not $QueryParams.ContainsKey('ids')
        }
    }

    It 'comma-joins multiple remote ids into one key' {
        Get-PfbArrayConnection -RemoteId 'r-1','r-2' -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['remote_ids'] -eq 'r-1,r-2'
        }
    }

    It 'composes -Id with -RemoteId and emits both plural keys' {
        Get-PfbArrayConnection -Id 'conn-1' -RemoteId 'r-1' -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['ids'] -eq 'conn-1' -and $QueryParams['remote_ids'] -eq 'r-1' -and
            -not $QueryParams.ContainsKey('remote_names')
        }
    }

    It 'rejects -RemoteName together with -RemoteId at bind time, and makes no API call' {
        # The spec forbids remote_names and remote_ids on the same request, so the two
        # selectors live in different parameter sets rather than being validated at runtime.
        { Get-PfbArrayConnection -RemoteName 'FB-B' -RemoteId 'r-1' -Array $fakeArray -ErrorAction Stop } |
            Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
    }

    It 'puts no ValidateSet on the free-form selector -<Parameter>' -ForEach @(
        @{ Parameter = 'RemoteName' }
        @{ Parameter = 'RemoteId' }
        @{ Parameter = 'Id' }
    ) {
        $attrs = (Get-Command Get-PfbArrayConnection).Parameters[$Parameter].Attributes
        @($attrs | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).Count |
            Should -Be 0
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

    It 'rejects a piped object that carries no id/name property instead of stringifying it' {
        # -Id absorbs a real connection object at binding pass 2. An object without id, name or
        # remoteName falls through to pass 3 and is ToString()-ed into -RemoteName, so the guard
        # is reachable here too.
        {
            [PSCustomObject]@{ status = 'connected'; type = 'async-replication' } |
                Get-PfbArrayConnection -Array $fakeArray
        } | Should -Throw -ExpectedMessage '*stringified object*'
    }

    It 'still routes filter/sort/limit through the common helper' {
        Get-PfbArrayConnection -Filter "status='connected'" -Sort 'id' -Limit 10 -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['filter'] -eq "status='connected'" -and
            $QueryParams['sort'] -eq 'id' -and $QueryParams['limit'] -eq 10
        }
    }

    It 'sends no selector key at all when listing everything' {
        Get-PfbArrayConnection -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            -not $QueryParams.ContainsKey('remote_names') -and -not $QueryParams.ContainsKey('remote_ids') -and
            -not $QueryParams.ContainsKey('names') -and -not $QueryParams.ContainsKey('ids')
        }
    }
}
