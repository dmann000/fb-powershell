#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.25'; AuthToken = 'x' }
}

Describe 'Get-PfbUserGroupQuotaPolicy' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    It 'GETs user-group-quota-policies with AutoPaginate and no filters by default' {
        Get-PfbUserGroupQuotaPolicy -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'GET' -and
            $Endpoint -eq 'user-group-quota-policies' -and
            $AutoPaginate -eq $true -and
            $QueryParams.Keys.Count -eq 0
        }
    }

    It 'joins -Name into a comma-separated names query param' {
        Get-PfbUserGroupQuotaPolicy -Name 'pol-1', 'pol-2' -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['names'] -eq 'pol-1,pol-2'
        }
    }

    It 'sends -Id as the ids query param' {
        Get-PfbUserGroupQuotaPolicy -Id 'id-1' -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['ids'] -eq 'id-1' -and -not $QueryParams.ContainsKey('names')
        }
    }

    It 'passes -Filter, -Sort, and -Limit through' {
        Get-PfbUserGroupQuotaPolicy -Filter "enabled='true'" -Sort 'name-' -Limit 5 -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['filter'] -eq "enabled='true'" -and
            $QueryParams['sort'] -eq 'name-' -and
            $QueryParams['limit'] -eq 5
        }
    }
}
