#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
    $script:expectedResponse = [PSCustomObject]@{
        items = @(
            [PSCustomObject]@{ component_name = 'syslog-prod'; success = $true; result_details = 'ok' }
            [PSCustomObject]@{ component_name = 'syslog-dr'; success = $false; result_details = 'unreachable' }
        )
        total_item_count = 2
    }
}

Describe 'Test-PfbSyslogServer' {
    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { $script:expectedResponse.items }
    }

    It 'sends no names or ids query keys' {
        Test-PfbSyslogServer -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            -not $QueryParams.ContainsKey('names') -and -not $QueryParams.ContainsKey('ids')
        }
    }

    It 'does not expose Name or Id parameters' {
        $parameters = (Get-Command Test-PfbSyslogServer).Parameters

        $parameters.Keys | Should -Not -Contain 'Name'
        $parameters.Keys | Should -Not -Contain 'Id'
    }

    It 'uses the syslog test endpoint with GET' {
        Test-PfbSyslogServer -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'GET' -and $Endpoint -eq 'syslog-servers/test'
        }
    }

    It 'passes the response items through to the caller' {
        $result = @(Test-PfbSyslogServer -Array $fakeArray)

        $result.Count | Should -Be 2
        $result[0].component_name | Should -Be 'syslog-prod'
        $result[0].success | Should -BeTrue
        $result[1].component_name | Should -Be 'syslog-dr'
        $result[1].success | Should -BeFalse
    }
}
