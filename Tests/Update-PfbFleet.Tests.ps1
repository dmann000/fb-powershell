#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Update-PfbFleet - typed body parameters (#31)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'typed parameters build the body' {
        It 'sends -NewName as the name body field (rename exception, constraint: name -> -NewName)' {
            Update-PfbFleet -Name 'fleet-prod' -NewName 'fleet-renamed' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Endpoint -eq 'fleets' -and
                $QueryParams['names'] -eq 'fleet-prod' -and
                $Body['name'] -eq 'fleet-renamed'
            }
        }

        It 'sends an EMPTY string for -NewName "" rather than dropping the key' {
            Update-PfbFleet -Name 'fleet-prod' -NewName '' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('name') -and $Body['name'] -eq ''
            }
        }

        It 'has no -Name-shaped body parameter, only -NewName' {
            (Get-Command Update-PfbFleet).Parameters.Keys | Should -Not -Contain 'FleetName'
        }

        It 'targets the fleet by id when -Id is used' {
            Update-PfbFleet -Id 'fleet-1' -NewName 'renamed' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['ids'] -eq 'fleet-1' -and -not $QueryParams.ContainsKey('names')
            }
        }

        It 'omits every body key when no typed body parameter is supplied' {
            Update-PfbFleet -Name 'fleet-prod' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.Count -eq 0
            }
        }
    }

    Context '-Attributes remains supported and is mutually exclusive' {
        It 'still sends a raw -Attributes body' {
            Update-PfbFleet -Name 'fleet-prod' -Attributes @{ name = 'raw-renamed' } -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['name'] -eq 'raw-renamed'
            }
        }

        It 'rejects -Attributes combined with -NewName at bind time' {
            { Update-PfbFleet -Name 'fleet-prod' -NewName 'x' -Attributes @{ name = 'y' } `
                -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'
        }
    }

    Context 'constraint compliance' {
        It 'puts no ValidateSet on -NewName (constraint 3, no spec enum)' {
            $attrs = (Get-Command Update-PfbFleet).Parameters['NewName'].Attributes
            @($attrs | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).Count |
                Should -Be 0
        }
    }
}
