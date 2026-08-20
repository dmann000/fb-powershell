#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Confirms Invoke-PfbApiRequest's capability-check gate blocks incompatible calls before
    any HTTP request is sent, and lets compatible calls through unchanged.
.DESCRIPTION
    Injects a small synthetic capability map into module state rather than relying on the
    real committed Data/PfbCapabilityMap.json, so this is independent of what the real map
    currently contains.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule

    $script:originalModuleRoot = InModuleScope PureStorageFlashBladePowerShell { $script:PfbModuleRoot }

    function New-TestConnection {
        param([string]$ApiVersion = '2.20')
        [PSCustomObject]@{
            Endpoint             = 'fb.test'
            ApiVersion           = $ApiVersion
            AuthToken            = 'session-token'
            BearerToken          = $null
            ApiToken             = 'T-fake-token'
            AuthMethod           = 'ApiToken'
            SkipCertificateCheck = $false
            ConnectedAt          = [datetime]::UtcNow
        }
    }
}

Describe 'Invoke-PfbApiRequest - capability check gate' {
    BeforeEach {
        InModuleScope PureStorageFlashBladePowerShell {
            $script:PfbCapabilityMap = [PSCustomObject]@{
                endpoints = [PSCustomObject]@{
                    'GET /file-systems' = [PSCustomObject]@{
                        minVersion     = '2.26'
                        parameters     = [PSCustomObject]@{}
                        bodyProperties = [PSCustomObject]@{}
                    }
                }
            }
            $script:PfbVersionMap = $null
        }
    }

    AfterEach {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ root = $script:originalModuleRoot } {
            $script:PfbCapabilityMap = $null
            $script:PfbVersionMap = $null
            $script:PfbModuleRoot = $root
        }
    }

    It 'throws before sending the request when the endpoint requires a newer REST version than the connected array' {
        $array = New-TestConnection -ApiVersion '2.20'
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod { throw 'should never be called' }

        {
            InModuleScope PureStorageFlashBladePowerShell -Parameters @{ array = $array } {
                Invoke-PfbApiRequest -Array $array -Method GET -Endpoint 'file-systems'
            }
        } | Should -Throw -ExpectedMessage '*requires REST 2.26*'

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod -Times 0
    }

    It 'proceeds to send the request when the connected array meets the required version' {
        $array = New-TestConnection -ApiVersion '2.26'
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
            [PSCustomObject]@{ items = @() }
        } -ParameterFilter { $Uri -like '*file-systems*' }

        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ array = $array } {
            Invoke-PfbApiRequest -Array $array -Method GET -Endpoint 'file-systems' | Out-Null
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod -Times 1 -Exactly
    }
}
