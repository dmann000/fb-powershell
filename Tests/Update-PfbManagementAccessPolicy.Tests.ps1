#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Update-PfbManagementAccessPolicy - typed body parameters (#31)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'typed parameters build the body' {
        It 'sends aggregation_strategy and the renamed name field' {
            Update-PfbManagementAccessPolicy -Name 'ops-policy' `
                -AggregationStrategy 'least-common-permissions' -PolicyName 'ops-policy-v2' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Endpoint -eq 'management-access-policies' -and
                $QueryParams['names'] -eq 'ops-policy' -and
                $Body['aggregation_strategy'] -eq 'least-common-permissions' -and
                $Body['name'] -eq 'ops-policy-v2'
            }
        }

        It 'sends an explicit -Enabled:$false (ContainsKey semantics, not truthiness)' {
            Update-PfbManagementAccessPolicy -Name 'ops-policy' -Enabled $false `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('enabled') -and $Body['enabled'] -eq $false
            }
        }

        It 'omits enabled entirely when -Enabled is not supplied' {
            Update-PfbManagementAccessPolicy -Name 'ops-policy' -PolicyName 'x' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                -not $Body.ContainsKey('enabled')
            }
        }

        It 'builds location as a single name-reference object (constraint 8a)' {
            Update-PfbManagementAccessPolicy -Name 'ops-policy' -Location 'array-1' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['location'].name -eq 'array-1'
            }
        }

        It 'passes rules through unchanged as composite objects (constraint 8c)' {
            $rules = @(
                @{ role = @{ name = 'viewer' }; scope = @{ name = 'array-1'; resource_type = 'arrays' } },
                @{ role = @{ name = 'admin' };  scope = @{ name = 'realm-1'; resource_type = 'realms' } }
            )

            Update-PfbManagementAccessPolicy -Name 'ops-policy' -Rules $rules `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['rules'].Count -eq 2 -and
                $Body['rules'][0].role.name -eq 'viewer' -and
                $Body['rules'][1].scope.resource_type -eq 'realms' -and
                -not $Body['rules'][0].ContainsKey('name')
            }
        }
    }

    Context '-Attributes remains supported and is mutually exclusive' {
        It 'still sends a raw -Attributes body' {
            Update-PfbManagementAccessPolicy -Name 'ops-policy' -Attributes @{ enabled = $true } `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['enabled'] -eq $true
            }
        }

        It 'rejects -Attributes combined with a typed parameter at bind time' {
            { Update-PfbManagementAccessPolicy -Name 'ops-policy' -Enabled $true -Attributes @{ enabled = $false } `
                -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'
        }
    }

    Context 'constraint compliance' {
        It 'puts no ValidateSet on -AggregationStrategy (constraint 3, no spec enum)' {
            $attrs = (Get-Command Update-PfbManagementAccessPolicy).Parameters['AggregationStrategy'].Attributes
            @($attrs | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).Count |
                Should -Be 0
        }

        It 'exposes no read-only field as a parameter (constraint 11)' {
            $paramNames = (Get-Command Update-PfbManagementAccessPolicy).Parameters.Keys
            foreach ($readOnly in 'Context', 'IsLocal', 'PolicyType', 'Realms', 'Version') {
                $paramNames | Should -Not -Contain $readOnly
            }
        }
    }
}
