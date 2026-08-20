#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule

    $script:testPassword = ConvertTo-SecureString 'hunter2' -AsPlainText -Force
}

Describe 'Connect-PfbArray - version negotiation (post-refactor)' {
    It 'negotiates the highest supported 2.x version numerically, ignoring 1.x noise' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
            [PSCustomObject]@{ versions = @('1.8', '1.9', '2.9', '2.10', '2.26') }
        } -ParameterFilter { $Uri -like '*api_version*' }

        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-WebRequest {
            [PSCustomObject]@{ Headers = @{ 'x-auth-token' = 'tok' } }
        } -ParameterFilter { $Uri -eq 'https://fb.test/api/login' }

        $conn = Connect-PfbArray -Endpoint 'fb.test' -ApiToken 'T-fake'

        $conn.ApiVersion | Should -Be '2.26'
    }

    It 'throws when the array supports no REST API 2.x versions at all' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
            [PSCustomObject]@{ versions = @('1.8', '1.9') }
        } -ParameterFilter { $Uri -like '*api_version*' }

        { Connect-PfbArray -Endpoint 'fb.test' -ApiToken 'T-fake' } |
            Should -Throw -ExpectedMessage '*No REST API 2.x versions supported*'
    }
}

Describe 'Connect-PfbArray - native login version gate + Posh-SSH fallback' {

    Context 'Array supports native login (>= 2.26)' {
        It 'uses the native /api/login path and never invokes the SSH fallback' {
            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
                [PSCustomObject]@{ versions = @('2.20', '2.25', '2.26') }
            } -ParameterFilter { $Uri -like '*api_version*' }

            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-WebRequest {
                [PSCustomObject]@{ Headers = @{ 'x-auth-token' = 'native-token' } }
            } -ParameterFilter { $Uri -eq 'https://fb.test/api/login' }

            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
                throw 'no admin token available'
            } -ParameterFilter { $Uri -like '*admins/api-tokens*' }

            Mock -ModuleName PureStorageFlashBladePowerShell Get-PfbApiTokenViaSsh { throw 'should not be called' }

            $conn = Connect-PfbArray -Endpoint 'fb.test' -Username 'pureuser' -Password $script:testPassword

            $conn.AuthToken | Should -Be 'native-token'
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Get-PfbApiTokenViaSsh -Times 0
        }

        It 'sends the full, untruncated password in the /api/login request body' {
            # Regression test for the SecureString->BSTR marshaling bug: Marshal.PtrToStringAuto
            # is ANSI on non-Windows platforms and silently truncates a UTF-16 BSTR at its first
            # null byte -- i.e. after only the first character -- so a naive mock that ignores
            # $Body (like the test above) can't catch it. Assert on the actual decoded password.
            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
                [PSCustomObject]@{ versions = @('2.26') }
            } -ParameterFilter { $Uri -like '*api_version*' }

            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-WebRequest {
                [PSCustomObject]@{ Headers = @{ 'x-auth-token' = 'native-token' } }
            } -ParameterFilter { $Uri -eq 'https://fb.test/api/login' }

            Connect-PfbArray -Endpoint 'fb.test' -Username 'pureuser' -Password $script:testPassword | Out-Null

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'https://fb.test/api/login' -and ($Body | ConvertFrom-Json).password -eq 'hunter2'
            }
        }
    }

    Context 'Array does not support native login (< 2.26)' {
        It 'falls back to Get-PfbApiTokenViaSsh and completes login with the minted token' {
            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
                [PSCustomObject]@{ versions = @('1.10', '1.11', '1.12', '2.20', '2.25') }
            } -ParameterFilter { $Uri -like '*api_version*' }

            Mock -ModuleName PureStorageFlashBladePowerShell Get-PfbApiTokenViaSsh { 'T-minted-via-ssh' }

            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-WebRequest {
                [PSCustomObject]@{ Headers = @{ 'x-auth-token' = 'ssh-session-token' } }
            } -ParameterFilter { $Uri -eq 'https://fb.test/api/login' -and $Headers['api-token'] -eq 'T-minted-via-ssh' }

            $conn = Connect-PfbArray -Endpoint 'fb.test' -Username 'pureuser' -Password $script:testPassword

            $conn.AuthToken | Should -Be 'ssh-session-token'
            $conn.ApiToken  | Should -Be 'T-minted-via-ssh'
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Get-PfbApiTokenViaSsh -Times 1 -Exactly
        }

        It 'falls back to Get-PfbApiTokenViaSsh via the -Credential (PSCredential) parameter set too' {
            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
                [PSCustomObject]@{ versions = @('1.10', '1.11', '1.12', '2.20', '2.25') }
            } -ParameterFilter { $Uri -like '*api_version*' }

            Mock -ModuleName PureStorageFlashBladePowerShell Get-PfbApiTokenViaSsh { 'T-minted-via-ssh' }

            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-WebRequest {
                [PSCustomObject]@{ Headers = @{ 'x-auth-token' = 'ssh-session-token' } }
            } -ParameterFilter { $Uri -eq 'https://fb.test/api/login' -and $Headers['api-token'] -eq 'T-minted-via-ssh' }

            $cred = [System.Management.Automation.PSCredential]::new('pureuser', $script:testPassword)
            $conn = Connect-PfbArray -Endpoint 'fb.test' -Credential $cred

            $conn.AuthToken | Should -Be 'ssh-session-token'
            $conn.ApiToken  | Should -Be 'T-minted-via-ssh'
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Get-PfbApiTokenViaSsh -Times 1 -Exactly -ParameterFilter { $Username -eq 'pureuser' }
        }
    }

    Context 'SSH fallback fails' {
        It 'throws a comprehensive error covering both the version gap and the SSH failure' {
            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
                [PSCustomObject]@{ versions = @('2.20', '2.25') }
            } -ParameterFilter { $Uri -like '*api_version*' }

            Mock -ModuleName PureStorageFlashBladePowerShell Get-PfbApiTokenViaSsh {
                throw "The Posh-SSH module is required for SSH-based API token generation but is not installed."
            }

            { Connect-PfbArray -Endpoint 'fb.test' -Username 'pureuser' -Password $script:testPassword } |
                Should -Throw -ExpectedMessage '*Posh-SSH module is required*'
        }
    }

    Context '-ApiToken parameter set is unaffected' {
        It 'authenticates via Invoke-PfbApiTokenLogin regardless of array version' {
            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
                [PSCustomObject]@{ versions = @('1.10', '1.11', '1.12', '2.20', '2.25') }
            } -ParameterFilter { $Uri -like '*api_version*' }

            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-WebRequest {
                [PSCustomObject]@{ Headers = @{ 'x-auth-token' = 'apitoken-session' } }
            } -ParameterFilter { $Uri -eq 'https://fb.test/api/login' }

            Mock -ModuleName PureStorageFlashBladePowerShell Get-PfbApiTokenViaSsh { throw 'should not be called' }

            $conn = Connect-PfbArray -Endpoint 'fb.test' -ApiToken 'T-fake-token'

            $conn.AuthToken | Should -Be 'apitoken-session'
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Get-PfbApiTokenViaSsh -Times 0
        }
    }
}

Describe 'Connect-PfbArray - HttpTimeout is applied to requests' {
    It 'converts -HttpTimeout milliseconds to whole TimeoutSec and applies it to /api/api_version' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
            [PSCustomObject]@{ versions = @('2.26') }
        } -ParameterFilter { $Uri -like '*api_version*' -and $TimeoutSec -eq 15 }

        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-WebRequest {
            [PSCustomObject]@{ Headers = @{ 'x-auth-token' = 'tok' } }
        } -ParameterFilter { $Uri -eq 'https://fb.test/api/login' }

        Connect-PfbArray -Endpoint 'fb.test' -ApiToken 'T-fake' -HttpTimeout 15000 | Out-Null

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $Uri -like '*api_version*' -and $TimeoutSec -eq 15
        }
    }

    It 'rounds up a sub-1-second timeout instead of collapsing to 0' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
            [PSCustomObject]@{ versions = @('2.26') }
        } -ParameterFilter { $Uri -like '*api_version*' -and $TimeoutSec -eq 1 }

        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-WebRequest {
            [PSCustomObject]@{ Headers = @{ 'x-auth-token' = 'tok' } }
        } -ParameterFilter { $Uri -eq 'https://fb.test/api/login' }

        Connect-PfbArray -Endpoint 'fb.test' -ApiToken 'T-fake' -HttpTimeout 500 | Out-Null

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $Uri -like '*api_version*' -and $TimeoutSec -eq 1
        }
    }

    It 'applies the timeout to the api-token login call via Invoke-PfbApiTokenLogin' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
            [PSCustomObject]@{ versions = @('2.26') }
        } -ParameterFilter { $Uri -like '*api_version*' }

        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-WebRequest {
            [PSCustomObject]@{ Headers = @{ 'x-auth-token' = 'tok' } }
        } -ParameterFilter { $Uri -eq 'https://fb.test/api/login' -and $TimeoutSec -eq 20 }

        Connect-PfbArray -Endpoint 'fb.test' -ApiToken 'T-fake' -HttpTimeout 20000 | Out-Null

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -eq 'https://fb.test/api/login' -and $TimeoutSec -eq 20
        }
    }

    It 'applies the timeout to the Posh-SSH-fallback login path too' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
            [PSCustomObject]@{ versions = @('2.20', '2.25') }
        } -ParameterFilter { $Uri -like '*api_version*' }

        Mock -ModuleName PureStorageFlashBladePowerShell Get-PfbApiTokenViaSsh { 'T-minted' }

        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-WebRequest {
            [PSCustomObject]@{ Headers = @{ 'x-auth-token' = 'ssh-tok' } }
        } -ParameterFilter { $Uri -eq 'https://fb.test/api/login' -and $TimeoutSec -eq 20 }

        $pw = ConvertTo-SecureString 'hunter2' -AsPlainText -Force
        Connect-PfbArray -Endpoint 'fb.test' -Username 'pureuser' -Password $pw -HttpTimeout 20000 | Out-Null

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -eq 'https://fb.test/api/login' -and $TimeoutSec -eq 20
        }
    }
}

Describe 'Connect-PfbArray - TLS 1.2 enforcement decoupled from cert-bypass' {
    It 'forces TLS 1.2 even when -IgnoreCertificateError is not specified' {
        Mock -ModuleName PureStorageFlashBladePowerShell Set-PfbTlsProtocol { }
        Mock -ModuleName PureStorageFlashBladePowerShell Set-PfbCertificatePolicy { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
            [PSCustomObject]@{ versions = @('2.26') }
        } -ParameterFilter { $Uri -like '*api_version*' }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-WebRequest {
            [PSCustomObject]@{ Headers = @{ 'x-auth-token' = 'tok' } }
        } -ParameterFilter { $Uri -eq 'https://fb.test/api/login' }

        Connect-PfbArray -Endpoint 'fb.test' -ApiToken 'T-fake' | Out-Null

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Set-PfbTlsProtocol -Times 1 -Exactly
        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Set-PfbCertificatePolicy -Times 0
    }

    It 'still applies certificate bypass only when -IgnoreCertificateError is specified' {
        Mock -ModuleName PureStorageFlashBladePowerShell Set-PfbTlsProtocol { }
        Mock -ModuleName PureStorageFlashBladePowerShell Set-PfbCertificatePolicy { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
            [PSCustomObject]@{ versions = @('2.26') }
        } -ParameterFilter { $Uri -like '*api_version*' }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-WebRequest {
            [PSCustomObject]@{ Headers = @{ 'x-auth-token' = 'tok' } }
        } -ParameterFilter { $Uri -eq 'https://fb.test/api/login' }

        Connect-PfbArray -Endpoint 'fb.test' -ApiToken 'T-fake' -IgnoreCertificateError | Out-Null

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Set-PfbTlsProtocol -Times 1 -Exactly
        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Set-PfbCertificatePolicy -Times 1 -Exactly
    }
}

Describe 'Connect-PfbArray - errors reuse ConvertTo-PfbApiError' {
    It 'includes the unpacked API error message when /api/api_version returns a structured error body' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
            $errorDetails = [System.Management.Automation.ErrorDetails]::new('{"errors":[{"message":"array unreachable"}]}')
            $exception = [System.Exception]::new('Response status code does not indicate success: 503 ()')
            $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'Err', 'InvalidOperation', $null)
            $errorRecord.ErrorDetails = $errorDetails
            throw $errorRecord
        } -ParameterFilter { $Uri -like '*api_version*' }

        { Connect-PfbArray -Endpoint 'fb.test' -ApiToken 'T-fake' } |
            Should -Throw -ExpectedMessage '*array unreachable*'
    }

    It 'includes the unpacked API error message when native login returns a structured error body' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
            [PSCustomObject]@{ versions = @('2.26') }
        } -ParameterFilter { $Uri -like '*api_version*' }

        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-WebRequest {
            $errorDetails = [System.Management.Automation.ErrorDetails]::new('{"errors":[{"message":"Invalid credentials."}]}')
            $exception = [System.Exception]::new('Response status code does not indicate success: 400 ()')
            $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'Err', 'InvalidOperation', $null)
            $errorRecord.ErrorDetails = $errorDetails
            throw $errorRecord
        } -ParameterFilter { $Uri -eq 'https://fb.test/api/login' }

        $pw = ConvertTo-SecureString 'hunter2' -AsPlainText -Force
        { Connect-PfbArray -Endpoint 'fb.test' -Username 'pureuser' -Password $pw } |
            Should -Throw -ExpectedMessage '*Invalid credentials.*'
    }
}
