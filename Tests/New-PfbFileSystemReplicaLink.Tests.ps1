#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'New-PfbFileSystemReplicaLink - query parameters' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'required selectors' {
        It 'sends local_file_system_names and remote_names to POST /file-system-replica-links' {
            New-PfbFileSystemReplicaLink -LocalFileSystemName 'fs01' -RemoteArrayName 'remote-fb' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Endpoint -eq 'file-system-replica-links' -and
                $QueryParams['local_file_system_names'] -eq 'fs01' -and
                $QueryParams['remote_names'] -eq 'remote-fb'
            }
        }

        It 'sends remote_file_system_names when supplied' {
            New-PfbFileSystemReplicaLink -LocalFileSystemName 'fs01' -RemoteArrayName 'remote-fb' `
                -RemoteFileSystemName 'fs01-dr' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['remote_file_system_names'] -eq 'fs01-dr'
            }
        }
    }

    Context 'RemoteDefaultExports tri-state (fixes: [switch] could never suppress remote default exports)' {
        It 'omits remote_default_exports entirely when the parameter is not bound (defers to array default)' {
            New-PfbFileSystemReplicaLink -LocalFileSystemName 'fs01' -RemoteArrayName 'remote-fb' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                -not $QueryParams.ContainsKey('remote_default_exports')
            }
        }

        It 'sends remote_default_exports=true when -RemoteDefaultExports $true' {
            New-PfbFileSystemReplicaLink -LocalFileSystemName 'fs01' -RemoteArrayName 'remote-fb' `
                -RemoteDefaultExports $true -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['remote_default_exports'] -eq 'true'
            }
        }

        It 'sends remote_default_exports=false when -RemoteDefaultExports $false (the previously-impossible case)' {
            New-PfbFileSystemReplicaLink -LocalFileSystemName 'fs01' -RemoteArrayName 'remote-fb' `
                -RemoteDefaultExports $false -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['remote_default_exports'] -eq 'false'
            }
        }

        It 'exposes -RemoteDefaultExports as a nullable bool, not a switch' {
            $p = (Get-Command New-PfbFileSystemReplicaLink).Parameters['RemoteDefaultExports']
            $p.ParameterType | Should -Be ([Nullable[bool]])
            $p.SwitchParameter | Should -BeFalse
        }
    }
}
