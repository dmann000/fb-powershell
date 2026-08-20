#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'New-PfbQosPolicyMember - typed query params (#31)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'existing member_names/member_ids wire keys are unchanged (confirmed non-issue)' {
        It 'still sends -MemberName as member_names' {
            New-PfbQosPolicyMember -PolicyName 'qos-gold' -MemberName 'fs1' -Confirm:$false -Array $fakeArray
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter { $QueryParams['member_names'] -eq 'fs1' }
        }

        It 'still sends -MemberId as member_ids' {
            New-PfbQosPolicyMember -PolicyName 'qos-gold' -MemberId 'm-1' -Confirm:$false -Array $fakeArray
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter { $QueryParams['member_ids'] -eq 'm-1' }
        }
    }

    Context 'new -MemberType query parameter' {
        It 'sends -MemberType as a joined member_types query param' {
            New-PfbQosPolicyMember -PolicyName 'qos-gold' -MemberName 'fs1' -MemberType @('file-systems', 'realms') -Confirm:$false -Array $fakeArray
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter { $QueryParams['member_types'] -eq 'file-systems,realms' }
        }

        It 'sends an explicit empty -MemberType @() (constraint 2, array field)' {
            New-PfbQosPolicyMember -PolicyName 'qos-gold' -MemberName 'fs1' -MemberType @() -Confirm:$false -Array $fakeArray
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter { $QueryParams.ContainsKey('member_types') -and $QueryParams['member_types'] -eq '' }
        }

        It 'omits member_types entirely when not supplied' {
            New-PfbQosPolicyMember -PolicyName 'qos-gold' -MemberName 'fs1' -Confirm:$false -Array $fakeArray
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter { -not $QueryParams.ContainsKey('member_types') }
        }
    }
}
