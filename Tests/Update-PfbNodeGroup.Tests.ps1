#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Update-PfbNodeGroup - typed body parameters (#31)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'typed parameters build the body' {
        It 'sends -NewName as the name body field (exception: name -> -NewName)' {
            Update-PfbNodeGroup -Name 'analytics-group' -NewName 'analytics-primary' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Endpoint -eq 'node-groups' -and
                $QueryParams['names'] -eq 'analytics-group' -and
                $Body['name'] -eq 'analytics-primary'
            }
        }

        It 'sends an EMPTY string for -NewName "" rather than dropping the key' {
            Update-PfbNodeGroup -Name 'analytics-group' -NewName '' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('name') -and $Body['name'] -eq ''
            }
        }

        It 'omits every body key when no typed body parameter is supplied (constraint 19, empty body permitted)' {
            Update-PfbNodeGroup -Name 'analytics-group' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.Count -eq 0
            }
        }

        It 'targets the node group by id when -Id is used' {
            Update-PfbNodeGroup -Id 'group-1' -NewName 'renamed' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['ids'] -eq 'group-1' -and -not $QueryParams.ContainsKey('names')
            }
        }
    }

    Context '-Attributes remains supported and is mutually exclusive' {
        It 'still sends a raw -Attributes body' {
            Update-PfbNodeGroup -Name 'analytics-group' -Attributes @{ name = 'raw-rename' } -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['name'] -eq 'raw-rename'
            }
        }

        It 'rejects -Attributes combined with -NewName at bind time' {
            { Update-PfbNodeGroup -Name 'analytics-group' -NewName 'x' -Attributes @{ name = 'y' } `
                -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'
        }
    }

    Context 'constraint compliance' {
        It 'puts no ValidateSet on -NewName (constraint 3, no spec enum)' {
            $attrs = (Get-Command Update-PfbNodeGroup).Parameters['NewName'].Attributes
            @($attrs | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).Count |
                Should -Be 0
        }

        It 'exposes the settable body field the endpoint accepts' {
            (Get-Command Update-PfbNodeGroup).Parameters.Keys | Should -Contain 'NewName'
        }
    }
}
