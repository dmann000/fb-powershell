#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Covers Get-PfbSmtpServer (issue #80). The cmdlet is retained after Get-PfbSmtp's deletion
    and previously had zero test coverage.
#>

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule

    $script:fakeArray = [PSCustomObject]@{
        Endpoint             = 'fb.example.test'
        ApiVersion           = '2.26'
        AuthToken            = 'session-token'
        BearerToken          = $null
        ApiToken             = 'T-fake-token'
        AuthMethod           = 'ApiToken'
        SkipCertificateCheck = $false
    }
}

Describe 'Get-PfbSmtpServer' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    It 'GETs the smtp-servers endpoint' {
        Get-PfbSmtpServer -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'GET' -and $Endpoint -eq 'smtp-servers'
        }
    }

    It 'sends no query parameters when none are supplied' {
        Get-PfbSmtpServer -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams.Count -eq 0
        }
    }

    It 'passes -Filter through Add-PfbCommonQueryParams as filter' {
        Get-PfbSmtpServer -Filter "relay_host='smtp.example.com'" -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['filter'] -eq "relay_host='smtp.example.com'"
        }
    }

    It 'passes -Sort through as sort' {
        Get-PfbSmtpServer -Sort 'name' -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['sort'] -eq 'name'
        }
    }

    It 'passes -Limit through as limit' {
        Get-PfbSmtpServer -Limit 5 -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['limit'] -eq 5
        }
    }

    It 'passes -Filter, -Sort and -Limit together' {
        Get-PfbSmtpServer -Filter "name='management'" -Sort 'name' -Limit 1 -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams.Count -eq 3 -and
            $QueryParams['filter'] -eq "name='management'" -and
            $QueryParams['sort'] -eq 'name' -and
            $QueryParams['limit'] -eq 1
        }
    }

    It 'exposes no -TotalOnly switch (GET /smtp-servers does not declare total_only)' {
        (Get-Command Get-PfbSmtpServer).Parameters.Keys | Should -Not -Contain 'TotalOnly'
    }
}
