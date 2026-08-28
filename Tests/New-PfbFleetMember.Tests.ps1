#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'New-PfbFleetMember - typed body/query parameters (#31, confirmed wire-contract bug)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'confirmed bug (issue #38): POST /fleets/members takes fleet_ids/fleet_names query + a members body, NOT member_names query' {
        It 'sends the fleet key and member self-reference in the request body, per the OpenAPI spec (FleetMemberPost)' {
            New-PfbFleetMember -FleetName 'fleet-prod' `
                -Members @{ key = 'fleet-key-abc'; member = @{ id = 'this-array-id' } } `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Endpoint -eq 'fleets/members' -and
                $QueryParams['fleet_names'] -eq 'fleet-prod' -and
                @($Body['members']).Count -eq 1 -and
                @($Body['members'])[0]['key'] -eq 'fleet-key-abc' -and
                @($Body['members'])[0]['member']['id'] -eq 'this-array-id'
            }
        }

        It 'never sends a member_names query parameter (regression: POST /fleets/members has no member_names -- confirmed via OpenAPI spec, the endpoint could never have worked with the old shape)' {
            New-PfbFleetMember -FleetName 'fleet-prod' `
                -Members @{ key = 'fleet-key-abc'; member = @{ id = 'this-array-id' } } `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                -not $QueryParams.ContainsKey('member_names') -and -not $QueryParams.ContainsKey('member_ids')
            }
        }

        It 'has no -MemberName parameter (removed: member_names is not a valid query parameter for POST /fleets/members)' {
            (Get-Command New-PfbFleetMember).Parameters.Keys | Should -Not -Contain 'MemberName'
        }
    }

    Context 'fleet selector' {
        It 'sends fleet_ids when -FleetId is used (new query parameter)' {
            New-PfbFleetMember -FleetId 'fleet-1' `
                -Members @{ key = 'fleet-key-abc'; member = @{ id = 'this-array-id' } } `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['fleet_ids'] -eq 'fleet-1' -and -not $QueryParams.ContainsKey('fleet_names')
            }
        }

        It 'omits fleet_names/fleet_ids entirely when neither is supplied (constraint 19, no mandatory throw)' {
            New-PfbFleetMember -Members @{ key = 'k'; member = @{ id = 'i' } } -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                -not $QueryParams.ContainsKey('fleet_names') -and -not $QueryParams.ContainsKey('fleet_ids')
            }
        }
    }

    Context '-Members composite array (constraint 8c: item schema has `key`, outside {id,name,resource_type})' {
        It 'accepts multiple member entries' {
            New-PfbFleetMember -FleetName 'fleet-prod' -Members @(
                @{ key = 'k1'; member = @{ id = 'a1' } },
                @{ key = 'k1'; member = @{ id = 'a2' } }
            ) -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                @($Body['members']).Count -eq 2
            }
        }

        It 'omits the members body key entirely when not supplied (empty write is permitted, constraint 19)' {
            New-PfbFleetMember -FleetName 'fleet-prod' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                -not $Body.ContainsKey('members')
            }
        }

        It 'sends an EMPTY array for -Members @() so the list can be cleared, not omit the key (constraint 18: does not apply to [hashtable[]], unlike a scalar [hashtable])' {
            New-PfbFleetMember -FleetName 'fleet-prod' -Members @() -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('members') -and @($Body['members']).Count -eq 0
            }
        }
    }

    Context '-FleetKey convenience path (build the body from a New-PfbFleetKey key plus self-identification)' {
        BeforeEach {
            Mock -ModuleName PureStorageFlashBladePowerShell Get-PfbArray {
                [PSCustomObject]@{ id = 'self-array-id'; name = 'fb-a' }
            }
        }

        It 'builds the members body from -FleetKey and the joining array own id' {
            New-PfbFleetMember -FleetName 'fleet-prod' -FleetKey 'fleet-key-abc' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Endpoint -eq 'fleets/members' -and
                $QueryParams['fleet_names'] -eq 'fleet-prod' -and
                @($Body['members']).Count -eq 1 -and
                @($Body['members'])[0]['key'] -eq 'fleet-key-abc' -and
                @($Body['members'])[0]['member']['id'] -eq 'self-array-id'
            }
        }

        It 'sends the same wire shape as the equivalent explicit -Members call, so the convenience path is a pure ergonomics layer' {
            $script:captured = @()
            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest {
                $script:captured += , ($Body | ConvertTo-Json -Depth 6 -Compress)
            }

            New-PfbFleetMember -FleetName 'fleet-prod' -FleetKey 'k' -Confirm:$false -Array $fakeArray
            New-PfbFleetMember -FleetName 'fleet-prod' `
                -Members @{ key = 'k'; member = @{ id = 'self-array-id' } } `
                -Confirm:$false -Array $fakeArray

            $script:captured.Count | Should -Be 2
            $script:captured[0] | Should -Be $script:captured[1]
        }

        It 'resolves the joining array over the connection it was given, not the default connection' {
            New-PfbFleetMember -FleetName 'fleet-prod' -FleetKey 'k' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Get-PfbArray -Times 1 -Exactly -ParameterFilter {
                $Array.Endpoint -eq 'fb.example.test'
            }
        }

        It 'takes the first array record, since GET /arrays returns a list of one for the array being talked to' {
            Mock -ModuleName PureStorageFlashBladePowerShell Get-PfbArray {
                @([PSCustomObject]@{ id = 'first'; name = 'fb-a' }, [PSCustomObject]@{ id = 'second'; name = 'fb-b' })
            }

            New-PfbFleetMember -FleetName 'fleet-prod' -FleetKey 'k' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                @($Body['members'])[0]['member']['id'] -eq 'first'
            }
        }

        It 'throws rather than POSTing a body with an empty member id when the array id cannot be resolved' {
            Mock -ModuleName PureStorageFlashBladePowerShell Get-PfbArray { }

            { New-PfbFleetMember -FleetName 'fleet-prod' -FleetKey 'k' -Confirm:$false -Array $fakeArray } |
                Should -Throw -ExpectedMessage '*-Members*'

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
        }

        It 'accepts -FleetId as the selector alongside -FleetKey, because the selector says WHICH fleet and the key only authorises the join' {
            New-PfbFleetMember -FleetId 'fleet-1' -FleetKey 'k' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['fleet_ids'] -eq 'fleet-1' -and -not $QueryParams.ContainsKey('fleet_names') -and
                @($Body['members'])[0]['key'] -eq 'k'
            }
        }

        It 'rejects -FleetKey and -Members together at bind time rather than silently preferring one' {
            { New-PfbFleetMember -FleetName 'fleet-prod' -FleetKey 'k' `
                    -Members @{ key = 'k'; member = @{ id = 'i' } } -Confirm:$false -Array $fakeArray } |
                Should -Throw
        }

        It 'never calls Get-PfbArray on the -Members path, so the passthrough shape stays exactly what the caller wrote' {
            New-PfbFleetMember -FleetName 'fleet-prod' -Members @{ key = 'k'; member = @{ id = 'i' } } `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Get-PfbArray -Times 0 -Exactly
        }
    }

    Context 'constraint compliance' {
        It 'puts no ValidateSet on -<Parameter> (constraint 3, no spec enum)' -ForEach @(
            @{ Parameter = 'FleetName' }
            @{ Parameter = 'FleetId' }
            @{ Parameter = 'FleetKey' }
            @{ Parameter = 'Members' }
        ) {
            $attrs = (Get-Command New-PfbFleetMember).Parameters[$Parameter].Attributes
            @($attrs | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).Count |
                Should -Be 0
        }
    }
}
