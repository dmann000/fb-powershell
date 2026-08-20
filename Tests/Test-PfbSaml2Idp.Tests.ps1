#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule
    # A throwaway connection object; Assert-PfbConnection is mocked so its contents don't matter.
    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Test-PfbSaml2Idp' {
    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    It 'works with a single explicit -Name (one call)' {
        Test-PfbSaml2Idp -Name 'adfs-prod' -Array $fakeArray
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'GET' -and $Endpoint -eq 'sso/saml2/idps/test' -and $QueryParams['names'] -eq 'adfs-prod'
        }
    }

    It 'joins multiple explicit -Name values into one call' {
        Test-PfbSaml2Idp -Name 'idp1', 'idp2' -Array $fakeArray
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $QueryParams['names'] -eq 'idp1,idp2'
        }
    }

    It 'accumulates ALL piped objects into ONE call (regression: not just the last)' {
        @(
            [pscustomobject]@{ Name = 'idp1' }
            [pscustomobject]@{ Name = 'idp2' }
        ) | Test-PfbSaml2Idp -Array $fakeArray
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $QueryParams['names'] -eq 'idp1,idp2'
        }
    }

    It 'works with explicit -Id' {
        Test-PfbSaml2Idp -Id 'abc12345-6789-0abc-def0-123456789abc' -Array $fakeArray
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $QueryParams['ids'] -eq 'abc12345-6789-0abc-def0-123456789abc'
        }
    }
}
