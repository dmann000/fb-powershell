#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    Import-Module "$PSScriptRoot/../PureStorageFlashBladePowerShell.psd1" -Force
    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Get-PfbArrayConnectionPerformanceReplication' {
    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    It 'restricts -Type to the three real spec-documented values' {
        $attr = (Get-Command Get-PfbArrayConnectionPerformanceReplication).Parameters['Type'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
        $attr | Should -Not -BeNullOrEmpty
        $attr.ValidValues | Should -Be @('all', 'file-system', 'object-store')
    }

    It 'rejects an invalid -Type value before making any API call' {
        { Get-PfbArrayConnectionPerformanceReplication -Type 'bogus' -Array $fakeArray } | Should -Throw
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 0 -Exactly
    }

    It 'passes a valid -Type through to the query string' {
        Get-PfbArrayConnectionPerformanceReplication -Type 'file-system' -Array $fakeArray
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'GET' -and $Endpoint -eq 'array-connections/performance/replication' -and $QueryParams['type'] -eq 'file-system'
        }
    }

    It 'omits -Type from the query string when not specified' {
        Get-PfbArrayConnectionPerformanceReplication -Array $fakeArray
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            -not $QueryParams.ContainsKey('type')
        }
    }

    It 'sends remote_names, never names' {
        Get-PfbArrayConnectionPerformanceReplication -RemoteName 'FB-B' -Array $fakeArray

        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $Endpoint -eq 'array-connections/performance/replication' -and
            $QueryParams['remote_names'] -eq 'FB-B' -and -not $QueryParams.ContainsKey('names')
        }
    }

    It 'still binds -Name through the alias, and emits remote_names for it' {
        Get-PfbArrayConnectionPerformanceReplication -Name 'FB-B' -Array $fakeArray

        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $QueryParams['remote_names'] -eq 'FB-B' -and -not $QueryParams.ContainsKey('names')
        }
    }

    It 'accumulates remote names piped by value into a single comma-joined key' {
        'FB-B','FB-C' | Get-PfbArrayConnectionPerformanceReplication -Array $fakeArray

        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $QueryParams['remote_names'] -eq 'FB-B,FB-C'
        }
    }

    It 'binds -RemoteName by property name from a user-built object' {
        [pscustomobject]@{ RemoteName = 'FB-B' } | Get-PfbArrayConnectionPerformanceReplication -Array $fakeArray

        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $QueryParams['remote_names'] -eq 'FB-B'
        }
    }

    It 'binds by property name through the Name alias' {
        [pscustomobject]@{ Name = 'FB-B' } | Get-PfbArrayConnectionPerformanceReplication -Array $fakeArray

        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $QueryParams['remote_names'] -eq 'FB-B'
        }
    }

    It 'sends remote_ids when -RemoteId is used, and no other selector key' {
        Get-PfbArrayConnectionPerformanceReplication -RemoteId 'r-1' -Array $fakeArray

        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $QueryParams['remote_ids'] -eq 'r-1' -and
            -not $QueryParams.ContainsKey('remote_names') -and
            -not $QueryParams.ContainsKey('names') -and -not $QueryParams.ContainsKey('ids')
        }
    }

    It 'sends ids when -Id is used, and no remote_names' {
        Get-PfbArrayConnectionPerformanceReplication -Id 'conn-1','conn-2' -Array $fakeArray

        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $QueryParams['ids'] -eq 'conn-1,conn-2' -and -not $QueryParams.ContainsKey('remote_names')
        }
    }

    It 'composes -Id with -RemoteId and emits both plural keys' {
        Get-PfbArrayConnectionPerformanceReplication -Id 'conn-1' -RemoteId 'r-1' -Array $fakeArray

        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $QueryParams['ids'] -eq 'conn-1' -and $QueryParams['remote_ids'] -eq 'r-1' -and
            -not $QueryParams.ContainsKey('remote_names')
        }
    }

    It 'rejects -RemoteName together with -RemoteId at bind time, and makes no API call' {
        { Get-PfbArrayConnectionPerformanceReplication -RemoteName 'FB-B' -RemoteId 'r-1' -Array $fakeArray -ErrorAction Stop } |
            Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'

        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 0 -Exactly
    }

    It 'puts no ValidateSet on the free-form selector -<Parameter>' -ForEach @(
        @{ Parameter = 'RemoteName' }
        @{ Parameter = 'RemoteId' }
        @{ Parameter = 'Id' }
    ) {
        $attrs = (Get-Command Get-PfbArrayConnectionPerformanceReplication).Parameters[$Parameter].Attributes
        @($attrs | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).Count |
            Should -Be 0
    }

    It 'binds a piped connection-shaped object by id and emits ids' {
        # A whole connection object carries `id`, which binds -Id by property name. This is
        # the shape the guard used to intercept before -Id existed on this cmdlet.
        [PSCustomObject]@{
            id     = '10314f42-aaaa'
            status = 'connected'
            remote = [PSCustomObject]@{ id = 'r-1'; name = 'FB-B' }
        } | Get-PfbArrayConnectionPerformanceReplication -Array $fakeArray

        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $QueryParams['ids'] -eq '10314f42-aaaa' -and -not $QueryParams.ContainsKey('remote_names')
        }
    }

    It 'rejects a piped object that carries no id/name property instead of stringifying it' {
        # An object that binds to neither -Id nor a name property falls through to the
        # ByValue-with-coercion pass and would be ToString()-ed into -RemoteName.
        {
            [PSCustomObject]@{ status = 'connected'; type = 'async-replication' } |
                Get-PfbArrayConnectionPerformanceReplication -Array $fakeArray
        } | Should -Throw -ExpectedMessage '*stringified object*'

        # The throw is terminating, so the end block never runs and no request is issued at all.
        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
    }

    It 'sends no selector key at all when listing everything' {
        Get-PfbArrayConnectionPerformanceReplication -Array $fakeArray

        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            -not $QueryParams.ContainsKey('remote_names') -and -not $QueryParams.ContainsKey('remote_ids') -and
            -not $QueryParams.ContainsKey('names') -and -not $QueryParams.ContainsKey('ids')
        }
    }

    It 'keeps remote_names alongside the time-range keys' {
        Get-PfbArrayConnectionPerformanceReplication -RemoteName 'FB-B' -Resolution 86400000 `
            -StartTime 1609459200000 -Array $fakeArray

        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $QueryParams['remote_names'] -eq 'FB-B' -and
            $QueryParams['resolution'] -eq 86400000 -and $QueryParams['start_time'] -eq 1609459200000
        }
    }
}
