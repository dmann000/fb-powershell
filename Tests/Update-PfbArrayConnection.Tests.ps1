#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Update-PfbArrayConnection - typed body parameters (#31)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'typed parameters build the body' {
        It 'sends management_address as a body field' {
            Update-PfbArrayConnection -RemoteName 'remote-fb-dc2' -ManagementAddress '10.0.2.101' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Endpoint -eq 'array-connections' -and
                $QueryParams['remote_names'] -eq 'remote-fb-dc2' -and
                $Body['management_address'] -eq '10.0.2.101'
            }
        }

        It 'sends replication_addresses as an array (constraint 7 shape 2)' {
            Update-PfbArrayConnection -RemoteName 'remote-fb-dr' -ReplicationAddresses '10.0.3.101','10.0.3.102' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                @($Body['replication_addresses']).Count -eq 2 -and
                @($Body['replication_addresses'])[1] -eq '10.0.3.102'
            }
        }

        It 'sends an EMPTY array for -ReplicationAddresses @() so the list can be cleared' {
            Update-PfbArrayConnection -RemoteName 'remote-fb-dr' -ReplicationAddresses @() `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('replication_addresses') -and
                @($Body['replication_addresses']).Count -eq 0
            }
        }

        It 'sends an explicit -Encrypted:$false (ContainsKey semantics, not truthiness)' {
            Update-PfbArrayConnection -RemoteName 'remote-fb-dc2' -Encrypted $false -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('encrypted') -and $Body['encrypted'] -eq $false
            }
        }

        It 'omits encrypted entirely when not supplied' {
            Update-PfbArrayConnection -RemoteName 'remote-fb-dc2' -ManagementAddress '10.0.2.101' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                -not $Body.ContainsKey('encrypted')
            }
        }

        It 'builds ca_certificate_group as a name-reference object (constraint 8a)' {
            Update-PfbArrayConnection -RemoteName 'remote-fb-dc2' -CaCertificateGroup 'my-certs' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['ca_certificate_group'].name -eq 'my-certs'
            }
        }

        It 'builds remote as a name-reference object (constraint 8a)' {
            Update-PfbArrayConnection -RemoteName 'remote-fb-dc2' -Remote 'remote-fb' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['remote'].name -eq 'remote-fb'
            }
        }

        It 'passes throttle straight through as a composite hashtable (constraint 8c)' {
            Update-PfbArrayConnection -RemoteName 'remote-fb-dc2' -Throttle @{ window_limit = 2097152 } `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['throttle']['window_limit'] -eq 2097152
            }
        }

        It 'omits every body key when no typed body parameter is supplied' {
            Update-PfbArrayConnection -RemoteName 'remote-fb-dc2' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.Count -eq 0
            }
        }

        It 'targets the connection by id when -Id is used' {
            Update-PfbArrayConnection -Id 'conn-1' -ManagementAddress '10.0.2.101' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['ids'] -eq 'conn-1' -and -not $QueryParams.ContainsKey('names')
            }
        }
    }

    Context '-RemoteId is a selector (#88)' {
        It 'selects by remote_ids alone with a typed body parameter' {
            Update-PfbArrayConnection -RemoteId 'remote-1' -ManagementAddress '10.0.2.101' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Endpoint -eq 'array-connections' -and
                $QueryParams['remote_ids'] -eq 'remote-1' -and
                -not $QueryParams.ContainsKey('remote_names') -and -not $QueryParams.ContainsKey('ids') -and
                $Body['management_address'] -eq '10.0.2.101'
            }
        }

        It 'selects by remote_ids alone with -Attributes' {
            Update-PfbArrayConnection -RemoteId 'remote-1' -Attributes @{ management_address = '10.0.2.101' } `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['remote_ids'] -eq 'remote-1' -and
                -not $QueryParams.ContainsKey('remote_names') -and
                $Body['management_address'] -eq '10.0.2.101'
            }
        }

        It 'composes -Id with -RemoteId and emits both plural keys' {
            Update-PfbArrayConnection -Id 'conn-1' -RemoteId 'remote-1' -ManagementAddress '10.0.2.101' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['ids'] -eq 'conn-1' -and $QueryParams['remote_ids'] -eq 'remote-1' -and
                -not $QueryParams.ContainsKey('remote_names')
            }
        }

        It 'rejects -RemoteName together with -RemoteId at bind time, and makes no API call' {
            # The spec forbids remote_names and remote_ids on the same request. This test
            # replaces an older pair that asserted the combination succeeded.
            { Update-PfbArrayConnection -RemoteName 'remote-fb-dc2' -RemoteId 'remote-1' `
                -ManagementAddress '10.0.2.101' -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
        }

        It 'rejects -RemoteName together with -RemoteId under -Attributes too' {
            { Update-PfbArrayConnection -RemoteName 'remote-fb-dc2' -RemoteId 'remote-1' `
                -Attributes @{ management_address = '10.0.2.101' } -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
        }

        It 'keeps -RemoteId, not -Id, as the parameter that spans the ById and ByRemoteId sets' {
            # Load-bearing shape. -Id + -RemoteId is legal, and the tempting way to express
            # that is to mirror -Id into the ByRemoteId* sets. That silently breaks
            # ByPropertyName binding of a piped connection object, which then falls through
            # to the coercion pass. Mirroring -RemoteId instead keeps both behaviours.
            $cmd = Get-Command Update-PfbArrayConnection
            $paramAttrs = {
                param($p)
                @($cmd.Parameters[$p].Attributes |
                    Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] })
            }
            $setsOf      = { param($p) @((& $paramAttrs $p).ParameterSetName) | Sort-Object }
            $mandatoryIn = {
                param($p, $set)
                @(& $paramAttrs $p | Where-Object { $_.ParameterSetName -eq $set })[0].Mandatory
            }

            & $setsOf 'Id' | Should -Be @('ByIdAttributes', 'ByIdIndividual')
            & $setsOf 'RemoteId' | Should -Be @(
                'ByIdAttributes', 'ByIdIndividual', 'ByRemoteIdAttributes', 'ByRemoteIdIndividual')

            # The Mandatory flags are the other half of the shape. Every set must carry
            # exactly one mandatory selector, or a call could resolve with no selector key
            # at all and PATCH every array connection on the appliance.
            & $mandatoryIn 'Id'         'ByIdIndividual'         | Should -BeTrue
            & $mandatoryIn 'Id'         'ByIdAttributes'         | Should -BeTrue
            & $mandatoryIn 'RemoteId'   'ByRemoteIdIndividual'   | Should -BeTrue
            & $mandatoryIn 'RemoteId'   'ByRemoteIdAttributes'   | Should -BeTrue
            & $mandatoryIn 'RemoteName' 'ByRemoteNameIndividual' | Should -BeTrue
            & $mandatoryIn 'RemoteName' 'ByRemoteNameAttributes' | Should -BeTrue

            # -RemoteId spans into the ById* sets and must stay OPTIONAL there --
            # mandatory would stop -Id from selecting alone.
            & $mandatoryIn 'RemoteId' 'ByIdIndividual' | Should -BeFalse
            & $mandatoryIn 'RemoteId' 'ByIdAttributes' | Should -BeFalse
        }

        It 'refuses a selector-less call and patches nothing' {
            # Observable half of the mandatory contract above. The default set is
            # ByRemoteNameIndividual, whose mandatory -RemoteName is the only thing stopping
            # a bare call from resolving into a fleet-wide PATCH.
            { Update-PfbArrayConnection -ManagementAddress '10.0.2.101' `
                -Confirm:$false -Array $fakeArray -ErrorAction Stop } | Should -Throw

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
        }

        It 'omits remote_ids entirely when not supplied' {
            Update-PfbArrayConnection -RemoteName 'remote-fb-dc2' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                -not $QueryParams.ContainsKey('remote_ids')
            }
        }
    }

    Context '-Attributes remains supported and is mutually exclusive' {
        It 'still sends a raw -Attributes body' {
            Update-PfbArrayConnection -RemoteName 'remote-fb-dc2' -Attributes @{ management_address = '10.0.2.101' } `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['management_address'] -eq '10.0.2.101'
            }
        }

        It 'rejects -Attributes combined with a typed parameter at bind time' {
            { Update-PfbArrayConnection -RemoteName 'remote-fb-dc2' -ManagementAddress '10.0.2.101' `
                -Attributes @{ management_address = 'y' } -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'
        }
    }

    Context 'constraint compliance' {
        It 'puts no ValidateSet on -<Parameter> (constraint 3, no spec enum)' -ForEach @(
            @{ Parameter = 'ManagementAddress' }
            @{ Parameter = 'ReplicationAddresses' }
            @{ Parameter = 'CaCertificateGroup' }
            @{ Parameter = 'Encrypted' }
            @{ Parameter = 'Remote' }
            @{ Parameter = 'Throttle' }
            @{ Parameter = 'RemoteId' }
            @{ Parameter = 'RemoteName' }
        ) {
            $attrs = (Get-Command Update-PfbArrayConnection).Parameters[$Parameter].Attributes
            @($attrs | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).Count |
                Should -Be 0
        }
    }

    Context 'issue #64 -- the dead `names` key is gone' {
        It 'sends remote_names, never names' {
            Update-PfbArrayConnection -RemoteName 'FB-B' -ManagementAddress '10.0.2.101' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['remote_names'] -eq 'FB-B' -and -not $QueryParams.ContainsKey('names')
            }
        }

        It 'still binds -Name through the alias, and emits remote_names for it' {
            Update-PfbArrayConnection -Name 'FB-B' -ManagementAddress '10.0.2.101' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['remote_names'] -eq 'FB-B' -and -not $QueryParams.ContainsKey('names')
            }
        }

        It 'declares Name as an alias of -RemoteName' {
            (Get-Command Update-PfbArrayConnection).Parameters['RemoteName'].Aliases |
                Should -Contain 'Name'
        }

        It 'no longer declares a -Name parameter of its own' {
            (Get-Command Update-PfbArrayConnection).Parameters.Keys | Should -Not -Contain 'Name'
        }
    }

    Context 'issue #64 -- pipeline binding by property name on -RemoteName' {
        It 'binds -RemoteName by property name from a user-built object' {
            [pscustomobject]@{ RemoteName = 'FB-B' } |
                Update-PfbArrayConnection -Throttle @{ default_limit = 1073741824 } `
                    -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['remote_names'] -eq 'FB-B' -and -not $QueryParams.ContainsKey('ids')
            }
        }

        It 'binds by property name through the Name alias' {
            [pscustomobject]@{ Name = 'FB-B' } |
                Update-PfbArrayConnection -Throttle @{ default_limit = 1073741824 } `
                    -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['remote_names'] -eq 'FB-B' -and -not $QueryParams.ContainsKey('ids')
            }
        }
    }

    Context 'issue #64 -- pipeline binding on -Id' {
        It 'binds a piped connection object by id' {
            [PSCustomObject]@{ id = 'conn-9' } |
                Update-PfbArrayConnection -Throttle @{ default_limit = 1073741824 } `
                    -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['ids'] -eq 'conn-9'
            }
        }

        It 'does NOT coerce a piped object into -RemoteName (binding-order guard)' {
            [PSCustomObject]@{ id = 'conn-9' } |
                Update-PfbArrayConnection -Throttle @{ default_limit = 1073741824 } `
                    -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                -not $QueryParams.ContainsKey('remote_names') -and
                $QueryParams['ids'] -notlike '*@{*'
            }
        }

        It 'processes each of several piped connections individually' {
            @([PSCustomObject]@{ id = 'conn-1' }, [PSCustomObject]@{ id = 'conn-2' }) |
                Update-PfbArrayConnection -Throttle @{ default_limit = 1 } `
                    -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 2 -Exactly
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['ids'] -eq 'conn-2'
            }
        }

        It 'makes no API call for the composite -Id + -RemoteId form under -WhatIf' {
            # The composite form is the one whose ShouldProcess target is composed rather than
            # chosen (see ArrayConnection.ShouldProcessTarget.Tests.ps1); composing the string
            # must not change the fact that -WhatIf still short-circuits the PATCH.
            Update-PfbArrayConnection -Id 'conn-1' -RemoteId 'r-77' `
                -Attributes @{ management_address = '10.0.2.101' } -WhatIf -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
        }
    }
}
