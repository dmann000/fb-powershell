#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule
    # A throwaway connection object; Assert-PfbConnection is mocked so its contents don't matter.
    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Test-PfbActiveDirectory' {
    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    It 'works with a single explicit -Name (one call)' {
        Test-PfbActiveDirectory -Name 'ad1' -Array $fakeArray
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'GET' -and $Endpoint -eq 'active-directory/test' -and $QueryParams['names'] -eq 'ad1'
        }
    }

    It 'joins multiple explicit -Name values into one call' {
        Test-PfbActiveDirectory -Name 'ad1', 'ad2' -Array $fakeArray
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $QueryParams['names'] -eq 'ad1,ad2'
        }
    }

    It 'accumulates ALL piped objects into ONE call (regression: not just the last)' {
        @(
            [pscustomobject]@{ Name = 'ad1' }
            [pscustomobject]@{ Name = 'ad2' }
        ) | Test-PfbActiveDirectory -Array $fakeArray
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $QueryParams['names'] -eq 'ad1,ad2'
        }
    }

    It 'works with explicit -Id' {
        Test-PfbActiveDirectory -Id 'abc12345-6789-0abc-def0-123456789abc' -Array $fakeArray
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $QueryParams['ids'] -eq 'abc12345-6789-0abc-def0-123456789abc'
        }
    }
}
