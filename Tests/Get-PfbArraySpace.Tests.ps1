#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule
    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Get-PfbArraySpace' {
    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    It 'restricts -Type to the three real spec-documented values' {
        $attr = (Get-Command Get-PfbArraySpace).Parameters['Type'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
        $attr | Should -Not -BeNullOrEmpty
        $attr.ValidValues | Should -Be @('array', 'file-system', 'object-store')
    }

    It 'rejects an invalid -Type value before making any API call' {
        { Get-PfbArraySpace -Type 'bogus' -Array $fakeArray } | Should -Throw
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 0 -Exactly
    }

    It 'passes a valid -Type through to the query string' {
        Get-PfbArraySpace -Type 'file-system' -Array $fakeArray
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'GET' -and $Endpoint -eq 'arrays/space' -and $QueryParams['type'] -eq 'file-system'
        }
    }

    It 'omits -Type from the query string when not specified (server defaults to array)' {
        Get-PfbArraySpace -Array $fakeArray
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            -not $QueryParams.ContainsKey('type')
        }
    }
}
