#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Update-PfbSaml2Idp - typed body parameters (#31)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'typed parameters build the body' {
        It 'sends array_url, binding, the renamed name field and services' {
            Update-PfbSaml2Idp -Name 'adfs-prod' `
                -ArrayUrl 'https://fb.example.test' -Binding 'http-redirect' `
                -NewName 'adfs-prod-v2' -Services 'management','object' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Endpoint -eq 'sso/saml2/idps' -and
                $QueryParams['names'] -eq 'adfs-prod' -and
                $Body['array_url'] -eq 'https://fb.example.test' -and
                $Body['binding'] -eq 'http-redirect' -and
                $Body['name'] -eq 'adfs-prod-v2' -and
                $Body['services'].Count -eq 2
            }
        }

        It 'sends an explicit -Enabled:$false (ContainsKey semantics, not truthiness)' {
            Update-PfbSaml2Idp -Name 'adfs-prod' -Enabled $false -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('enabled') -and $Body['enabled'] -eq $false
            }
        }

        It 'omits enabled entirely when -Enabled is not supplied' {
            Update-PfbSaml2Idp -Name 'adfs-prod' -ArrayUrl 'https://x' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                -not $Body.ContainsKey('enabled')
            }
        }

        It 'sends an EMPTY array for -Services @() so the list can be cleared' {
            Update-PfbSaml2Idp -Name 'adfs-prod' -Services @() -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('services') -and @($Body['services']).Count -eq 0
            }
        }

        It 'sends an EMPTY string for -ArrayUrl "" rather than dropping the key' {
            Update-PfbSaml2Idp -Name 'adfs-prod' -ArrayUrl '' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('array_url') -and $Body['array_url'] -eq ''
            }
        }

        It 'passes idp, sp and management through as composite sub-objects (constraint 8c)' {
            Update-PfbSaml2Idp -Name 'adfs-prod' `
                -Idp @{ entity_id = 'urn:idp'; metadata_url = 'https://idp/meta' } `
                -Sp  @{ entity_id = 'urn:sp' } `
                -Management @{ trust_other_saml_sps_in_fleet = $true } `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['idp'].entity_id -eq 'urn:idp' -and
                $Body['idp'].metadata_url -eq 'https://idp/meta' -and
                -not $Body['idp'].ContainsKey('name') -and
                $Body['sp'].entity_id -eq 'urn:sp' -and
                $Body['management'].trust_other_saml_sps_in_fleet -eq $true
            }
        }

        It 'targets the IdP by id when -Id is used' {
            Update-PfbSaml2Idp -Id 'idp-1' -Enabled $true -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['ids'] -eq 'idp-1' -and -not $QueryParams.ContainsKey('names')
            }
        }
    }

    Context '-Attributes remains supported and is mutually exclusive' {
        It 'still sends a raw -Attributes body' {
            Update-PfbSaml2Idp -Name 'adfs-prod' -Attributes @{ enabled = $false } `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['enabled'] -eq $false
            }
        }

        It 'rejects -Attributes combined with a typed parameter at bind time' {
            { Update-PfbSaml2Idp -Name 'adfs-prod' -Enabled $true -Attributes @{ enabled = $false } `
                -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'
        }
    }

    Context 'constraint compliance' {
        It 'puts no ValidateSet on -Binding or -Services (constraint 3, no spec enum)' {
            foreach ($p in 'Binding', 'Services') {
                $attrs = (Get-Command Update-PfbSaml2Idp).Parameters[$p].Attributes
                @($attrs | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).Count |
                    Should -Be 0
            }
        }

        It 'exposes no read-only field as a parameter (constraint 11)' {
            (Get-Command Update-PfbSaml2Idp).Parameters.Keys | Should -Not -Contain 'Prn'
        }
    }
}
