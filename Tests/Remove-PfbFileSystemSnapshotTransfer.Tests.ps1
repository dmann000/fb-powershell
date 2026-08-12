#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Remove-PfbFileSystemSnapshotTransfer - remote qualifiers (#88)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'pre-existing identity paths are byte-identical' {
        It 'still sends names alone for -Name' {
            Remove-PfbFileSystemSnapshotTransfer -Name 'fs01.snap1' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'DELETE' -and $Endpoint -eq 'file-system-snapshots/transfer' -and
                $QueryParams['names'] -eq 'fs01.snap1' -and
                -not $QueryParams.ContainsKey('ids') -and
                -not $QueryParams.ContainsKey('remote_names') -and
                -not $QueryParams.ContainsKey('remote_ids')
            }
        }

        It 'still sends ids alone for -Id' {
            Remove-PfbFileSystemSnapshotTransfer -Id 'abc-123' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['ids'] -eq 'abc-123' -and
                -not $QueryParams.ContainsKey('names') -and
                -not $QueryParams.ContainsKey('remote_names') -and
                -not $QueryParams.ContainsKey('remote_ids')
            }
        }

        It 'still binds -Name from the pipeline, one request per item' {
            'fs01.snap1', 'fs01.snap2' | Remove-PfbFileSystemSnapshotTransfer -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 2 -Exactly
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['names'] -eq 'fs01.snap2'
            }
        }
    }

    Context 'the remote selectors are qualifiers, never identities' {
        It 'adds remote_names alongside names, never instead of them' {
            Remove-PfbFileSystemSnapshotTransfer -Name 'fs01.snap1' -RemoteName 'FB-B', 'FB-C' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['names'] -eq 'fs01.snap1' -and
                $QueryParams['remote_names'] -eq 'FB-B,FB-C' -and
                -not $QueryParams.ContainsKey('remote_ids')
            }
        }

        It 'adds remote_ids alongside ids, never instead of them' {
            Remove-PfbFileSystemSnapshotTransfer -Id 'abc-123' -RemoteId 'r-1', 'r-2' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['ids'] -eq 'abc-123' -and
                $QueryParams['remote_ids'] -eq 'r-1,r-2' -and
                -not $QueryParams.ContainsKey('remote_names')
            }
        }

        It 'composes -Name with -RemoteId (the remote dimension is orthogonal to the identity set)' {
            Remove-PfbFileSystemSnapshotTransfer -Name 'fs01.snap1' -RemoteId 'r-1' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['names'] -eq 'fs01.snap1' -and $QueryParams['remote_ids'] -eq 'r-1' -and
                -not $QueryParams.ContainsKey('ids') -and -not $QueryParams.ContainsKey('remote_names')
            }
        }

        It 'composes -Id with -RemoteName' {
            Remove-PfbFileSystemSnapshotTransfer -Id 'abc-123' -RemoteName 'FB-B' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['ids'] -eq 'abc-123' -and $QueryParams['remote_names'] -eq 'FB-B' -and
                -not $QueryParams.ContainsKey('names') -and -not $QueryParams.ContainsKey('remote_ids')
            }
        }

        It 'omits both remote keys entirely when no remote selector is bound' {
            Remove-PfbFileSystemSnapshotTransfer -Name 'fs01.snap1' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                -not $QueryParams.ContainsKey('remote_names') -and -not $QueryParams.ContainsKey('remote_ids')
            }
        }

        It 'refuses a remote-only call and deletes nothing' {
            # The whole point of "qualifier, not identity". If -RemoteId ever became
            # standalone-reachable, this DELETE would target every transfer aimed at that
            # remote instead of one named transfer.
            { Remove-PfbFileSystemSnapshotTransfer -RemoteId 'r-1' -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
        }

        It 'keeps -Name and -Id mandatory in their own sets, and the remote selectors out of every set' {
            # Metadata half of the rejection above, pinned so the guarantee cannot be lost by an
            # attribute edit that leaves every wire-key test still green. Asserted on metadata
            # rather than by invoking, because an unbound mandatory parameter prompts.
            $cmd = Get-Command Remove-PfbFileSystemSnapshotTransfer
            $paramAttrs = {
                param($p)
                @($cmd.Parameters[$p].Attributes |
                    Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] })
            }

            @((& $paramAttrs 'Name').ParameterSetName) | Should -Be @('ByName')
            @((& $paramAttrs 'Id').ParameterSetName)   | Should -Be @('ById')
            (& $paramAttrs 'Name')[0].Mandatory | Should -BeTrue
            (& $paramAttrs 'Id')[0].Mandatory   | Should -BeTrue

            # __AllParameterSets on the remote selectors is what lets them qualify either
            # identity; being mandatory there would make an identity-only call impossible.
            foreach ($p in 'RemoteName', 'RemoteId') {
                @((& $paramAttrs $p).ParameterSetName) |
                    Should -Be @([System.Management.Automation.ParameterAttribute]::AllParameterSets)
                (& $paramAttrs $p)[0].Mandatory | Should -BeFalse
            }
        }
    }

    Context 'mutual exclusion, at runtime, before the request' {
        It 'throws the exact message for -RemoteName with -RemoteId, and deletes nothing' {
            # This cmdlet enforces the exclusion with a throw in begin{} rather than with
            # parameter sets (which would fracture ByName/ById). begin{} runs ahead of the
            # connection check and ahead of any process{} request, so nothing is deleted.
            { Remove-PfbFileSystemSnapshotTransfer -Name 'fs01.snap1' -RemoteName 'FB-B' -RemoteId 'r-1' `
                    -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '-RemoteName and -RemoteId cannot be used together: remote_names and remote_ids are mutually exclusive.'

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
        }

        It 'throws before the pipeline delivers any item' {
            { 'fs01.snap1', 'fs01.snap2' |
                Remove-PfbFileSystemSnapshotTransfer -RemoteName 'FB-B' -RemoteId 'r-1' `
                    -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*mutually exclusive*'

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
        }
    }

    Context 'ShouldProcess' {
        It 'still declares SupportsShouldProcess with ConfirmImpact High' {
            $meta = [System.Management.Automation.CommandMetadata]::new((Get-Command Remove-PfbFileSystemSnapshotTransfer))
            $meta.SupportsShouldProcess | Should -BeTrue
            $meta.ConfirmImpact | Should -Be ([System.Management.Automation.ConfirmImpact]::High)
        }

        It 'makes no API call when ShouldProcess is declined via -WhatIf, even with a remote qualifier' {
            Remove-PfbFileSystemSnapshotTransfer -Name 'fs01.snap1' -RemoteId 'r-1' -WhatIf -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
        }
    }
}
