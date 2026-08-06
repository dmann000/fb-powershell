#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force
}

Describe 'Invoke-PfbApiTokenLogin' {
    It 'POSTs the api-token header to /api/login and returns x-auth-token' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-WebRequest {
            [PSCustomObject]@{ Headers = @{ 'x-auth-token' = 'session-token-123' } }
        } -ParameterFilter { $Uri -eq 'https://fb.test/api/login' -and $Headers['api-token'] -eq 'T-fake' }

        $result = InModuleScope PureStorageFlashBladePowerShell {
            Invoke-PfbApiTokenLogin -Endpoint 'fb.test' -ApiToken 'T-fake'
        }

        # Returns an OBJECT, not a bare string: the login body carries the array's own spelling of
        # the admin name and the whole point of Task 12b is not to discard it.
        $result.AuthToken | Should -Be 'session-token-123'
    }

    It 'throws a clear error when the login call fails' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-WebRequest {
            throw 'connection refused'
        } -ParameterFilter { $Uri -eq 'https://fb.test/api/login' }

        { InModuleScope PureStorageFlashBladePowerShell {
            Invoke-PfbApiTokenLogin -Endpoint 'fb.test' -ApiToken 'T-fake'
        } } |
            Should -Throw -ExpectedMessage "*Authentication failed for FlashBlade 'fb.test'*"
    }
}

Describe 'Invoke-PfbApiTokenLogin - login response username' {
    # Mocked at the Invoke-WebRequest boundary. The plan's global constraint names
    # Invoke-RestMethod; the equivalent boundary HERE is Invoke-WebRequest, because that is what
    # the login functions call -- the header is only reachable through a full response object. A
    # mock of Invoke-PfbApiTokenLogin ITSELF cannot prove this contract: that exact mistake left
    # the admin-locality feature inert in production behind a fully green suite.
    It 'returns the username the array reported in the /api/login body' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-WebRequest {
            [PSCustomObject]@{
                StatusCode = 200
                Headers    = @{ 'x-auth-token' = 'sess-tok' }
                Content    = '{"username":"pureuser"}'
            }
        } -ParameterFilter { $Uri -eq 'https://fb.test/api/login' }

        $result = InModuleScope PureStorageFlashBladePowerShell {
            Invoke-PfbApiTokenLogin -Endpoint 'fb.test' -ApiToken 'T-1234'
        }

        $result.AuthToken | Should -Be 'sess-tok'
        $result.Username  | Should -Be 'pureuser'
    }

    It 'still returns the token, with a $null Username, when the body carries no username' {
        # DEFENSIVE ONLY -- malformed-body tolerance. NOT a version concern: /api/login returns
        # username in every REST version 2.0 through 2.28, so there is no version in which this
        # branch is the expected path. A login that authenticated must never fail because a proxy
        # rewrote the body.
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-WebRequest {
            [PSCustomObject]@{ Headers = @{ 'x-auth-token' = 'sess-tok' }; Content = '{}' }
        } -ParameterFilter { $Uri -eq 'https://fb.test/api/login' }

        $result = InModuleScope PureStorageFlashBladePowerShell {
            Invoke-PfbApiTokenLogin -Endpoint 'fb.test' -ApiToken 'T-1234'
        }

        $result.AuthToken | Should -Be 'sess-tok'
        $null -eq $result.Username | Should -BeTrue
    }

    It 'still returns the token, with a $null Username, when the body is not JSON at all' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-WebRequest {
            [PSCustomObject]@{ Headers = @{ 'x-auth-token' = 'sess-tok' }; Content = '<html>nope</html>' }
        } -ParameterFilter { $Uri -eq 'https://fb.test/api/login' }

        $result = InModuleScope PureStorageFlashBladePowerShell {
            Invoke-PfbApiTokenLogin -Endpoint 'fb.test' -ApiToken 'T-1234'
        }

        $result.AuthToken | Should -Be 'sess-tok'
        $null -eq $result.Username | Should -BeTrue
    }

    It 'still returns the token, with a $null Username, when the response has no Content member' {
        # A response object with no Content property at all: a direct .Content read would be a
        # PropertyNotFound error under StrictMode, so the parse must go through PSObject.Properties.
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-WebRequest {
            [PSCustomObject]@{ Headers = @{ 'x-auth-token' = 'sess-tok' } }
        } -ParameterFilter { $Uri -eq 'https://fb.test/api/login' }

        $result = InModuleScope PureStorageFlashBladePowerShell {
            Invoke-PfbApiTokenLogin -Endpoint 'fb.test' -ApiToken 'T-1234'
        }

        $result.AuthToken | Should -Be 'sess-tok'
        $null -eq $result.Username | Should -BeTrue
    }

    It 'still unwraps an x-auth-token returned as a header array' {
        # WinPS 5.1 hands back header values as string[]. Pre-existing behaviour, pinned here
        # because the return shape changed around it.
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-WebRequest {
            [PSCustomObject]@{
                Headers = @{ 'x-auth-token' = @('sess-tok', 'ignored') }
                Content = '{"username":"pureuser"}'
            }
        } -ParameterFilter { $Uri -eq 'https://fb.test/api/login' }

        $result = InModuleScope PureStorageFlashBladePowerShell {
            Invoke-PfbApiTokenLogin -Endpoint 'fb.test' -ApiToken 'T-1234'
        }

        $result.AuthToken | Should -Be 'sess-tok'
    }
}

Describe 'Invoke-PfbApiTokenLogin - TimeoutSec' {
    It 'defaults to 30 seconds when -TimeoutSec is not specified' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-WebRequest {
            [PSCustomObject]@{ Headers = @{ 'x-auth-token' = 'tok' } }
        } -ParameterFilter { $Uri -eq 'https://fb.test/api/login' -and $TimeoutSec -eq 30 }

        InModuleScope PureStorageFlashBladePowerShell {
            Invoke-PfbApiTokenLogin -Endpoint 'fb.test' -ApiToken 'T-fake' | Out-Null
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-WebRequest -Times 1 -Exactly -ParameterFilter { $TimeoutSec -eq 30 }
    }

    It 'passes through an explicit -TimeoutSec' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-WebRequest {
            [PSCustomObject]@{ Headers = @{ 'x-auth-token' = 'tok' } }
        } -ParameterFilter { $Uri -eq 'https://fb.test/api/login' -and $TimeoutSec -eq 5 }

        InModuleScope PureStorageFlashBladePowerShell {
            Invoke-PfbApiTokenLogin -Endpoint 'fb.test' -ApiToken 'T-fake' -TimeoutSec 5 | Out-Null
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-WebRequest -Times 1 -Exactly -ParameterFilter { $TimeoutSec -eq 5 }
    }
}

Describe 'Invoke-PfbApiTokenLogin - errors reuse ConvertTo-PfbApiError' {
    It 'includes the unpacked API error message when the array returns a structured error body' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-WebRequest {
            $errorDetails = [System.Management.Automation.ErrorDetails]::new('{"errors":[{"message":"Invalid API token."}]}')
            $exception = [System.Exception]::new('Response status code does not indicate success: 401 ()')
            $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'Err', 'InvalidOperation', $null)
            $errorRecord.ErrorDetails = $errorDetails
            throw $errorRecord
        } -ParameterFilter { $Uri -eq 'https://fb.test/api/login' }

        { InModuleScope PureStorageFlashBladePowerShell {
            Invoke-PfbApiTokenLogin -Endpoint 'fb.test' -ApiToken 'T-bad'
        } } |
            Should -Throw -ExpectedMessage '*Invalid API token.*'
    }
}
