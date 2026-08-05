#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeConnection = [PSCustomObject]@{
        PSTypeName   = 'PureStorage.FlashBlade.Connection'
        HttpEndpoint = 'https://fb.test'
        Endpoint     = 'fb.test'
        AuthToken    = 'tok'
        ApiVersion   = '2.26'
    }
}

Describe 'Get-PfbFleetMember - top-level MemberName/FleetName decoration' {

    It 'adds MemberName and FleetName from the nested member/fleet objects' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest {
            @(
                [PSCustomObject]@{
                    member = [PSCustomObject]@{ name = 'fb-a'; id = 'm1'; resource_type = 'arrays' }
                    fleet  = [PSCustomObject]@{ name = 'cc-test-fleet'; id = 'f1' }
                    status = 'connected'
                },
                [PSCustomObject]@{
                    member = [PSCustomObject]@{ name = 'fb-c'; id = 'm2'; resource_type = 'arrays' }
                    fleet  = [PSCustomObject]@{ name = 'cc-test-fleet'; id = 'f1' }
                    status = 'connected'
                }
            )
        }

        $result = @(Get-PfbFleetMember -Array $script:fakeConnection)

        $result.Count | Should -Be 2
        @($result | ForEach-Object { $_.MemberName }) | Should -Be @('fb-a', 'fb-c')
        @($result | ForEach-Object { $_.FleetName })  | Should -Be @('cc-test-fleet', 'cc-test-fleet')
    }

    It 'is ADDITIVE: the raw nested member/fleet objects survive untouched' {
        # Existing callers reach .member.name directly. This must not become a reshape.
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest {
            [PSCustomObject]@{
                member         = [PSCustomObject]@{ name = 'fb-a'; id = 'm1' }
                fleet          = [PSCustomObject]@{ name = 'cc-test-fleet'; id = 'f1' }
                status         = 'connected'
                status_details = 'all good'
                coordinator_of = @()
            }
        }

        $result = Get-PfbFleetMember -Array $script:fakeConnection

        $result.member.name | Should -Be 'fb-a'
        $result.member.id | Should -Be 'm1'
        $result.fleet.name | Should -Be 'cc-test-fleet'
        $result.status | Should -Be 'connected'
        $result.status_details | Should -Be 'all good'
        $result.PSObject.Properties.Name | Should -Contain 'coordinator_of'
    }

    It 'yields $null rather than throwing when the nested data is absent or partial' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest {
            @(
                [PSCustomObject]@{ fleet = [PSCustomObject]@{ name = 'f' }; status = 'x' }, # no member
                [PSCustomObject]@{ member = [PSCustomObject]@{ id = 'm3' }; status = 'x' }, # member, no name
                [PSCustomObject]@{ status = 'x' }                                              # neither
            )
        }

        $result = @(Get-PfbFleetMember -Array $script:fakeConnection)

        $result.Count | Should -Be 3
        $result[0].MemberName | Should -BeNullOrEmpty
        $result[0].FleetName | Should -Be 'f'
        $result[1].MemberName | Should -BeNullOrEmpty
        $result[2].MemberName | Should -BeNullOrEmpty
        $result[2].FleetName | Should -BeNullOrEmpty
    }

    It 'decorates every item across an AutoPaginate multi-page result, not just the first' {
        # -AutoPaginate hands back the accumulated items; a decorate-the-first-page
        # implementation would leave later pages bare.
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest {
            @(1..7 | ForEach-Object {
                    [PSCustomObject]@{
                        member = [PSCustomObject]@{ name = "fb-$_" }
                        fleet  = [PSCustomObject]@{ name = 'cc-test-fleet' }
                    }
                })
        }

        $result = @(Get-PfbFleetMember -Array $script:fakeConnection)

        $result.Count | Should -Be 7
        @($result | Where-Object { $_.MemberName }).Count | Should -Be 7
        @($result | Where-Object { $_.FleetName }).Count  | Should -Be 7
        $result[6].MemberName | Should -Be 'fb-7'
    }

    It 'does NOT add IsLocal' {
        # is_local is relative to the CALL'S CONTEXT, not the connection: a documented
        # Where-Object { -not $_.IsLocal } idiom would silently select a different array
        # once a context is active. Determining the local array belongs to the connection.
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest {
            [PSCustomObject]@{
                member   = [PSCustomObject]@{ name = 'fb-a' }
                fleet    = [PSCustomObject]@{ name = 'cc-test-fleet' }
                is_local = $true
            }
        }

        $result = Get-PfbFleetMember -Array $script:fakeConnection

        $result.PSObject.Properties.Name | Should -Not -Contain 'IsLocal'
    }

    It 'returns nothing and does not throw when the API returns no members' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { @() }
        @(Get-PfbFleetMember -Array $script:fakeConnection).Count | Should -Be 0
    }

    It 'still forwards fleet_names and member_names as query parameters' {
        # Regression guard: the decoration must not disturb the existing query building.
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { @() }

        Get-PfbFleetMember -Array $script:fakeConnection -FleetName 'cc-test-fleet' -MemberName 'fb-a', 'fb-c' | Out-Null

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['fleet_names'] -eq 'cc-test-fleet' -and $QueryParams['member_names'] -eq 'fb-a,fb-c'
        }
    }
}
