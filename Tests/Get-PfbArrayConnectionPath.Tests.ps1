#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Get-PfbArrayConnectionPath - selector query keys (#64)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    It 'sends remote_names, never names' {
        Get-PfbArrayConnectionPath -RemoteName 'FB-B' -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'GET' -and $Endpoint -eq 'array-connections/path' -and
            $QueryParams['remote_names'] -eq 'FB-B' -and -not $QueryParams.ContainsKey('names')
        }
    }

    It 'still binds -Name through the alias, and emits remote_names for it' {
        Get-PfbArrayConnectionPath -Name 'FB-B' -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['remote_names'] -eq 'FB-B' -and -not $QueryParams.ContainsKey('names')
        }
    }

    It 'declares Name as an alias of -RemoteName' {
        (Get-Command Get-PfbArrayConnectionPath).Parameters['RemoteName'].Aliases | Should -Contain 'Name'
    }

    It 'accumulates remote names piped by value into a single comma-joined key' {
        'FB-B','FB-C' | Get-PfbArrayConnectionPath -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['remote_names'] -eq 'FB-B,FB-C'
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
            } | Get-PfbArrayConnectionPath -Array $fakeArray
        } | Should -Throw -ExpectedMessage '*stringified object*'

        $captured = $global:pfbCapturedRemoteNames
        Remove-Variable -Name pfbCapturedRemoteNames -Scope Global -ErrorAction SilentlyContinue
        $captured | Should -Not -BeLike '*@{*' -Because 'a whole piped object must not be stringified onto the remote_names filter'
    }

    It 'still routes filter/sort/limit through the common helper' {
        Get-PfbArrayConnectionPath -Filter "status='connected'" -Sort 'name' -Limit 5 -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['filter'] -eq "status='connected'" -and
            $QueryParams['sort'] -eq 'name' -and $QueryParams['limit'] -eq 5
        }
    }

    It 'sends no selector key at all when listing everything' {
        Get-PfbArrayConnectionPath -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            -not $QueryParams.ContainsKey('remote_names') -and -not $QueryParams.ContainsKey('names')
        }
    }
}
