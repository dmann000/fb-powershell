#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Get-PfbBucketReplicaLink - selector query keys (#88)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'no-selector read is preserved' {
        It 'sends no selector keys at all on a bare list call' {
            # The regression this guards: giving -RemoteName/-RemoteId their own parameter sets
            # must not make a bare list call resolve to a set that emits an empty selector key.
            Get-PfbBucketReplicaLink -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'GET' -and $Endpoint -eq 'bucket-replica-links' -and
                -not $QueryParams.ContainsKey('ids') -and
                -not $QueryParams.ContainsKey('remote_names') -and
                -not $QueryParams.ContainsKey('remote_ids')
            }
        }

        It 'still routes the pre-existing local/remote bucket filters' {
            Get-PfbBucketReplicaLink -LocalBucketName 's3-backup' -RemoteBucketName 's3-archive-dr' -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['local_bucket_names'] -eq 's3-backup' -and
                $QueryParams['remote_bucket_names'] -eq 's3-archive-dr' -and
                -not $QueryParams.ContainsKey('remote_names') -and
                -not $QueryParams.ContainsKey('remote_ids')
            }
        }

        It 'still routes filter, sort, and limit through the common helper' {
            Get-PfbBucketReplicaLink -Filter "status='replicating'" -Sort 'direction' -Limit 5 -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['filter'] -eq "status='replicating'" -and
                $QueryParams['sort'] -eq 'direction' -and $QueryParams['limit'] -eq 5
            }
        }
    }

    Context 'exact wire keys for the added selectors' {
        It 'sends ids for -Id, comma-joined, and nothing else' {
            Get-PfbBucketReplicaLink -Id 'link-1', 'link-2' -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['ids'] -eq 'link-1,link-2' -and
                -not $QueryParams.ContainsKey('names') -and
                -not $QueryParams.ContainsKey('remote_names') -and
                -not $QueryParams.ContainsKey('remote_ids')
            }
        }

        It 'sends remote_names for -RemoteName, comma-joined, never remote_bucket_names' {
            # -RemoteName is the REMOTE ARRAY, a different dimension from -RemoteBucketName.
            # Collapsing the two would silently change which resources the read returns.
            Get-PfbBucketReplicaLink -RemoteName 'FB-B', 'FB-C' -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['remote_names'] -eq 'FB-B,FB-C' -and
                -not $QueryParams.ContainsKey('remote_bucket_names') -and
                -not $QueryParams.ContainsKey('remote_ids')
            }
        }

        It 'sends remote_ids for -RemoteId, comma-joined, never remote_names' {
            Get-PfbBucketReplicaLink -RemoteId 'r-1', 'r-2' -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['remote_ids'] -eq 'r-1,r-2' -and
                -not $QueryParams.ContainsKey('remote_names')
            }
        }

        It 'composes -Id with -RemoteName and emits both keys' {
            Get-PfbBucketReplicaLink -Id 'link-1' -RemoteName 'FB-B' -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['ids'] -eq 'link-1' -and $QueryParams['remote_names'] -eq 'FB-B' -and
                -not $QueryParams.ContainsKey('remote_ids')
            }
        }

        It 'composes -Id with -RemoteId and emits both keys' {
            Get-PfbBucketReplicaLink -Id 'link-1' -RemoteId 'r-1' -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['ids'] -eq 'link-1' -and $QueryParams['remote_ids'] -eq 'r-1' -and
                -not $QueryParams.ContainsKey('remote_names')
            }
        }
    }

    Context 'mutual exclusion' {
        It 'rejects -RemoteName together with -RemoteId at bind time, and reads nothing' {
            # The spec couples only the two remote forms: "This cannot be provided together with
            # the remote_ids query parameter". Parameter sets make it a binding-time error, so
            # no request is assembled at all.
            { Get-PfbBucketReplicaLink -RemoteName 'FB-B' -RemoteId 'r-1' -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
        }
    }

    Context 'parameter-set topology' {
        It 'declares -Id in every set so it stays reachable on its own' {
            $attrs = (Get-Command Get-PfbBucketReplicaLink).Parameters['Id'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            @($attrs.ParameterSetName) | Sort-Object | Should -Be @('ByRemoteId', 'ByRemoteName', 'List')
            @($attrs | Where-Object { $_.Mandatory }).Count | Should -Be 0
        }

        It 'keeps -<Parameter> in exactly one exclusive set' -ForEach @(
            @{ Parameter = 'RemoteName'; Set = 'ByRemoteName' }
            @{ Parameter = 'RemoteId';   Set = 'ByRemoteId' }
        ) {
            $attrs = (Get-Command Get-PfbBucketReplicaLink).Parameters[$Parameter].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            @($attrs.ParameterSetName) | Should -Be @($Set)
        }

        It 'defaults to the List set so a bare read still resolves' {
            (Get-Command Get-PfbBucketReplicaLink).DefaultParameterSet | Should -Be 'List'
        }
    }
}
