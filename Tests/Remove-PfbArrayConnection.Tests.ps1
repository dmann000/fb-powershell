#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Remove-PfbArrayConnection - selector query keys (#64)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    It 'sends remote_names, never names' {
        Remove-PfbArrayConnection -RemoteName 'FB-B' -Confirm:$false -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'DELETE' -and $Endpoint -eq 'array-connections' -and
            $QueryParams['remote_names'] -eq 'FB-B' -and -not $QueryParams.ContainsKey('names')
        }
    }

    It 'still binds -Name through the alias, and emits remote_names for it' {
        Remove-PfbArrayConnection -Name 'FB-B' -Confirm:$false -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['remote_names'] -eq 'FB-B' -and -not $QueryParams.ContainsKey('names')
        }
    }

    It 'declares Name as an alias of -RemoteName' {
        (Get-Command Remove-PfbArrayConnection).Parameters['RemoteName'].Aliases | Should -Contain 'Name'
    }

    It 'targets the connection by id when -Id is used' {
        Remove-PfbArrayConnection -Id 'conn-1' -Confirm:$false -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['ids'] -eq 'conn-1' -and -not $QueryParams.ContainsKey('remote_names')
        }
    }

    It 'binds a piped connection object by id' {
        [PSCustomObject]@{ id = 'conn-9' } |
            Remove-PfbArrayConnection -Confirm:$false -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['ids'] -eq 'conn-9'
        }
    }

    It 'does NOT coerce a piped object into -RemoteName (binding-order guard)' {
        [PSCustomObject]@{ id = 'conn-9' } |
            Remove-PfbArrayConnection -Confirm:$false -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            -not $QueryParams.ContainsKey('remote_names') -and $QueryParams['ids'] -notlike '*@{*'
        }
    }

    It 'still accepts a bare remote name piped by value' {
        'FB-B' | Remove-PfbArrayConnection -Confirm:$false -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['remote_names'] -eq 'FB-B'
        }
    }

    It 'makes no API call when ShouldProcess is declined via -WhatIf' {
        Remove-PfbArrayConnection -RemoteName 'FB-B' -WhatIf -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
    }
}
