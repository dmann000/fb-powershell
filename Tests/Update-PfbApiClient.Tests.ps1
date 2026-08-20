#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Update-PfbApiClient - typed body parameters (#31)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'typed parameters build the body' {
        It 'sends an explicit -Enabled:$true' {
            Update-PfbApiClient -Name 'automation' -Enabled $true -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Endpoint -eq 'api-clients' -and
                $QueryParams['names'] -eq 'automation' -and
                $Body['enabled'] -eq $true
            }
        }

        It 'sends an explicit -Enabled:$false (ContainsKey semantics, not truthiness)' {
            Update-PfbApiClient -Name 'automation' -Enabled $false -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('enabled') -and $Body['enabled'] -eq $false
            }
        }

        It 'omits enabled entirely when -Enabled is not supplied' {
            Update-PfbApiClient -Id 'client-1' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['ids'] -eq 'client-1' -and -not $Body.ContainsKey('enabled')
            }
        }
    }

    Context '-Attributes remains supported and is mutually exclusive' {
        It 'still sends a raw -Attributes body' {
            Update-PfbApiClient -Name 'automation' -Attributes @{ enabled = $true } `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['enabled'] -eq $true
            }
        }

        It 'rejects -Attributes combined with a typed parameter at bind time' {
            { Update-PfbApiClient -Name 'automation' -Enabled $true -Attributes @{ enabled = $false } `
                -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'
        }
    }

    Context 'excluded fields are not exposed' {
        It 'has no -MaxRole parameter (deprecated, constraint 9)' {
            (Get-Command Update-PfbApiClient).Parameters.Keys | Should -Not -Contain 'MaxRole'
        }

        It 'exposes no read-only field as a parameter (constraint 11)' {
            $paramNames = (Get-Command Update-PfbApiClient).Parameters.Keys
            foreach ($readOnly in 'AccessPolicies', 'AccessTokenTtlInMs', 'Issuer', 'KeyId', 'PublicKey') {
                $paramNames | Should -Not -Contain $readOnly
            }
        }
    }
}
