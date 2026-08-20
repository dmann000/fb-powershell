#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.25'; AuthToken = 'x' }
}

Describe 'Remove-PfbUserGroupQuotaPolicy' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    It 'DELETEs user-group-quota-policies by -Name' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ arr = $fakeArray } {
            param($arr)
            Remove-PfbUserGroupQuotaPolicy -Name 'pol-1' -Confirm:$false -Array $arr
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'DELETE' -and $Endpoint -eq 'user-group-quota-policies' -and $QueryParams['names'] -eq 'pol-1'
        }
    }

    It 'targets by -Id when supplied' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ arr = $fakeArray } {
            param($arr)
            Remove-PfbUserGroupQuotaPolicy -Id 'id-1' -Confirm:$false -Array $arr
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['ids'] -eq 'id-1' -and -not $QueryParams.ContainsKey('names')
        }
    }

    It 'sends -Version as the versions query param' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ arr = $fakeArray } {
            param($arr)
            Remove-PfbUserGroupQuotaPolicy -Name 'pol-1' -Version 'v1' -Confirm:$false -Array $arr
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['versions'] -eq 'v1'
        }
    }

    It 'rejects a -Name that looks like a wildcard' {
        { InModuleScope PureStorageFlashBladePowerShell -Parameters @{ arr = $fakeArray } {
            param($arr)
            Remove-PfbUserGroupQuotaPolicy -Name '*' -Confirm:$false -Array $arr
        } } | Should -Throw
    }

    It 'does not call the API under -WhatIf' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ arr = $fakeArray } {
            param($arr)
            Remove-PfbUserGroupQuotaPolicy -Name 'pol-1' -WhatIf -Array $arr
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0
    }
}
