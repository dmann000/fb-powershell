#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Empty-pipeline regression coverage for Get-PfbRemoteArray (#121).
.DESCRIPTION
    Get-PfbRemoteArray is the one cmdlet in the guarded population where the generator's
    usual guard position -- immediately above the request -- would have been INERT rather
    than protective. Its end block writes `current_fleet_only` on BOTH branches of an
    if/else, so $queryParams is never empty by the time the request is issued, and a guard
    below that write could never fire.

    Its guard is therefore hand-placed ABOVE that write, on the design's own terms: the
    policy is "no SELECTOR reached the query", and current_fleet_only is a scope flag, not
    a selector. These two tests pin both halves of that placement -- an empty pipeline
    issues nothing, and an ordinary direct call still issues exactly one request that still
    carries the flag.
#>

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1') -Force

    $script:fakeConnection = [PSCustomObject]@{
        PSTypeName   = 'PureStorage.FlashBlade.Connection'
        HttpEndpoint = 'https://fb.test'
        Endpoint     = 'fb.test'
        AuthToken    = 'tok'
        ApiVersion   = '2.26'
    }
}

Describe 'Get-PfbRemoteArray - empty pipeline guard' {

    It 'issues no request at all when piped an empty collection' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { @() }

        @() | Get-PfbRemoteArray -Array $script:fakeConnection | Out-Null

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
    }

    It 'still issues exactly one request carrying current_fleet_only on a direct call' {
        # The guard sits ABOVE the current_fleet_only write, so this is the assertion that
        # proves it did not swallow the ordinary path or drop the flag with it.
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { @() }

        Get-PfbRemoteArray -Array $script:fakeConnection | Out-Null

        # $PSBoundParameters is EMPTY inside a -ParameterFilter; assert on the bound
        # variable instead, or the filter passes vacuously.
        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['current_fleet_only'] -eq 'true'
        }
    }

    It 'still issues a request when a name arrives down the pipeline' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { @() }

        'remote-dc2' | Get-PfbRemoteArray -Array $script:fakeConnection | Out-Null

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['names'] -eq 'remote-dc2'
        }
    }
}
