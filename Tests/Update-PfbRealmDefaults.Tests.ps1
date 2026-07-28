#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Update-PfbRealmDefaults - typed body parameters + query wire-key fix (#31)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'query wire-key bug fix: PATCH /realms/defaults only accepts realm_ids/realm_names' {
        It 'sends -Name as realm_names, NOT names' {
            Update-PfbRealmDefaults -Name 'realm-prod' -Attributes @{} -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Endpoint -eq 'realms/defaults' -and
                $QueryParams['realm_names'] -eq 'realm-prod' -and
                -not $QueryParams.ContainsKey('names')
            }
        }

        It 'sends -Id as realm_ids, NOT ids' {
            Update-PfbRealmDefaults -Id 'realm-1' -Attributes @{} -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['realm_ids'] -eq 'realm-1' -and -not $QueryParams.ContainsKey('ids')
            }
        }
    }

    Context 'typed parameters build the body' {
        It 'sends object_store as a composite array, passed straight through' {
            Update-PfbRealmDefaults -Name 'realm-prod' -ObjectStore @{ server = @{ name = 'obj-server-1' } } `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                @($Body['object_store']).Count -eq 1 -and
                $Body['object_store'][0].server.name -eq 'obj-server-1'
            }
        }

        It 'sends an EMPTY array for -ObjectStore @() so the list can be cleared' {
            Update-PfbRealmDefaults -Name 'realm-prod' -ObjectStore @() -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('object_store') -and @($Body['object_store']).Count -eq 0
            }
        }

        It 'omits every body key when no typed body parameter is supplied' {
            Update-PfbRealmDefaults -Name 'realm-prod' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.Count -eq 0
            }
        }
    }

    Context '-Attributes remains supported and is mutually exclusive' {
        It 'still sends a raw -Attributes body' {
            Update-PfbRealmDefaults -Name 'realm-prod' -Attributes @{ object_store = @(@{ server = @{ name = 'raw' } }) } `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['object_store'][0].server.name -eq 'raw'
            }
        }

        It 'rejects -Attributes combined with a typed parameter at bind time' {
            { Update-PfbRealmDefaults -Name 'realm-prod' -ObjectStore @() -Attributes @{} `
                -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'
        }
    }

    Context 'read-only fields are not exposed (constraint 11)' {
        It 'has no -Context or -Realm parameter' {
            $keys = (Get-Command Update-PfbRealmDefaults).Parameters.Keys
            $keys | Should -Not -Contain 'Context'
            $keys | Should -Not -Contain 'Realm'
        }
    }

    Context 'constraint compliance' {
        It 'puts no ValidateSet on -ObjectStore (constraint 3, no spec enum)' {
            $attrs = (Get-Command Update-PfbRealmDefaults).Parameters['ObjectStore'].Attributes
            @($attrs | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).Count |
                Should -Be 0
        }

        It 'exposes -ObjectStore as [hashtable[]] (constraint 8c, composite)' {
            (Get-Command Update-PfbRealmDefaults).Parameters['ObjectStore'].ParameterType.Name | Should -Be 'Hashtable[]'
        }
    }
}
