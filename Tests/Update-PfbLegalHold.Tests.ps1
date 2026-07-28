#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Update-PfbLegalHold - typed body parameters (#31)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'typed parameters build the body' {
        It 'sends -Description as the description body field' {
            Update-PfbLegalHold -Name 'litigation-hold-2024' -Description 'Updated description' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Endpoint -eq 'legal-holds' -and
                $QueryParams['names'] -eq 'litigation-hold-2024' -and
                $Body['description'] -eq 'Updated description'
            }
        }

        It 'sends an EMPTY string for -Description "" rather than dropping the key' {
            Update-PfbLegalHold -Name 'litigation-hold-2024' -Description '' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('description') -and $Body['description'] -eq ''
            }
        }

        It 'omits description entirely when not supplied' {
            Update-PfbLegalHold -Name 'litigation-hold-2024' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                -not $Body.ContainsKey('description')
            }
        }

        It 'targets the legal hold by id when -Id is used' {
            Update-PfbLegalHold -Id 'hold-1' -Description 'x' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['ids'] -eq 'hold-1' -and -not $QueryParams.ContainsKey('names')
            }
        }
    }

    Context '-Attributes remains supported and is mutually exclusive' {
        It 'still sends a raw -Attributes body' {
            Update-PfbLegalHold -Name 'litigation-hold-2024' -Attributes @{ description = 'raw' } `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['description'] -eq 'raw'
            }
        }

        It 'rejects -Attributes combined with a typed parameter at bind time' {
            { Update-PfbLegalHold -Name 'litigation-hold-2024' -Description 'x' -Attributes @{ description = 'y' } `
                -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'
        }
    }

    Context 'an empty write is permitted (constraint 19)' {
        It 'resolves cleanly and sends an empty body when no parameter is supplied' {
            Update-PfbLegalHold -Name 'litigation-hold-2024' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.Count -eq 0
            }
        }
    }
}
