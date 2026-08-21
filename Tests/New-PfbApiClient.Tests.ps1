#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'New-PfbApiClient - typed body parameters (#106)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'typed parameters build the body' {
        It 'sends -PublicKey in the body and -Name as names' {
            New-PfbApiClient -Name 'automation-client' -PublicKey 'public-key' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Endpoint -eq 'api-clients' -and
                $QueryParams['names'] -eq 'automation-client' -and
                $Body['public_key'] -eq 'public-key'
            }
        }

        It 'sends -MaxRole as a nested reference without resource_type' {
            New-PfbApiClient -Name 'automation-client' -PublicKey 'public-key' -MaxRole 'storage_admin' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['max_role'] -is [hashtable] -and
                $Body['max_role']['name'] -eq 'storage_admin' -and
                -not $Body['max_role'].ContainsKey('resource_type')
            }
        }

        It 'omits max_role when -MaxRole is not supplied' {
            New-PfbApiClient -Name 'automation-client' -PublicKey 'public-key' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('public_key') -and -not $Body.ContainsKey('max_role')
            }
        }
    }

    Context '-Attributes remains supported as a raw body' {
        It 'sends the raw hashtable body' {
            $attributes = @{ public_key = 'raw-key'; max_role = @{ name = 'storage_admin' } }

            New-PfbApiClient -Name 'automation-client' -Attributes $attributes -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['public_key'] -eq 'raw-key' -and
                $Body['max_role']['name'] -eq 'storage_admin'
            }
        }

        It 'does not mutate the caller hashtable' {
            $attributes = @{ public_key = 'raw-key'; custom = 'value' }
            $originalCount = $attributes.Count

            New-PfbApiClient -Name 'automation-client' -Attributes $attributes -Confirm:$false -Array $fakeArray

            $attributes.Count | Should -Be $originalCount
        }

        It 'rejects -Attributes combined with typed parameters at bind time' {
            { New-PfbApiClient -Name 'x' -PublicKey 'k' -Attributes @{} -Confirm:$false -Array $fakeArray } |
                Should -Throw
        }
    }

    Context 'typed parameter metadata' {
        It 'makes -PublicKey mandatory in the default Typed parameter set' {
            $publicKeyParameter = (Get-Command New-PfbApiClient).Parameters['PublicKey']
            $typedParameterAttribute = $publicKeyParameter.Attributes |
                Where-Object {
                    $_ -is [System.Management.Automation.ParameterAttribute] -and
                    $_.ParameterSetName -eq 'Typed'
                }

            $typedParameterAttribute.Mandatory | Should -BeTrue
        }
    }
}
