#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'New-PfbPolicyFileSystemReplicaLink - correct query wire keys (#31)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'policy selector unchanged' {
        It 'sends -PolicyName as policy_names' {
            New-PfbPolicyFileSystemReplicaLink -PolicyName 'daily-snap' -LocalFileSystemName 'fs1' -Confirm:$false -Array $fakeArray
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter { $QueryParams['policy_names'] -eq 'daily-snap' }
        }

        It 'sends -PolicyId as policy_ids' {
            New-PfbPolicyFileSystemReplicaLink -PolicyId 'p-1' -LocalFileSystemId 'lfs-1' -Confirm:$false -Array $fakeArray
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter { $QueryParams['policy_ids'] -eq 'p-1' }
        }
    }

    Context 'regression: member_names does not exist on this endpoint (confirmed via spec), but member_ids does' {
        It 'sends -LocalFileSystemName as local_file_system_names, NOT member_names' {
            New-PfbPolicyFileSystemReplicaLink -PolicyName 'daily-snap' -LocalFileSystemName 'fs1/remote-fb' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['local_file_system_names'] -eq 'fs1/remote-fb' -and
                -not $QueryParams.ContainsKey('member_names')
            }
        }

        It 'sends -LocalFileSystemId as local_file_system_ids, NOT member_ids' {
            New-PfbPolicyFileSystemReplicaLink -PolicyName 'daily-snap' -LocalFileSystemId 'lfs-1' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['local_file_system_ids'] -eq 'lfs-1' -and
                -not $QueryParams.ContainsKey('member_ids')
            }
        }

        It 'accepts -MemberName as a backward-compatible alias of -LocalFileSystemName (whole-branch review finding I-3: matches the sibling cmdlet New-PfbFileSystemReplicaLinkPolicy)' {
            New-PfbPolicyFileSystemReplicaLink -PolicyName 'daily-snap' -MemberName 'fs01' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['local_file_system_names'] -eq 'fs01' -and
                -not $QueryParams.ContainsKey('member_names')
            }
        }

        It 'exposes no separate -MemberName parameter (alias only)' {
            $params = (Get-Command New-PfbPolicyFileSystemReplicaLink).Parameters
            $params.Keys | Should -Not -Contain 'MemberName'
            $params['LocalFileSystemName'].Aliases | Should -Contain 'MemberName'
        }

        It 'sends -MemberId as member_ids (real, spec-declared parameter -- restored after review, unlike -MemberName)' {
            New-PfbPolicyFileSystemReplicaLink -PolicyName 'daily-snap' -MemberId 'member-1' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['member_ids'] -eq 'member-1'
            }
        }

        It 'omits member_ids entirely when -MemberId is not supplied' {
            New-PfbPolicyFileSystemReplicaLink -PolicyName 'daily-snap' -LocalFileSystemName 'fs1' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                -not $QueryParams.ContainsKey('member_ids')
            }
        }
    }

    Context 'new remote query parameters' {
        It 'sends -RemoteName as remote_names' {
            New-PfbPolicyFileSystemReplicaLink -PolicyName 'daily-snap' -RemoteName 'remote-fb' -Confirm:$false -Array $fakeArray
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter { $QueryParams['remote_names'] -eq 'remote-fb' }
        }

        It 'sends -RemoteId as remote_ids' {
            New-PfbPolicyFileSystemReplicaLink -PolicyName 'daily-snap' -RemoteId 'remote-1' -Confirm:$false -Array $fakeArray
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter { $QueryParams['remote_ids'] -eq 'remote-1' }
        }
    }

    Context 'no request body' {
        It 'sends no Body parameter to Invoke-PfbApiRequest' {
            New-PfbPolicyFileSystemReplicaLink -PolicyName 'daily-snap' -LocalFileSystemName 'fs1' -Confirm:$false -Array $fakeArray
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter { $null -eq $Body }
        }
    }

    Context 'honors -WhatIf' {
        It 'makes no call under -WhatIf' {
            New-PfbPolicyFileSystemReplicaLink -PolicyName 'daily-snap' -LocalFileSystemName 'fs1' -WhatIf -Array $fakeArray
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
        }
    }
}
