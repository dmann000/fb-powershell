#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'New-PfbNetworkInterfaceTlsPolicy - query parameters (#31)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'existing name-based selectors still work (non-issue confirmed, keys already correct)' {
        It 'sends -MemberName as member_names and -PolicyName as policy_names' {
            New-PfbNetworkInterfaceTlsPolicy -MemberName 'data-vip1' -PolicyName 'strict-tls-1.3' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Endpoint -eq 'network-interfaces/tls-policies' -and
                $QueryParams['member_names'] -eq 'data-vip1' -and
                $QueryParams['policy_names'] -eq 'strict-tls-1.3'
            }
        }
    }

    Context '-MemberId / -PolicyId query parameters (missing query params)' {
        It 'sends -MemberId as member_ids' {
            New-PfbNetworkInterfaceTlsPolicy -MemberId 'iface-1' -PolicyName 'strict-tls-1.3' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['member_ids'] -eq 'iface-1' -and -not $QueryParams.ContainsKey('member_names')
            }
        }

        It 'sends -PolicyId as policy_ids' {
            New-PfbNetworkInterfaceTlsPolicy -MemberName 'data-vip1' -PolicyId 'policy-1' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['policy_ids'] -eq 'policy-1' -and -not $QueryParams.ContainsKey('policy_names')
            }
        }

        It 'can select both member and policy purely by id, with no name parameters at all' {
            New-PfbNetworkInterfaceTlsPolicy -MemberId 'iface-1' -PolicyId 'policy-1' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['member_ids'] -eq 'iface-1' -and $QueryParams['policy_ids'] -eq 'policy-1' -and
                -not $QueryParams.ContainsKey('member_names') -and -not $QueryParams.ContainsKey('policy_names')
            }
        }
    }
}
