#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule

    # A throwaway connection object; Assert-PfbConnection is mocked so its contents don't matter.
    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Update-PfbFileSystem - file-system demote support' {

    BeforeEach {
        # Isolate the REST layer: never make a real call, just capture what would be sent.
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context '-DiscardNonSnapshottedData switch' {
        It 'adds discard_non_snapshotted_data=true to the query params when present' {
            Update-PfbFileSystem -Name 'fs1' `
                -Attributes @{ requested_promotion_state = 'demoted' } `
                -DiscardNonSnapshottedData -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and
                $Endpoint -eq 'file-systems' -and
                $QueryParams['names'] -eq 'fs1' -and
                $QueryParams['discard_non_snapshotted_data'] -eq 'true'
            }
        }

        It 'does NOT add the key when the switch is absent (no regression)' {
            Update-PfbFileSystem -Name 'fs1' -Provisioned 2147483648 -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['names'] -eq 'fs1' -and
                -not $QueryParams.ContainsKey('discard_non_snapshotted_data')
            }
        }
    }

    Context '-RequestedPromotionState typed parameter' {
        It 'sets requested_promotion_state in the body' {
            Update-PfbFileSystem -Name 'fs1' -RequestedPromotionState 'demoted' `
                -DiscardNonSnapshottedData -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['requested_promotion_state'] -eq 'demoted' -and
                $QueryParams['discard_non_snapshotted_data'] -eq 'true'
            }
        }

        It 'rejects values outside the promoted/demoted set at parameter binding' {
            { Update-PfbFileSystem -Name 'fs1' -RequestedPromotionState 'bogus' -Array $fakeArray } |
                Should -Throw
        }

        It 'throws when both -Attributes and -RequestedPromotionState are supplied' {
            { Update-PfbFileSystem -Name 'fs1' `
                -Attributes @{ requested_promotion_state = 'demoted' } `
                -RequestedPromotionState 'demoted' -Confirm:$false -Array $fakeArray } |
                Should -Throw '*mutually exclusive*'
        }
    }

    Context 'end-to-end demote shape (mocked)' {
        It 'produces body { requested_promotion_state = demoted } and query { names; discard_non_snapshotted_data = true }' {
            Update-PfbFileSystem -Name 'fs1' `
                -Attributes @{ requested_promotion_state = 'demoted' } `
                -DiscardNonSnapshottedData -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and
                $Endpoint -eq 'file-systems' -and
                $Body['requested_promotion_state'] -eq 'demoted' -and
                $Body.Keys.Count -eq 1 -and
                $QueryParams['names'] -eq 'fs1' -and
                $QueryParams['discard_non_snapshotted_data'] -eq 'true'
            }
        }
    }
}
