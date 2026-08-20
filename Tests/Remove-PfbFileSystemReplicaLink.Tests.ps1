#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Remove-PfbFileSystemReplicaLink - selector query keys (#88)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'pre-existing removal paths are byte-identical' {
        It 'still sends local_file_system_names + remote_names on the ByName path' {
            Remove-PfbFileSystemReplicaLink -LocalFileSystemName 'fs01' -RemoteArrayName 'remote-fb' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'DELETE' -and $Endpoint -eq 'file-system-replica-links' -and
                $QueryParams['local_file_system_names'] -eq 'fs01' -and
                $QueryParams['remote_names'] -eq 'remote-fb' -and
                -not $QueryParams.ContainsKey('remote_ids') -and
                -not $QueryParams.ContainsKey('ids')
            }
        }

        It 'still sends ids alone on the ById path' {
            # -Id is the ONLY standalone-identity removal path. If a remote selector ever
            # became standalone-reachable, this would stop being true.
            Remove-PfbFileSystemReplicaLink -Id 'link-9' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['ids'] -eq 'link-9' -and
                -not $QueryParams.ContainsKey('local_file_system_names') -and
                -not $QueryParams.ContainsKey('remote_names') -and
                -not $QueryParams.ContainsKey('remote_ids')
            }
        }

        It 'still emits cancel_in_progress_transfers=true when the switch is present' {
            Remove-PfbFileSystemReplicaLink -Id 'link-9' -CancelInProgressTransfers `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['cancel_in_progress_transfers'] -eq 'true'
            }
        }

        It 'omits cancel_in_progress_transfers when the switch is absent' {
            Remove-PfbFileSystemReplicaLink -Id 'link-9' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                -not $QueryParams.ContainsKey('cancel_in_progress_transfers')
            }
        }
    }

    Context 'the added ByRemoteId path' {
        It 'sends local_file_system_names + remote_ids, never remote_names' {
            Remove-PfbFileSystemReplicaLink -LocalFileSystemName 'fs01' -RemoteId 'r-77' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'DELETE' -and $Endpoint -eq 'file-system-replica-links' -and
                $QueryParams['local_file_system_names'] -eq 'fs01' -and
                $QueryParams['remote_ids'] -eq 'r-77' -and
                -not $QueryParams.ContainsKey('remote_names') -and
                -not $QueryParams.ContainsKey('ids')
            }
        }

        It 'carries the optional remote_file_system_names disambiguator' {
            Remove-PfbFileSystemReplicaLink -LocalFileSystemName 'fs01' -RemoteId 'r-77' `
                -RemoteFileSystemName 'fs01-dr' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['remote_file_system_names'] -eq 'fs01-dr' -and
                $QueryParams['remote_ids'] -eq 'r-77'
            }
        }

        It 'omits remote_file_system_names when it is not supplied' {
            Remove-PfbFileSystemReplicaLink -LocalFileSystemName 'fs01' -RemoteId 'r-77' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                -not $QueryParams.ContainsKey('remote_file_system_names')
            }
        }
    }

    Context 'mutual exclusion and composite identity' {
        It 'rejects -RemoteArrayName together with -RemoteId at bind time, and deletes nothing' {
            { Remove-PfbFileSystemReplicaLink -LocalFileSystemName 'fs01' -RemoteArrayName 'remote-fb' `
                    -RemoteId 'r-77' -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
        }

        It 'rejects -Id together with -RemoteId at bind time, and deletes nothing' {
            # ById and ByRemoteId are disjoint: -Id already identifies the link, so mixing it
            # with a remote selector has no defined meaning on this DELETE.
            { Remove-PfbFileSystemReplicaLink -Id 'link-9' -RemoteId 'r-77' `
                    -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
        }

        It 'keeps -LocalFileSystemName mandatory in both composite sets' {
            # Load-bearing, and the dangerous half. -RemoteId names only the remote side; if
            # -LocalFileSystemName were made optional in ByRemoteId, a bare -RemoteId call would
            # resolve and DELETE every replica link pointing at that remote. Asserted on the
            # metadata rather than by invoking, because an unbound mandatory parameter prompts
            # interactively rather than failing.
            $cmd = Get-Command Remove-PfbFileSystemReplicaLink
            $mandatoryIn = {
                param($p, $set)
                @($cmd.Parameters[$p].Attributes |
                    Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and
                                   $_.ParameterSetName -eq $set })[0].Mandatory
            }

            & $mandatoryIn 'LocalFileSystemName' 'ByName'     | Should -BeTrue
            & $mandatoryIn 'LocalFileSystemName' 'ByRemoteId' | Should -BeTrue
            & $mandatoryIn 'RemoteArrayName'     'ByName'     | Should -BeTrue
            & $mandatoryIn 'RemoteId'            'ByRemoteId' | Should -BeTrue
            & $mandatoryIn 'Id'                  'ById'       | Should -BeTrue
        }

        It 'declares -<Parameter> in exactly the sets <Sets>' -ForEach @(
            @{ Parameter = 'LocalFileSystemName';  Sets = @('ByName', 'ByRemoteId') }
            @{ Parameter = 'RemoteArrayName';      Sets = @('ByName') }
            @{ Parameter = 'RemoteId';             Sets = @('ByRemoteId') }
            @{ Parameter = 'Id';                   Sets = @('ById') }
            @{ Parameter = 'RemoteFileSystemName'; Sets = @('ByName', 'ByRemoteId') }
        ) {
            # -Id must stay out of ByRemoteId and -RemoteId out of ById: the two are alternative
            # whole identities, not composable qualifiers, on this endpoint.
            $attrs = (Get-Command Remove-PfbFileSystemReplicaLink).Parameters[$Parameter].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            @($attrs.ParameterSetName) | Sort-Object | Should -Be ($Sets | Sort-Object)
        }
    }

    Context 'ShouldProcess' {
        It 'still declares SupportsShouldProcess with ConfirmImpact High' {
            # Downgrading either of these would silently remove the confirmation gate from a
            # DELETE without changing a single wire key, so no other test here would notice.
            $meta = [System.Management.Automation.CommandMetadata]::new((Get-Command Remove-PfbFileSystemReplicaLink))
            $meta.SupportsShouldProcess | Should -BeTrue
            $meta.ConfirmImpact | Should -Be ([System.Management.Automation.ConfirmImpact]::High)
        }

        It 'makes no API call when ShouldProcess is declined via -WhatIf on the <Set> path' -ForEach @(
            @{ Set = 'ByName';     Splat = @{ LocalFileSystemName = 'fs01'; RemoteArrayName = 'remote-fb' } }
            @{ Set = 'ByRemoteId'; Splat = @{ LocalFileSystemName = 'fs01'; RemoteId = 'r-77' } }
            @{ Set = 'ById';       Splat = @{ Id = 'link-9' } }
        ) {
            Remove-PfbFileSystemReplicaLink @Splat -WhatIf -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
        }
    }
}
