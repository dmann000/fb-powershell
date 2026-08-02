#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.26'; AuthToken = 'x' }
}

Describe 'Set-PfbPresetWorkload - routed through Invoke-PfbApiRequest (#76)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod { }
    }

    Context 'the shared request path is used' {
        It 'sends PUT to presets/workload' {
            Set-PfbPresetWorkload -Name 'analytics' -Attributes @{ name = 'analytics' } -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PUT' -and $Endpoint -eq 'presets/workload'
            }
        }

        # The whole point of #76: this cmdlet used to call Invoke-RestMethod itself, which
        # skipped capability gating, error normalisation, and Bearer-token auth. If a direct
        # call ever comes back, this is the test that says so.
        It 'makes no direct Invoke-RestMethod call' {
            Set-PfbPresetWorkload -Name 'analytics' -Attributes @{ name = 'analytics' } -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod -Times 0 -Exactly
        }

        It 'passes -Attributes through as the body, unmodified' {
            $attrs = @{ name = 'analytics'; description = 'test'; workload_type = 'generic' }
            Set-PfbPresetWorkload -Name 'analytics' -Attributes $attrs -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.Count -eq 3 -and
                $Body['name'] -eq 'analytics' -and
                $Body['description'] -eq 'test' -and
                $Body['workload_type'] -eq 'generic'
            }
        }
    }

    Context 'query parameters' {
        It 'targets by name via the names query parameter' {
            Set-PfbPresetWorkload -Name 'analytics' -Attributes @{ name = 'analytics' } -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['names'] -eq 'analytics' -and -not $QueryParams.ContainsKey('ids')
            }
        }

        It 'targets by id via the ids query parameter' {
            Set-PfbPresetWorkload -Id 'preset-1' -Attributes @{ name = 'analytics' } -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['ids'] -eq 'preset-1' -and -not $QueryParams.ContainsKey('names')
            }
        }

        It 'sends skip_verify_deployable only when the switch is supplied' {
            Set-PfbPresetWorkload -Name 'analytics' -Attributes @{ name = 'analytics' } -SkipVerifyDeployable -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['skip_verify_deployable'] -eq 'true'
            }
        }

        It 'omits skip_verify_deployable when the switch is absent' {
            Set-PfbPresetWorkload -Name 'analytics' -Attributes @{ name = 'analytics' } -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                -not $QueryParams.ContainsKey('skip_verify_deployable')
            }
        }
    }

    Context 'ShouldProcess still gates the call' {
        It 'makes no request under -WhatIf' {
            Set-PfbPresetWorkload -Name 'analytics' -Attributes @{ name = 'analytics' } -WhatIf -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod -Times 0 -Exactly
        }
    }
}
