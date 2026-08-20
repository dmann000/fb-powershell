#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Get-PfbFileSystemReplicaLink - selector query keys (#88)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'no-selector read is preserved' {
        It 'sends no selector keys at all on a bare list call' {
            Get-PfbFileSystemReplicaLink -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'GET' -and $Endpoint -eq 'file-system-replica-links' -and
                -not $QueryParams.ContainsKey('ids') -and
                -not $QueryParams.ContainsKey('remote_names') -and
                -not $QueryParams.ContainsKey('remote_ids')
            }
        }

        It 'still routes the pre-existing local/remote file-system filters' {
            Get-PfbFileSystemReplicaLink -LocalFileSystemName 'fs-data' -RemoteFileSystemName 'fs-data-dr' -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['local_file_system_names'] -eq 'fs-data' -and
                $QueryParams['remote_file_system_names'] -eq 'fs-data-dr' -and
                -not $QueryParams.ContainsKey('remote_names') -and
                -not $QueryParams.ContainsKey('remote_ids')
            }
        }

        It 'still routes filter, sort, and limit through the common helper' {
            Get-PfbFileSystemReplicaLink -Filter "status='replicating'" -Sort 'direction' -Limit 20 -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['filter'] -eq "status='replicating'" -and
                $QueryParams['sort'] -eq 'direction' -and $QueryParams['limit'] -eq 20
            }
        }
    }

    Context 'exact wire keys for the added selectors' {
        It 'sends ids for -Id, comma-joined, and nothing else' {
            Get-PfbFileSystemReplicaLink -Id 'link-1', 'link-2' -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['ids'] -eq 'link-1,link-2' -and
                -not $QueryParams.ContainsKey('names') -and
                -not $QueryParams.ContainsKey('remote_names') -and
                -not $QueryParams.ContainsKey('remote_ids')
            }
        }

        It 'sends remote_names for -RemoteName, comma-joined, never remote_file_system_names' {
            # -RemoteName names the REMOTE ARRAY; -RemoteFileSystemName names the remote FILE
            # SYSTEM. Emitting one under the other's key would silently change the result set.
            Get-PfbFileSystemReplicaLink -RemoteName 'FB-B', 'FB-C' -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['remote_names'] -eq 'FB-B,FB-C' -and
                -not $QueryParams.ContainsKey('remote_file_system_names') -and
                -not $QueryParams.ContainsKey('remote_ids')
            }
        }

        It 'sends remote_ids for -RemoteId, comma-joined, never remote_names' {
            Get-PfbFileSystemReplicaLink -RemoteId 'r-1', 'r-2' -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['remote_ids'] -eq 'r-1,r-2' -and
                -not $QueryParams.ContainsKey('remote_names')
            }
        }

        It 'composes -Id with -RemoteName and emits both keys' {
            Get-PfbFileSystemReplicaLink -Id 'link-1' -RemoteName 'FB-B' -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['ids'] -eq 'link-1' -and $QueryParams['remote_names'] -eq 'FB-B' -and
                -not $QueryParams.ContainsKey('remote_ids')
            }
        }

        It 'composes -Id with -RemoteId and emits both keys' {
            Get-PfbFileSystemReplicaLink -Id 'link-1' -RemoteId 'r-1' -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['ids'] -eq 'link-1' -and $QueryParams['remote_ids'] -eq 'r-1' -and
                -not $QueryParams.ContainsKey('remote_names')
            }
        }
    }

    Context 'mutual exclusion' {
        It 'rejects -RemoteName together with -RemoteId at bind time, and reads nothing' {
            { Get-PfbFileSystemReplicaLink -RemoteName 'FB-B' -RemoteId 'r-1' -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
        }
    }

    Context 'parameter-set topology' {
        It 'declares -Id in every set so it stays reachable on its own' {
            $attrs = (Get-Command Get-PfbFileSystemReplicaLink).Parameters['Id'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            @($attrs.ParameterSetName) | Sort-Object | Should -Be @('ByRemoteId', 'ByRemoteName', 'List')
            @($attrs | Where-Object { $_.Mandatory }).Count | Should -Be 0
        }

        It 'keeps -<Parameter> in exactly one exclusive set' -ForEach @(
            @{ Parameter = 'RemoteName'; Set = 'ByRemoteName' }
            @{ Parameter = 'RemoteId';   Set = 'ByRemoteId' }
        ) {
            $attrs = (Get-Command Get-PfbFileSystemReplicaLink).Parameters[$Parameter].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            @($attrs.ParameterSetName) | Should -Be @($Set)
        }

        It 'defaults to the List set so a bare read still resolves' {
            (Get-Command Get-PfbFileSystemReplicaLink).DefaultParameterSet | Should -Be 'List'
        }

        It 'declares no pipeline binding on -Id, so the transfer chain cannot be intercepted' {
            # Get-PfbFileSystemReplicaLink | Get-PfbFileSystemReplicaLinkTransfer is a documented
            # chain. A ValueFromPipeline* attribute on this cmdlet's own -Id would make it a
            # pipeline sink and change what the chain means.
            $attrs = (Get-Command Get-PfbFileSystemReplicaLink).Parameters['Id'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            @($attrs | Where-Object { $_.ValueFromPipeline -or $_.ValueFromPipelineByPropertyName }).Count |
                Should -Be 0
        }
    }
}
