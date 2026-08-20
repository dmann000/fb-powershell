#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'New-PfbPolicyFileSystem' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    It 'POSTs policies/file-systems with policy_names + member_names and no body' {
        New-PfbPolicyFileSystem -PolicyName 'snap-daily' -MemberName 'fs-share' -Confirm:$false -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'POST' -and
            $Endpoint -eq 'policies/file-systems' -and
            $QueryParams['policy_names'] -eq 'snap-daily' -and
            $QueryParams['member_names'] -eq 'fs-share' -and
            $null -eq $Body
        }
    }

    It 'supports the IDs path (policy_ids + member_ids)' {
        New-PfbPolicyFileSystem -PolicyId 'p-123' -MemberId 'm-456' -Confirm:$false -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'POST' -and
            $Endpoint -eq 'policies/file-systems' -and
            $QueryParams['policy_ids'] -eq 'p-123' -and
            $QueryParams['member_ids'] -eq 'm-456'
        }
    }

    It 'honors -WhatIf (no call made)' {
        New-PfbPolicyFileSystem -PolicyName 'snap-daily' -MemberName 'fs-share' -WhatIf -Array $fakeArray
        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
    }

    It 'throws when neither -PolicyName nor -PolicyId is supplied, before any API call' {
        { New-PfbPolicyFileSystem -MemberName 'fs-share' -Confirm:$false -Array $fakeArray } | Should -Throw
        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
    }

    It 'throws when neither -MemberName nor -MemberId is supplied, before any API call' {
        { New-PfbPolicyFileSystem -PolicyName 'snap-daily' -Confirm:$false -Array $fakeArray } | Should -Throw
        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
    }
}
