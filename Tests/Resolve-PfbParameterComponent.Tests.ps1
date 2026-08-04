#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force
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
