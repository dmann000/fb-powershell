#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'New-PfbFileSystemReplicaLinkPolicy - query parameters (#31)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'existing selectors (converted to ContainsKey)' {
        It 'sends policy_names and member_ids' {
            New-PfbFileSystemReplicaLinkPolicy -PolicyName 'repl-daily' -MemberId 'member-1' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Endpoint -eq 'file-system-replica-links/policies' -and
                $QueryParams['policy_names'] -eq 'repl-daily' -and
                $QueryParams['member_ids'] -eq 'member-1'
            }
        }

        It 'sends policy_ids' {
            New-PfbFileSystemReplicaLinkPolicy -PolicyId 'policy-1' -MemberId 'member-1' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['policy_ids'] -eq 'policy-1'
            }
        }
    }

    Context 'member_names does not exist on this endpoint (confirmed bug fix)' {
        It 'never sends a member_names query parameter (regression: POST /file-system-replica-links/policies has no member_names)' {
            New-PfbFileSystemReplicaLinkPolicy -PolicyName 'repl-daily' -LocalFileSystemName 'fs01' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                -not $QueryParams.ContainsKey('member_names') -and
                $QueryParams['local_file_system_names'] -eq 'fs01'
            }
        }

        It 'accepts -MemberName as a backward-compatible alias of -LocalFileSystemName' {
            New-PfbFileSystemReplicaLinkPolicy -PolicyName 'repl-daily' -MemberName 'fs01' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['local_file_system_names'] -eq 'fs01' -and
                -not $QueryParams.ContainsKey('member_names')
            }
        }

        It 'exposes no separate -MemberName parameter (alias only)' {
            $params = (Get-Command New-PfbFileSystemReplicaLinkPolicy).Parameters
            $params.Keys | Should -Not -Contain 'MemberName'
            $params['LocalFileSystemName'].Aliases | Should -Contain 'MemberName'
        }
    }

    Context 'new query parameters' {
        It 'sends local_file_system_ids' {
            New-PfbFileSystemReplicaLinkPolicy -PolicyName 'repl-daily' -LocalFileSystemId 'fs-id-1' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['local_file_system_ids'] -eq 'fs-id-1'
            }
        }

        It 'sends remote_ids' {
            New-PfbFileSystemReplicaLinkPolicy -PolicyName 'repl-daily' -RemoteId 'remote-1' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['remote_ids'] -eq 'remote-1'
            }
        }

        It 'sends remote_names' {
            New-PfbFileSystemReplicaLinkPolicy -PolicyName 'repl-daily' -RemoteName 'remote-array' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['remote_names'] -eq 'remote-array'
            }
        }

        It 'omits all optional query parameters when not supplied' {
            New-PfbFileSystemReplicaLinkPolicy -PolicyName 'repl-daily' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                -not $QueryParams.ContainsKey('local_file_system_ids') -and
                -not $QueryParams.ContainsKey('local_file_system_names') -and
                -not $QueryParams.ContainsKey('remote_ids') -and
                -not $QueryParams.ContainsKey('remote_names')
            }
        }
    }

    Context 'constraint compliance' {
        It 'puts no ValidateSet on -<Parameter> (constraint 3, no spec enum)' -ForEach @(
            @{ Parameter = 'PolicyName' }
            @{ Parameter = 'PolicyId' }
            @{ Parameter = 'MemberId' }
            @{ Parameter = 'LocalFileSystemName' }
            @{ Parameter = 'LocalFileSystemId' }
            @{ Parameter = 'RemoteId' }
            @{ Parameter = 'RemoteName' }
        ) {
            $attrs = (Get-Command New-PfbFileSystemReplicaLinkPolicy).Parameters[$Parameter].Attributes
            @($attrs | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).Count |
                Should -Be 0
        }
    }
}
