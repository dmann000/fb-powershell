#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Get-PfbObjectStoreAccountExport - GET wire contract (#101)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    It 'no longer exposes -TotalOnly (the GET does not declare total_only)' {
        (Get-Command Get-PfbObjectStoreAccountExport).Parameters.Keys | Should -Not -Contain 'TotalOnly'
    }

    It 'rejects -TotalOnly at bind time' {
        { Get-PfbObjectStoreAccountExport -TotalOnly -Array $fakeArray -ErrorAction Stop } |
            Should -Throw -ExpectedMessage '*TotalOnly*'
    }

    It 'never emits a total_only query key' {
        Get-PfbObjectStoreAccountExport -Filter "name='x'" -Sort 'name' -Limit 10 -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'GET' -and $Endpoint -eq 'object-store-account-exports' -and
            -not $QueryParams.ContainsKey('total_only')
        }
    }

    It 'emits names for -Name' {
        Get-PfbObjectStoreAccountExport -Name 'export-1' -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['names'] -eq 'export-1' -and -not $QueryParams.ContainsKey('ids')
        }
    }

    It 'emits ids for -Id' {
        Get-PfbObjectStoreAccountExport -Id 'export-id-1' -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['ids'] -eq 'export-id-1' -and -not $QueryParams.ContainsKey('names')
        }
    }
}

Describe 'Remove-PfbObjectStoreAccountExport - DELETE wire contract (#101)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    It 'emits names for -Name' {
        Remove-PfbObjectStoreAccountExport -Name 'export-1' -Confirm:$false -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'DELETE' -and $Endpoint -eq 'object-store-account-exports' -and
            $QueryParams['names'] -eq 'export-1' -and -not $QueryParams.ContainsKey('ids')
        }
    }

    It 'emits ids for -Id' {
        Remove-PfbObjectStoreAccountExport -Id 'export-id-1' -Confirm:$false -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['ids'] -eq 'export-id-1' -and -not $QueryParams.ContainsKey('names')
        }
    }
}
