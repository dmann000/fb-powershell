#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

# Issue #126. The denylist IS the policy at runtime, so its membership is the whole safety
# argument -- there is no algorithm behind it to fall back on. These assertions exist so that
# adding or removing an entry is a deliberate, reviewed act rather than a quiet edit.

BeforeAll {
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule
}

Describe 'PfbNonSelectorQueryKeys' {

    It 'contains exactly the twelve classified non-selector keys' {
        InModuleScope PureStorageFlashBladePowerShell {
            $expected = @(
                'current_fleet_only', 'destroyed', 'end_time', 'expose_api_token', 'flagged',
                'limit', 'protocols', 'resolution', 'sort', 'start_time', 'total_only', 'type'
            )

            $actual = [string[]]@($script:PfbNonSelectorQueryKeys)
            [System.Array]::Sort($actual, [System.StringComparer]::Ordinal)

            $actual.Count | Should -Be 12
            ($actual -join ',') | Should -Be ($expected -join ',')
        }
    }

    It 'does not contain filter, the one caller-authored predicate' {
        # The deliberate divergence from the alternative policy. With -Filter "name='x'" the
        # result is bounded by a predicate the CALLER wrote, which is exactly what a selector is
        # under this spec. Add it here and every filtered empty-pipeline read stops working.
        InModuleScope PureStorageFlashBladePowerShell {
            $script:PfbNonSelectorQueryKeys.Contains('filter') | Should -BeFalse
        }
    }

    It 'does not contain any centrally injected key the predicate cannot see' {
        # All three would look like reasonable entries and all three are wrong. context_names is
        # injected into a CLONE inside Invoke-PfbApiRequest AFTER the guard has run;
        # continuation_token is written inside the pagination loop, also after; allow_errors is
        # never written into a query hashtable at all -- it exists only as
        # $script:PfbAllowErrorsParameterName, read as a capability-map discriminator.
        # Listing any of them would imply the predicate inspects the fully built wire query. It
        # inspects the PRE-REQUEST query state.
        InModuleScope PureStorageFlashBladePowerShell {
            foreach ($key in @('context_names', 'continuation_token', 'allow_errors')) {
                $script:PfbNonSelectorQueryKeys.Contains($key) |
                    Should -BeFalse -Because "$key never reaches the hashtable the guard inspects"
            }
        }
    }

    It 'holds wire keys, not parameter names, and compares them ordinally' {
        # Wire keys are lowercase snake_case without exception. A case-insensitive set would
        # silently accept a PascalCase entry, and a PascalCase entry would never match a real
        # query key -- a dead list entry that reads as coverage.
        InModuleScope PureStorageFlashBladePowerShell {
            foreach ($key in $script:PfbNonSelectorQueryKeys) {
                $key | Should -MatchExactly '^[a-z][a-z0-9_]*$' -Because 'wire keys are lowercase snake_case'
            }
            $script:PfbNonSelectorQueryKeys.Contains('Limit') |
                Should -BeFalse -Because 'the comparer must be Ordinal, not OrdinalIgnoreCase'
        }
    }
}
