#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force
}

Describe 'Invoke-PfbApiRequest - HttpTimeoutMs is applied' {
    It 'passes Array.HttpTimeoutMs (converted to whole seconds) as TimeoutSec' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
            [PSCustomObject]@{ items = @() }
        } -ParameterFilter { $Uri -like '*file-systems*' -and $TimeoutSec -eq 45 }

        InModuleScope PureStorageFlashBladePowerShell {
            $array = [PSCustomObject]@{
                Endpoint      = 'fb.test'; ApiVersion = '2.26'; AuthToken = 'tok'
                ApiToken      = $null; AuthMethod = 'ApiToken'
                SkipCertificateCheck = $false; HttpTimeoutMs = 45000
            }
            Invoke-PfbApiRequest -Array $array -Method GET -Endpoint 'file-systems' | Out-Null
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $Uri -like '*file-systems*' -and $TimeoutSec -eq 45
        }
    }

    It 'defaults to 30 seconds when HttpTimeoutMs is absent from the connection object' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
            [PSCustomObject]@{ items = @() }
        } -ParameterFilter { $Uri -like '*file-systems*' -and $TimeoutSec -eq 30 }

        InModuleScope PureStorageFlashBladePowerShell {
            $array = [PSCustomObject]@{
                Endpoint = 'fb.test'; ApiVersion = '2.26'; AuthToken = 'tok'
                ApiToken = $null; AuthMethod = 'ApiToken'; SkipCertificateCheck = $false
            }
            Invoke-PfbApiRequest -Array $array -Method GET -Endpoint 'file-systems' | Out-Null
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $Uri -like '*file-systems*' -and $TimeoutSec -eq 30
        }
    }

    It 'passes TimeoutSec to Connect-PfbArrayInternal on 401 auto-reconnect' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-WebRequest {
            $mockResponse = @{
                Headers = @{ 'x-auth-token' = 'new-token' }
            }
            return $mockResponse
        } -ParameterFilter { $Uri -like '*login*' -and $TimeoutSec -eq 45 }

        InModuleScope PureStorageFlashBladePowerShell {
            # Test Connect-PfbArrayInternal directly
            $result = Connect-PfbArrayInternal -Endpoint 'fb.test' -ApiToken 'test-token' -ApiVersion '2.26' -TimeoutSec 45
            $result.AuthToken | Should -Be 'new-token'
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -like '*login*' -and $TimeoutSec -eq 45
        }
    }
}

Describe 'Invoke-PfbApiRequest - AutoPaginate honors -Limit' {
    It 'stops paginating and trims results once the running total reaches the requested limit' {
        $script:pageCallCount = 0
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
            $script:pageCallCount++
            switch ($script:pageCallCount) {
                1 {
                    [PSCustomObject]@{
                        items              = @(1..6 | ForEach-Object { [PSCustomObject]@{ name = "fs$_" } })
                        continuation_token = 'token-page-2'
                    }
                }
                2 {
                    [PSCustomObject]@{
                        items              = @(7..12 | ForEach-Object { [PSCustomObject]@{ name = "fs$_" } })
                        continuation_token = 'token-page-3'
                    }
                }
                default {
                    throw "Unexpected extra page request (call #$script:pageCallCount) -- the -Limit guard should have stopped pagination after call #2"
                }
            }
        } -ParameterFilter { $Uri -like '*file-systems*' }

        $script:result = InModuleScope PureStorageFlashBladePowerShell {
            $array = [PSCustomObject]@{
                Endpoint = 'fb.test'; ApiVersion = '2.26'; AuthToken = 'tok'
                ApiToken = $null; AuthMethod = 'ApiToken'; SkipCertificateCheck = $false
            }
            Invoke-PfbApiRequest -Array $array -Method GET -Endpoint 'file-systems' -QueryParams @{ limit = 10 } -AutoPaginate
        }

        $script:result.Count | Should -Be 10
        $script:pageCallCount | Should -Be 2
        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod -Times 2 -Exactly -ParameterFilter { $Uri -like '*file-systems*' }
    }

    It 'still auto-paginates the full collection when no -Limit is given' {
        $script:pageCallCount2 = 0
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
            $script:pageCallCount2++
            if ($script:pageCallCount2 -eq 1) {
                [PSCustomObject]@{
                    items              = @(1..6 | ForEach-Object { [PSCustomObject]@{ name = "fs$_" } })
                    continuation_token = 'token-page-2'
                }
            }
            else {
                [PSCustomObject]@{
                    items = @(7..9 | ForEach-Object { [PSCustomObject]@{ name = "fs$_" } })
                }
            }
        } -ParameterFilter { $Uri -like '*file-systems*' }

        $script:result2 = InModuleScope PureStorageFlashBladePowerShell {
            $array = [PSCustomObject]@{
                Endpoint = 'fb.test'; ApiVersion = '2.26'; AuthToken = 'tok'
                ApiToken = $null; AuthMethod = 'ApiToken'; SkipCertificateCheck = $false
            }
            Invoke-PfbApiRequest -Array $array -Method GET -Endpoint 'file-systems' -QueryParams @{} -AutoPaginate
        }

        $script:result2.Count | Should -Be 9
        $script:pageCallCount2 | Should -Be 2
    }
}
