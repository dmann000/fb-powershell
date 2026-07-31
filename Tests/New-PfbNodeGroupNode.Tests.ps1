#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'New-PfbNodeGroupNode - query parameters (#31)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'wire-key correctness fix: POST /node-groups/nodes documents node_group_*/node_*, not group_*/member_*' {
        It 'sends -GroupName as node_group_names, NOT group_names' {
            New-PfbNodeGroupNode -GroupName 'analytics-group' -MemberName 'CH1.FB1' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Endpoint -eq 'node-groups/nodes' -and
                $QueryParams['node_group_names'] -eq 'analytics-group' -and
                -not $QueryParams.ContainsKey('group_names')
            }
        }

        It 'sends -MemberName as node_names, NOT member_names' {
            New-PfbNodeGroupNode -GroupName 'analytics-group' -MemberName 'CH1.FB1' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['node_names'] -eq 'CH1.FB1' -and
                -not $QueryParams.ContainsKey('member_names')
            }
        }
    }

    Context '-GroupId / -MemberId query parameters (missing query params: node_group_ids, node_ids)' {
        It 'sends -GroupId as node_group_ids' {
            New-PfbNodeGroupNode -GroupId 'group-1' -MemberName 'CH1.FB1' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['node_group_ids'] -eq 'group-1' -and -not $QueryParams.ContainsKey('node_group_names')
            }
        }

        It 'sends -MemberId as node_ids' {
            New-PfbNodeGroupNode -GroupName 'analytics-group' -MemberId 'node-1' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['node_ids'] -eq 'node-1' -and -not $QueryParams.ContainsKey('node_names')
            }
        }

        It 'can select both group and node purely by id' {
            New-PfbNodeGroupNode -GroupId 'group-1' -MemberId 'node-1' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['node_group_ids'] -eq 'group-1' -and $QueryParams['node_ids'] -eq 'node-1'
            }
        }
    }
}
