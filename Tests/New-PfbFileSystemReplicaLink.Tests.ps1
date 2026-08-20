#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule

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

    Context 'remote selectors (#88)' {
        It 'sends remote_ids and not remote_names on the ByRemoteId path' {
            New-PfbFileSystemReplicaLink -LocalFileSystemName 'fs01' -RemoteId 'r-77' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Endpoint -eq 'file-system-replica-links' -and
                $QueryParams['local_file_system_names'] -eq 'fs01' -and
                $QueryParams['remote_ids'] -eq 'r-77' -and
                -not $QueryParams.ContainsKey('remote_names')
            }
        }

        It 'still sends an empty body on the ByRemoteId path' {
            New-PfbFileSystemReplicaLink -LocalFileSystemName 'fs01' -RemoteId 'r-77' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $null -ne $Body -and $Body.Count -eq 0
            }
        }

        It 'carries -RemoteFileSystemName and the tri-state export flag onto the ByRemoteId path' {
            New-PfbFileSystemReplicaLink -LocalFileSystemName 'fs01' -RemoteId 'r-77' `
                -RemoteFileSystemName 'fs01-dr' -RemoteDefaultExports $false -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['remote_ids'] -eq 'r-77' -and
                $QueryParams['remote_file_system_names'] -eq 'fs01-dr' -and
                $QueryParams['remote_default_exports'] -eq 'false'
            }
        }

        It 'rejects -RemoteArrayName together with -RemoteId at bind time, and creates nothing' {
            { New-PfbFileSystemReplicaLink -LocalFileSystemName 'fs01' -RemoteArrayName 'remote-fb' `
                    -RemoteId 'r-77' -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
        }

        It 'keeps -LocalFileSystemName mandatory in every set, so no remote-only create exists' {
            # -RemoteId names the remote side only. If -LocalFileSystemName were scoped to
            # ByRemoteName, a bare -RemoteId call would resolve and POST with no local
            # identity. Pinned on metadata rather than by invoking, because an unbound
            # mandatory parameter prompts interactively instead of failing.
            $attrs = (Get-Command New-PfbFileSystemReplicaLink).Parameters['LocalFileSystemName'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            @($attrs.ParameterSetName) |
                Should -Be @([System.Management.Automation.ParameterAttribute]::AllParameterSets)
            $attrs[0].Mandatory | Should -BeTrue
        }

        It 'keeps the remote selectors mandatory in their own exclusive sets' {
            $cmd = Get-Command New-PfbFileSystemReplicaLink
            foreach ($pair in @(@('RemoteArrayName', 'ByRemoteName'), @('RemoteId', 'ByRemoteId'))) {
                $attrs = $cmd.Parameters[$pair[0]].Attributes |
                    Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
                @($attrs.ParameterSetName) | Should -Be @($pair[1])
                $attrs[0].Mandatory | Should -BeTrue
            }
            $cmd.DefaultParameterSet | Should -Be 'ByRemoteName'
        }
    }

    Context '-Id is a published-spec pass-through only (#88)' {
        # The spec publishes ids on this POST but documents it with the generic read-filter
        # wording, so nothing is asserted here about what the array does with it. These tests
        # pin only what the module controls: the exact key emitted, and that -Id can never
        # displace the mandatory local identity.
        It 'omits ids entirely when -Id is not bound' {
            New-PfbFileSystemReplicaLink -LocalFileSystemName 'fs01' -RemoteArrayName 'remote-fb' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                -not $QueryParams.ContainsKey('ids')
            }
        }

        It 'emits ids comma-joined when -Id is bound, alongside the unchanged local identity' {
            New-PfbFileSystemReplicaLink -LocalFileSystemName 'fs01' -RemoteArrayName 'remote-fb' `
                -Id 'link-1', 'link-2' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['ids'] -eq 'link-1,link-2' -and
                $QueryParams['local_file_system_names'] -eq 'fs01' -and
                $QueryParams['remote_names'] -eq 'remote-fb'
            }
        }

        It 'is opt-in and set-less: it neither joins nor replaces a remote-selector set' {
            $attrs = (Get-Command New-PfbFileSystemReplicaLink).Parameters['Id'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            @($attrs.ParameterSetName) |
                Should -Be @([System.Management.Automation.ParameterAttribute]::AllParameterSets)
            $attrs[0].Mandatory | Should -BeFalse
        }
    }

    Context 'ShouldProcess' {
        It 'still declares SupportsShouldProcess with ConfirmImpact Medium' {
            $meta = [System.Management.Automation.CommandMetadata]::new((Get-Command New-PfbFileSystemReplicaLink))
            $meta.SupportsShouldProcess | Should -BeTrue
            $meta.ConfirmImpact | Should -Be ([System.Management.Automation.ConfirmImpact]::Medium)
        }

        It 'makes no API call when ShouldProcess is declined via -WhatIf on the <Set> path' -ForEach @(
            @{ Set = 'ByRemoteName'; Splat = @{ LocalFileSystemName = 'fs01'; RemoteArrayName = 'remote-fb' } }
            @{ Set = 'ByRemoteId';   Splat = @{ LocalFileSystemName = 'fs01'; RemoteId = 'r-77' } }
        ) {
            New-PfbFileSystemReplicaLink @Splat -WhatIf -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
        }
    }
}
