#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Remove-PfbArrayConnection - selector query keys (#64)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    It 'sends remote_names, never names' {
        Remove-PfbArrayConnection -RemoteName 'FB-B' -Confirm:$false -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'DELETE' -and $Endpoint -eq 'array-connections' -and
            $QueryParams['remote_names'] -eq 'FB-B' -and -not $QueryParams.ContainsKey('names')
        }
    }

    It 'still binds -Name through the alias, and emits remote_names for it' {
        Remove-PfbArrayConnection -Name 'FB-B' -Confirm:$false -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['remote_names'] -eq 'FB-B' -and -not $QueryParams.ContainsKey('names')
        }
    }

    It 'declares Name as an alias of -RemoteName' {
        (Get-Command Remove-PfbArrayConnection).Parameters['RemoteName'].Aliases | Should -Contain 'Name'
    }

    It 'targets the connection by id when -Id is used' {
        Remove-PfbArrayConnection -Id 'conn-1' -Confirm:$false -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['ids'] -eq 'conn-1' -and -not $QueryParams.ContainsKey('remote_names')
        }
    }

    It 'targets the connection by remote_ids when -RemoteId is used alone' {
        Remove-PfbArrayConnection -RemoteId 'r-77' -Confirm:$false -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'DELETE' -and $Endpoint -eq 'array-connections' -and
            $QueryParams['remote_ids'] -eq 'r-77' -and
            -not $QueryParams.ContainsKey('remote_names') -and -not $QueryParams.ContainsKey('ids')
        }
    }

    It 'composes -Id with -RemoteId and emits both plural keys' {
        Remove-PfbArrayConnection -Id 'conn-1' -RemoteId 'r-77' -Confirm:$false -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['ids'] -eq 'conn-1' -and $QueryParams['remote_ids'] -eq 'r-77' -and
            -not $QueryParams.ContainsKey('remote_names')
        }
    }

    It 'omits remote_ids entirely when -RemoteId is not supplied' {
        Remove-PfbArrayConnection -Id 'conn-1' -Confirm:$false -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            -not $QueryParams.ContainsKey('remote_ids')
        }
    }

    It 'rejects -RemoteName together with -RemoteId at bind time, and deletes nothing' {
        # The spec forbids remote_names and remote_ids on the same request; on a DELETE the
        # exclusion has to bite before any call is made.
        { Remove-PfbArrayConnection -RemoteName 'FB-B' -RemoteId 'r-77' -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
            Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
    }

    It 'keeps -RemoteId, not -Id, as the parameter that spans the ById and ByRemoteId sets' {
        # Load-bearing shape. -Id + -RemoteId is legal, and the tempting way to express that
        # is to mirror -Id into the ByRemoteId set. That silently breaks ByPropertyName
        # binding of a piped connection object, which then falls through to the coercion
        # pass. Mirroring -RemoteId instead keeps both behaviours. See the two pipeline
        # tests below, which are the observable half of this contract.
        $cmd = Get-Command Remove-PfbArrayConnection
        $paramAttrs = {
            param($p)
            @($cmd.Parameters[$p].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] })
        }
        $setsOf     = { param($p) @((& $paramAttrs $p).ParameterSetName) | Sort-Object }
        $mandatoryIn = {
            param($p, $set)
            @(& $paramAttrs $p | Where-Object { $_.ParameterSetName -eq $set })[0].Mandatory
        }

        & $setsOf 'Id'       | Should -Be @('ById')
        & $setsOf 'RemoteId' | Should -Be @('ById', 'ByRemoteId')

        # The Mandatory flags are the other half of the shape, and the more dangerous half.
        # This cmdlet has no DefaultParameterSetName; it is safe from a blanket delete only
        # because every set carries exactly one mandatory selector. Making -RemoteId optional
        # in ByRemoteId leaves the set-name lists above untouched, but lets a bare call
        # resolve to ByRemoteId and DELETE array-connections with no selector key at all.
        & $mandatoryIn 'Id'         'ById'         | Should -BeTrue
        & $mandatoryIn 'RemoteName' 'ByRemoteName' | Should -BeTrue
        & $mandatoryIn 'RemoteId'   'ByRemoteId'   | Should -BeTrue

        # -RemoteId is the spanning parameter, so it must stay OPTIONAL in ById --
        # mandatory there would stop -Id from selecting alone.
        & $mandatoryIn 'RemoteId' 'ById' | Should -BeFalse
    }

    It 'refuses a selector-less call and deletes nothing' {
        # Observable half of the mandatory contract above. A no-selector DELETE would target
        # every array connection on the appliance, so it must never reach the wire.
        { Remove-PfbArrayConnection -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
            Should -Throw

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
    }

    It 'puts no ValidateSet on the free-form selector -<Parameter>' -ForEach @(
        @{ Parameter = 'RemoteName' }
        @{ Parameter = 'RemoteId' }
        @{ Parameter = 'Id' }
    ) {
        $attrs = (Get-Command Remove-PfbArrayConnection).Parameters[$Parameter].Attributes
        @($attrs | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).Count |
            Should -Be 0
    }

    It 'binds a piped connection object by id' {
        [PSCustomObject]@{ id = 'conn-9' } |
            Remove-PfbArrayConnection -Confirm:$false -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['ids'] -eq 'conn-9'
        }
    }

    It 'does NOT coerce a piped object into -RemoteName (binding-order guard)' {
        [PSCustomObject]@{ id = 'conn-9' } |
            Remove-PfbArrayConnection -Confirm:$false -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            -not $QueryParams.ContainsKey('remote_names') -and $QueryParams['ids'] -notlike '*@{*'
        }
    }

    It 'binds -RemoteName by property name from a user-built object' {
        [pscustomobject]@{ RemoteName = 'FB-B' } |
            Remove-PfbArrayConnection -Confirm:$false -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['remote_names'] -eq 'FB-B' -and -not $QueryParams.ContainsKey('ids')
        }
    }

    It 'binds by property name through the Name alias' {
        [pscustomobject]@{ Name = 'FB-B' } |
            Remove-PfbArrayConnection -Confirm:$false -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['remote_names'] -eq 'FB-B' -and -not $QueryParams.ContainsKey('ids')
        }
    }

    It 'still accepts a bare remote name piped by value' {
        'FB-B' | Remove-PfbArrayConnection -Confirm:$false -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['remote_names'] -eq 'FB-B'
        }
    }

    It 'rejects a piped object that carries no id/name property instead of stringifying it' {
        # -Id absorbs a real connection object at binding pass 2. An object without id, name or
        # remoteName falls through to pass 3 and is ToString()-ed into -RemoteName, so the guard
        # is reachable here too -- and this cmdlet is a DELETE.
        {
            [PSCustomObject]@{ status = 'connected'; type = 'async-replication' } |
                Remove-PfbArrayConnection -Confirm:$false -Array $fakeArray
        } | Should -Throw -ExpectedMessage '*stringified object*'

        # The guard is terminating and fires before request assembly, so no DELETE is
        # issued at all. Without this assertion a guard moved after assembly, or made
        # non-terminating, would still pass while remote_names=@{status=connected...}
        # went out on the wire.
        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
    }

    It 'makes no API call when ShouldProcess is declined via -WhatIf' {
        Remove-PfbArrayConnection -RemoteName 'FB-B' -WhatIf -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
    }

    It 'makes no API call for the composite -Id + -RemoteId form under -WhatIf' {
        # The composite form is the one whose ShouldProcess target is composed rather than
        # chosen (see ArrayConnection.ShouldProcessTarget.Tests.ps1); composing the string
        # must not change the fact that -WhatIf still short-circuits the DELETE.
        Remove-PfbArrayConnection -Id 'conn-1' -RemoteId 'r-77' -WhatIf -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
    }
}
