#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule
    # A throwaway connection object; Assert-PfbConnection is mocked so its contents don't matter.
    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

# NOTE: New-PfbFileSystemSnapshotPolicy was removed in PR #8 (it POSTed to an endpoint
# that rejects POST -- confirmed HTTP 400/405 live) and replaced by New-PfbPolicyFileSystem,
# which is covered by New-PfbPolicyFileSystem.Tests.ps1. #6's pipeline-binding fix to the
# retained Remove-PfbFileSystemSnapshotPolicy cmdlet is still exercised below.

Describe 'Remove-PfbFileSystemSnapshotPolicy' {
    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    It 'works with explicit -PolicyName / -MemberName (DELETE)' {
        Remove-PfbFileSystemSnapshotPolicy -PolicyName 'daily-snap' -MemberName 'fs01.snap1' -Confirm:$false -Array $fakeArray
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'DELETE' -and $Endpoint -eq 'file-system-snapshots/policies' -and
            $QueryParams['policy_names'] -eq 'daily-snap' -and $QueryParams['member_names'] -eq 'fs01.snap1'
        }
    }

    It 'binds MemberName from a piped snapshot object (.name)' {
        [pscustomobject]@{ name = 'fs01.daily-backup' } |
            Remove-PfbFileSystemSnapshotPolicy -PolicyName 'daily-snap' -Confirm:$false -Array $fakeArray
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $QueryParams['policy_names'] -eq 'daily-snap' -and $QueryParams['member_names'] -eq 'fs01.daily-backup'
        }
    }

    It 'throws when neither policy identity is supplied, before any API call' {
        { Remove-PfbFileSystemSnapshotPolicy -MemberName 'fs01.snap1' -Confirm:$false -Array $fakeArray } | Should -Throw
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 0 -Exactly
    }

    It 'throws when neither member identity is supplied, before any API call' {
        { Remove-PfbFileSystemSnapshotPolicy -PolicyName 'daily-snap' -Confirm:$false -Array $fakeArray } | Should -Throw
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 0 -Exactly
    }

    It 'works with explicit -PolicyId / -MemberId' {
        Remove-PfbFileSystemSnapshotPolicy -PolicyId 'abc-123' -MemberId 'def-456' -Confirm:$false -Array $fakeArray
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $QueryParams['policy_ids'] -eq 'abc-123' -and $QueryParams['member_ids'] -eq 'def-456'
        }
    }

    It 'pipes 2 snapshot objects into 2 separate DELETE calls' {
        @(
            [pscustomobject]@{ name = 'fs01.snap1' }
            [pscustomobject]@{ name = 'fs01.snap2' }
        ) | Remove-PfbFileSystemSnapshotPolicy -PolicyName 'daily-snap' -Confirm:$false -Array $fakeArray
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 2 -Exactly
    }

    It 'makes zero API calls under -WhatIf' {
        Remove-PfbFileSystemSnapshotPolicy -PolicyName 'daily-snap' -MemberName 'fs01.snap1' -WhatIf -Array $fakeArray
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 0 -Exactly
    }
}
