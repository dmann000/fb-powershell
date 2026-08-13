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

Describe 'Get-PfbFileSystemReplicaLinkTransfer - remote-array selectors (#88)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    It 'sends no remote keys at all on a bare list call' {
        Get-PfbFileSystemReplicaLinkTransfer -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'GET' -and $Endpoint -eq 'file-system-replica-links/transfer' -and
            -not $QueryParams.ContainsKey('remote_names') -and -not $QueryParams.ContainsKey('remote_ids')
        }
    }

    It 'sends remote_names for -RemoteName, comma-joined' {
        Get-PfbFileSystemReplicaLinkTransfer -RemoteName 'FB-B', 'FB-C' -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['remote_names'] -eq 'FB-B,FB-C' -and
            -not $QueryParams.ContainsKey('remote_ids') -and
            -not $QueryParams.ContainsKey('names') -and
            -not $QueryParams.ContainsKey('names_or_owner_names')
        }
    }

    It 'sends remote_ids for -RemoteId, comma-joined' {
        Get-PfbFileSystemReplicaLinkTransfer -RemoteId 'r-1', 'r-2' -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['remote_ids'] -eq 'r-1,r-2' -and
            -not $QueryParams.ContainsKey('remote_names')
        }
    }

    It 'composes -RemoteId with the ByNameOrOwnerName identity set' {
        # The remote dimension is deliberately set-less, so it must remain usable alongside
        # BOTH existing identity sets. Putting it in exclusive sets would break this.
        Get-PfbFileSystemReplicaLinkTransfer -NameOrOwnerName 'fs01' -RemoteId 'r-1' -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['names_or_owner_names'] -eq 'fs01' -and $QueryParams['remote_ids'] -eq 'r-1' -and
            -not $QueryParams.ContainsKey('ids')
        }
    }

    It 'composes -RemoteName with the ById identity set' {
        Get-PfbFileSystemReplicaLinkTransfer -Id 'transfer-1' -RemoteName 'FB-B' -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['ids'] -eq 'transfer-1' -and $QueryParams['remote_names'] -eq 'FB-B' -and
            -not $QueryParams.ContainsKey('names_or_owner_names')
        }
    }

    It 'composes -RemoteId with pipeline-bound ids' {
        @([PSCustomObject]@{ id = 'transfer-1' }, [PSCustomObject]@{ id = 'transfer-2' }) |
            Get-PfbFileSystemReplicaLinkTransfer -RemoteId 'r-1' -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['ids'] -eq 'transfer-1,transfer-2' -and $QueryParams['remote_ids'] -eq 'r-1'
        }
    }

    It 'throws the exact message for -RemoteName with -RemoteId, and reads nothing' {
        # Enforced by a runtime throw in begin{} rather than by parameter sets, which would
        # have split each existing set in two and made -Name/-Id resolution ambiguous.
        # begin{} runs ahead of the connection check and ahead of the end{} request.
        { Get-PfbFileSystemReplicaLinkTransfer -RemoteName 'FB-B' -RemoteId 'r-1' -Array $fakeArray -ErrorAction Stop } |
            Should -Throw -ExpectedMessage '-RemoteName and -RemoteId cannot be used together: remote_names and remote_ids are mutually exclusive.'

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
    }

    It 'throws for the combination even when an identity selector is also bound' {
        { Get-PfbFileSystemReplicaLinkTransfer -Id 'transfer-1' -RemoteName 'FB-B' -RemoteId 'r-1' `
                -Array $fakeArray -ErrorAction Stop } |
            Should -Throw -ExpectedMessage '*mutually exclusive*'

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
    }

    It 'keeps -<Parameter> out of every identity set so it can qualify both' -ForEach @(
        @{ Parameter = 'RemoteName' }
        @{ Parameter = 'RemoteId' }
    ) {
        $attrs = (Get-Command Get-PfbFileSystemReplicaLinkTransfer).Parameters[$Parameter].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
        @($attrs.ParameterSetName) |
            Should -Be @([System.Management.Automation.ParameterAttribute]::AllParameterSets)
        @($attrs | Where-Object { $_.Mandatory }).Count | Should -Be 0
        # No pipeline binding: these must not be able to absorb a piped object and be
        # ToString()-ed into a remote selector, which is why they carry no coercion guard.
        @($attrs | Where-Object { $_.ValueFromPipeline -or $_.ValueFromPipelineByPropertyName }).Count |
            Should -Be 0
    }
}
