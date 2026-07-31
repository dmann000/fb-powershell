#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Update-PfbOidcIdp - typed body parameters (#31)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'typed parameters build the body' {
        It 'sends the renamed name field and services array' {
            Update-PfbOidcIdp -Name 'okta-prod' -NewName 'okta-prod-v2' -Services 'object' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Endpoint -eq 'sso/oidc/idps' -and
                $QueryParams['names'] -eq 'okta-prod' -and
                $Body['name'] -eq 'okta-prod-v2' -and
                $Body['services'].Count -eq 1 -and $Body['services'][0] -eq 'object'
            }
        }

        It 'sends an explicit -Enabled:$false (ContainsKey semantics, not truthiness)' {
            Update-PfbOidcIdp -Name 'okta-prod' -Enabled $false -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('enabled') -and $Body['enabled'] -eq $false
            }
        }

        It 'omits enabled entirely when -Enabled is not supplied' {
            Update-PfbOidcIdp -Name 'okta-prod' -NewName 'x' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                -not $Body.ContainsKey('enabled')
            }
        }

        It 'sends an EMPTY array for -Services @() so the list can be cleared' {
            Update-PfbOidcIdp -Name 'okta-prod' -Services @() -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('services') -and @($Body['services']).Count -eq 0
            }
        }

        It 'sends an EMPTY string for -NewName "" rather than dropping the key' {
            Update-PfbOidcIdp -Name 'okta-prod' -NewName '' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('name') -and $Body['name'] -eq ''
            }
        }

        It 'passes idp through as a composite sub-object, NOT a name reference (constraint 8c)' {
            Update-PfbOidcIdp -Name 'okta-prod' `
                -Idp @{ provider_url = 'https://idp.example.com' } `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['idp'].provider_url -eq 'https://idp.example.com' -and
                -not $Body['idp'].ContainsKey('name')
            }
        }
    }

    Context '-Attributes remains supported and is mutually exclusive' {
        It 'still sends a raw -Attributes body' {
            Update-PfbOidcIdp -Name 'okta-prod' -Attributes @{ enabled = $false } `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['enabled'] -eq $false
            }
        }

        It 'rejects -Attributes combined with a typed parameter at bind time' {
            { Update-PfbOidcIdp -Name 'okta-prod' -Enabled $true -Attributes @{ enabled = $false } `
                -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'
        }
    }

    Context 'constraint compliance' {
        It 'puts no ValidateSet on -Services (constraint 3, no spec enum)' {
            $attrs = (Get-Command Update-PfbOidcIdp).Parameters['Services'].Attributes
            @($attrs | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).Count |
                Should -Be 0
        }

        It 'does not expose the read-only prn field (constraint 11)' {
            (Get-Command Update-PfbOidcIdp).Parameters.Keys | Should -Not -Contain 'Prn'
        }
    }
}
