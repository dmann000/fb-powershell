#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule
}

Describe 'Resolve-PfbParameterComponent' {

    # Fixtures mimic ConvertFrom-Json output: PSCustomObject, where a JSON null becomes a
    # PRESENT property whose value is $null. That is the case the whole function exists for.
    BeforeAll {
        $script:defaults = [PSCustomObject]@{
            context_names = 'Context_names_get'
            limit         = 'Limit'
        }
    }

    Context 'Step 1: the override key is present' {

        It 'returns the override value and ignores a differing default' {
            $entry = [PSCustomObject]@{
                parameterComponentOverrides = [PSCustomObject]@{ context_names = 'Context_names' }
            }

            $result = InModuleScope PureStorageFlashBladePowerShell -Parameters @{ E = $entry; D = $script:defaults } {
                param($E, $D)
                Resolve-PfbParameterComponent -EndpointEntry $E -ParameterName 'context_names' -ParameterComponentDefaults $D
            }

            $result | Should -Be 'Context_names'
        }

        It 'REGRESSION: a key present with a NULL value returns $null and does NOT fall through to a matching default' {
            # This is the defect the extraction exists to prevent. A naive
            # `if ($overrides.$name)` implementation passes every other test in this file
            # and fails only this one.
            $entry = [PSCustomObject]@{
                parameterComponentOverrides = [PSCustomObject]@{ context_names = $null }
            }

            $result = InModuleScope PureStorageFlashBladePowerShell -Parameters @{ E = $entry; D = $script:defaults } {
                param($E, $D)
                Resolve-PfbParameterComponent -EndpointEntry $E -ParameterName 'context_names' -ParameterComponentDefaults $D
            }

            $result | Should -BeNullOrEmpty
            # Assert the SPECIFIC wrong answer is absent, not merely that the result is falsy --
            # 'returns $null' alone cannot distinguish this case from step 3.
            $result | Should -Not -Be 'Context_names_get'
        }
    }

    Context 'Step 2: the override key is absent' {

        It 'falls through to the default when the endpoint has an overrides object without this key' {
            $entry = [PSCustomObject]@{
                parameterComponentOverrides = [PSCustomObject]@{ sort = 'Sort' }
            }

            $result = InModuleScope PureStorageFlashBladePowerShell -Parameters @{ E = $entry; D = $script:defaults } {
                param($E, $D)
                Resolve-PfbParameterComponent -EndpointEntry $E -ParameterName 'context_names' -ParameterComponentDefaults $D
            }

            $result | Should -Be 'Context_names_get'
        }

        It 'falls through to the default when the endpoint has no overrides object at all' {
            $entry = [PSCustomObject]@{ minVersion = '2.23' }

            $result = InModuleScope PureStorageFlashBladePowerShell -Parameters @{ E = $entry; D = $script:defaults } {
                param($E, $D)
                Resolve-PfbParameterComponent -EndpointEntry $E -ParameterName 'context_names' -ParameterComponentDefaults $D
            }

            $result | Should -Be 'Context_names_get'
        }
    }

    Context 'Step 3: no signal anywhere' {

        It 'returns $null when neither the override nor the default has the parameter' {
            $entry = [PSCustomObject]@{ minVersion = '2.23' }

            $result = InModuleScope PureStorageFlashBladePowerShell -Parameters @{ E = $entry; D = $script:defaults } {
                param($E, $D)
                Resolve-PfbParameterComponent -EndpointEntry $E -ParameterName 'not_a_real_parameter' -ParameterComponentDefaults $D
            }

            $result | Should -BeNullOrEmpty
        }

        It 'returns $null without throwing when the defaults table is $null' {
            $entry = [PSCustomObject]@{ minVersion = '2.23' }

            $result = InModuleScope PureStorageFlashBladePowerShell -Parameters @{ E = $entry } {
                param($E)
                Resolve-PfbParameterComponent -EndpointEntry $E -ParameterName 'context_names' -ParameterComponentDefaults $null
            }

            $result | Should -BeNullOrEmpty
        }
    }

    Context 'Key matching is exact, and works on multi-key containers' {

        # These close mutation gaps found in review: four plausible wrong implementations
        # passed every test above. Each It below kills at least one of them.

        It 'MUTATION GUARD: honours a present key on an overrides object holding SEVERAL keys' {
            # Kills reversed operands -- ($ParameterName -contains $overrides.PSObject.Properties.Name).
            # With a single-key overrides object that accidentally works (scalar vs scalar);
            # with two or more keys the right-hand side becomes an array, the test is never
            # true, and the override is silently discarded in favour of the default. The real
            # Data/PfbCapabilityMap.json has 40 multi-key overrides objects, 18 of them
            # containing context_names -- so this is the original bug class on real endpoints.
            $entry = [PSCustomObject]@{
                parameterComponentOverrides = [PSCustomObject]@{
                    sort          = 'Sort'
                    context_names = $null
                    limit         = 'Limit'
                }
            }

            $result = InModuleScope PureStorageFlashBladePowerShell -Parameters @{ E = $entry; D = $script:defaults } {
                param($E, $D)
                Resolve-PfbParameterComponent -EndpointEntry $E -ParameterName 'context_names' -ParameterComponentDefaults $D
            }

            $result | Should -BeNullOrEmpty
            $result | Should -Not -Be 'Context_names_get'
        }

        It 'MUTATION GUARD: does not treat a substring/regex-adjacent key name as a match' {
            # Kills -match and -like. 'ids' regex-matches the key name 'ids_or_names', which
            # would wrongly enter step 1 and return that key's $null instead of the default.
            # Both names are real API parameters; 'ids' is in the real defaults table.
            $entry = [PSCustomObject]@{
                parameterComponentOverrides = [PSCustomObject]@{ ids_or_names = $null }
            }
            $defaults = [PSCustomObject]@{ ids = 'Ids' }

            $result = InModuleScope PureStorageFlashBladePowerShell -Parameters @{ E = $entry; D = $defaults } {
                param($E, $D)
                Resolve-PfbParameterComponent -EndpointEntry $E -ParameterName 'ids' -ParameterComponentDefaults $D
            }

            $result | Should -Be 'Ids'
        }

        It 'falls through to the default when parameterComponentOverrides is present but NULL' {
            # Kills a guard written as
            # ($EndpointEntry.PSObject.Properties.Name -contains 'parameterComponentOverrides'),
            # which treats a null overrides object as authoritative.
            $entry = [PSCustomObject]@{ parameterComponentOverrides = $null }

            $result = InModuleScope PureStorageFlashBladePowerShell -Parameters @{ E = $entry; D = $script:defaults } {
                param($E, $D)
                Resolve-PfbParameterComponent -EndpointEntry $E -ParameterName 'context_names' -ParameterComponentDefaults $D
            }

            $result | Should -Be 'Context_names_get'
        }

        It 'falls through to the default when the overrides object is present but EMPTY' {
            # An empty PSCustomObject is TRUTHY, so a truthiness guard would not save this.
            $entry = [PSCustomObject]@{ parameterComponentOverrides = [PSCustomObject]@{} }

            $result = InModuleScope PureStorageFlashBladePowerShell -Parameters @{ E = $entry; D = $script:defaults } {
                param($E, $D)
                Resolve-PfbParameterComponent -EndpointEntry $E -ParameterName 'context_names' -ParameterComponentDefaults $D
            }

            $result | Should -Be 'Context_names_get'
        }
    }

    Context 'Dictionary-shaped input (the in-memory generator shape)' {

        # tools/Build-PfbCapabilityMap.ps1 builds parameterComponentDefaults and
        # parameterComponentOverrides as [ordered]@{}. Any tools/ caller resolving against
        # the map it just built -- rather than the JSON round-trip -- passes dictionaries.
        # .PSObject.Properties.Name returns the CLR surface for those, not the keys, so a
        # PSCustomObject-only implementation is wrong for every such caller.

        It 'honours a present-but-null key in an ORDERED DICTIONARY overrides object' {
            $overrides = [ordered]@{ sort = 'Sort'; context_names = $null }
            $entry = [PSCustomObject]@{ parameterComponentOverrides = $overrides }

            $result = InModuleScope PureStorageFlashBladePowerShell -Parameters @{ E = $entry; D = $script:defaults } {
                param($E, $D)
                Resolve-PfbParameterComponent -EndpointEntry $E -ParameterName 'context_names' -ParameterComponentDefaults $D
            }

            $result | Should -BeNullOrEmpty
            $result | Should -Not -Be 'Context_names_get'
        }

        It 'returns the override value from a HASHTABLE overrides object' {
            $entry = @{ parameterComponentOverrides = @{ context_names = 'Context_names' } }

            $result = InModuleScope PureStorageFlashBladePowerShell -Parameters @{ E = $entry; D = $script:defaults } {
                param($E, $D)
                Resolve-PfbParameterComponent -EndpointEntry $E -ParameterName 'context_names' -ParameterComponentDefaults $D
            }

            $result | Should -Be 'Context_names'
        }

        It 'resolves against a DICTIONARY defaults table' {
            $entry = [PSCustomObject]@{ minVersion = '2.23' }
            $defaults = [ordered]@{ context_names = 'Context_names_get' }

            $result = InModuleScope PureStorageFlashBladePowerShell -Parameters @{ E = $entry; D = $defaults } {
                param($E, $D)
                Resolve-PfbParameterComponent -EndpointEntry $E -ParameterName 'context_names' -ParameterComponentDefaults $D
            }

            $result | Should -Be 'Context_names_get'
        }

        It 'does not mistake a dictionary INTRINSIC member for a parameter key' {
            # A hashtable's .PSObject.Properties.Name exposes Count/Keys/Values/... A
            # PSObject-only presence test would report 'Count' as present and return the
            # item count -- an [int], violating the declared [string] output.
            $entry = @{ parameterComponentOverrides = @{ a = 1; b = 2 } }

            $result = InModuleScope PureStorageFlashBladePowerShell -Parameters @{ E = $entry } {
                param($E)
                Resolve-PfbParameterComponent -EndpointEntry $E -ParameterName 'Count' -ParameterComponentDefaults $null
            }

            $result | Should -BeNullOrEmpty
            $result | Should -Not -Be 2
        }
    }

    Context 'Parameter-name independence' {

        It 'resolves a parameter other than context_names through the same contract' {
            # allow_errors needs this in Phase 2; the function must not be context_names-specific.
            $entry = [PSCustomObject]@{
                parameterComponentOverrides = [PSCustomObject]@{ limit = $null }
            }

            $result = InModuleScope PureStorageFlashBladePowerShell -Parameters @{ E = $entry; D = $script:defaults } {
                param($E, $D)
                Resolve-PfbParameterComponent -EndpointEntry $E -ParameterName 'limit' -ParameterComponentDefaults $D
            }

            $result | Should -BeNullOrEmpty
        }
    }
}
