#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Get-PfbFileSystemReplicaLinkTransfer - selector query keys (#87)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    It 'sends names_or_owner_names for -NameOrOwnerName, never names' {
        Get-PfbFileSystemReplicaLinkTransfer -NameOrOwnerName 'fs01' -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'GET' -and $Endpoint -eq 'file-system-replica-links/transfer' -and
            $QueryParams['names_or_owner_names'] -eq 'fs01' -and
            -not $QueryParams.ContainsKey('names')
        }
    }

    It 'still binds -Name through the alias and emits names_or_owner_names' {
        Get-PfbFileSystemReplicaLinkTransfer -Name 'fs01' -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['names_or_owner_names'] -eq 'fs01' -and
            -not $QueryParams.ContainsKey('names')
        }
    }

    It 'declares Name as an alias of -NameOrOwnerName' {
        (Get-Command Get-PfbFileSystemReplicaLinkTransfer).Parameters['NameOrOwnerName'].Aliases |
            Should -Contain 'Name'
    }

    It 'sends ids when -Id is used' {
        Get-PfbFileSystemReplicaLinkTransfer -Id 'transfer-1','transfer-2' -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['ids'] -eq 'transfer-1,transfer-2' -and
            -not $QueryParams.ContainsKey('names_or_owner_names') -and
            -not $QueryParams.ContainsKey('names')
        }
    }

    It 'binds -Id by property name from piped objects' {
        @([PSCustomObject]@{ id = 'transfer-1' }, [PSCustomObject]@{ id = 'transfer-2' }) |
            Get-PfbFileSystemReplicaLinkTransfer -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['ids'] -eq 'transfer-1,transfer-2'
        }
    }

    It 'comma-joins multiple name-or-owner-name values into one key' {
        Get-PfbFileSystemReplicaLinkTransfer -NameOrOwnerName 'snapshot-1','fs01' -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['names_or_owner_names'] -eq 'snapshot-1,fs01' -and
            -not $QueryParams.ContainsKey('names')
        }
    }

    It 'still emits total_only through the common helper' {
        Get-PfbFileSystemReplicaLinkTransfer -TotalOnly -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['total_only'] -eq 'true'
        }
    }

    It 'still routes filter, sort, and limit through the common helper' {
        Get-PfbFileSystemReplicaLinkTransfer -Filter "direction='outbound'" -Sort 'progress' -Limit 10 -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['filter'] -eq "direction='outbound'" -and
            $QueryParams['sort'] -eq 'progress' -and $QueryParams['limit'] -eq 10
        }
    }

    It 'rejects a piped object coerced to a string before making the request' {
        {
            [PSCustomObject]@{ status = 'transferring'; direction = 'outbound' } |
                Get-PfbFileSystemReplicaLinkTransfer -Array $fakeArray
        } | Should -Throw -ExpectedMessage '*stringified object*'

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0
    }
}
