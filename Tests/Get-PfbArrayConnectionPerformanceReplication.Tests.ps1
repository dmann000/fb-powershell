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

    It 'does NOT coerce a piped object into -RemoteName (binding-order guard)' {
        $global:pfbCapturedRemoteNames = $null
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest {
            $global:pfbCapturedRemoteNames = $QueryParams['remote_names']
        }

        {
            [PSCustomObject]@{
                id     = '10314f42-aaaa'
                status = 'connected'
                remote = [PSCustomObject]@{ id = 'r-1'; name = 'FB-B' }
            } | Get-PfbArrayConnectionPerformanceReplication -Array $fakeArray
        } | Should -Throw -ExpectedMessage '*stringified object*'

        $captured = $global:pfbCapturedRemoteNames
        Remove-Variable -Name pfbCapturedRemoteNames -Scope Global -ErrorAction SilentlyContinue
        $captured | Should -Not -BeLike '*@{*' -Because 'a whole piped object must not be stringified onto the remote_names filter'
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
