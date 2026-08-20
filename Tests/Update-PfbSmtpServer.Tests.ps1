#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Covers Update-PfbSmtpServer (issue #80), the modern replacement for the deleted
    Update-PfbSmtp, which PATCHed the legacy REST 1.12 /smtp path that does not exist in 2.x.
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

Describe 'Update-PfbSmtpServer - request shape' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'typed parameters map to wire keys' {
        It 'sends -RelayHost as relay_host' {
            Update-PfbSmtpServer -RelayHost 'smtp.example.com' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['relay_host'] -eq 'smtp.example.com'
            }
        }

        It 'sends -SenderDomain as sender_domain' {
            Update-PfbSmtpServer -SenderDomain 'alerts.example.com' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['sender_domain'] -eq 'alerts.example.com'
            }
        }

        It 'sends -EncryptionMode as encryption_mode' {
            Update-PfbSmtpServer -EncryptionMode 'starttls' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['encryption_mode'] -eq 'starttls'
            }
        }

        It 'sends all three together' {
            Update-PfbSmtpServer -RelayHost 'smtp.example.com' -SenderDomain 'example.com' `
                -EncryptionMode 'starttls' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.Count -eq 3 -and
                $Body['relay_host'] -eq 'smtp.example.com' -and
                $Body['sender_domain'] -eq 'example.com' -and
                $Body['encryption_mode'] -eq 'starttls'
            }
        }
    }

    Context 'omitted parameters leave their keys absent' {
        It 'omits sender_domain and encryption_mode when only -RelayHost is supplied' {
            Update-PfbSmtpServer -RelayHost 'smtp.example.com' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('relay_host') -and
                -not $Body.ContainsKey('sender_domain') -and
                -not $Body.ContainsKey('encryption_mode')
            }
        }

        It 'sends an empty body when no typed body parameter is supplied' {
            Update-PfbSmtpServer -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.Count -eq 0
            }
        }
    }

    Context 'ContainsKey guards, not truthiness' {
        # The whole reason for the ContainsKey rule: the API documents '' as the way to CLEAR
        # encryption_mode. The deleted Update-PfbSmtp used `if ($RelayHost)` truthiness, which
        # silently dropped every empty-string value and made clearing impossible.
        It 'sends -EncryptionMode "" through as an empty string (clear-the-value case)' {
            Update-PfbSmtpServer -EncryptionMode '' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('encryption_mode') -and $Body['encryption_mode'] -eq ''
            }
        }

        It 'sends -RelayHost "" through as an empty string' {
            Update-PfbSmtpServer -RelayHost '' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('relay_host') -and $Body['relay_host'] -eq ''
            }
        }

        It 'sends -SenderDomain "" through as an empty string' {
            Update-PfbSmtpServer -SenderDomain '' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('sender_domain') -and $Body['sender_domain'] -eq ''
            }
        }
    }

    Context 'method and endpoint (guards the /smtp regression)' {
        It 'PATCHes smtp-servers, never smtp' {
            Update-PfbSmtpServer -RelayHost 'smtp.example.com' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Endpoint -eq 'smtp-servers'
            }
        }
    }

    Context '-Attributes parameter set' {
        It 'passes -Attributes through as the body verbatim' {
            Update-PfbSmtpServer -Attributes @{ relay_host = 'smtp.example.com'; encryption_mode = 'starttls' } `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['relay_host'] -eq 'smtp.example.com' -and $Body['encryption_mode'] -eq 'starttls'
            }
        }

        It 'accepts -Attributes positionally' {
            Update-PfbSmtpServer @{ relay_host = 'smtp.example.com' } -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['relay_host'] -eq 'smtp.example.com'
            }
        }

        It 'rejects -Attributes mixed with a typed parameter at bind time' {
            { Update-PfbSmtpServer -RelayHost 'smtp.example.com' -Attributes @{ relay_host = 'other.example.com' } `
                -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'
        }

        It 'rejects -EncryptionMode mixed with -Attributes at bind time' {
            { Update-PfbSmtpServer -EncryptionMode 'starttls' -Attributes @{ relay_host = 'other.example.com' } `
                -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'
        }
    }

    Context 'ShouldProcess' {
        It 'suppresses the request entirely under -WhatIf' {
            Update-PfbSmtpServer -RelayHost 'smtp.example.com' -WhatIf -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
        }

        It 'declares SupportsShouldProcess with ConfirmImpact Medium' {
            $binding = (Get-Command Update-PfbSmtpServer).ScriptBlock.Ast.Body.ParamBlock.Attributes |
                Where-Object { $_.TypeName.Name -eq 'CmdletBinding' }
            $text = $binding.Extent.Text
            $text | Should -BeLike '*SupportsShouldProcess*'
            $text | Should -BeLike "*ConfirmImpact = 'Medium'*"
        }
    }

    Context 'constraint compliance' {
        It 'puts no ValidateSet on -EncryptionMode (spec enum is open-ended)' {
            $attrs = (Get-Command Update-PfbSmtpServer).Parameters['EncryptionMode'].Attributes
            @($attrs | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).Count |
                Should -Be 0
        }

        It 'exposes every settable body field the endpoint accepts' {
            $keys = (Get-Command Update-PfbSmtpServer).Parameters.Keys
            foreach ($p in 'RelayHost', 'SenderDomain', 'EncryptionMode', 'Attributes') {
                $keys | Should -Contain $p
            }
        }
    }
}

Describe 'Update-PfbSmtpServer - encryption_mode version gate (mock-only)' {
    # Mock-only by necessity: FB-A runs REST 2.26 and can never exercise the sub-2.15 branch.
    # Invoke-PfbApiRequest is deliberately NOT mocked here -- the point is that the real
    # Assert-PfbApiCapability call inside it fires against the real Data/PfbCapabilityMap.json,
    # which records encryption_mode on PATCH /smtp-servers at 2.15.

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod { throw 'should never be called' }
    }

    It 'throws naming encryption_mode when the array is below REST 2.15' {
        $oldArray = [PSCustomObject]@{
            Endpoint             = 'fb.example.test'
            ApiVersion           = '2.14'
            AuthToken            = 'session-token'
            BearerToken          = $null
            ApiToken             = 'T-fake-token'
            AuthMethod           = 'ApiToken'
            SkipCertificateCheck = $false
        }

        { Update-PfbSmtpServer -EncryptionMode 'starttls' -Confirm:$false -Array $oldArray } |
            Should -Throw -ExpectedMessage "*request-body field 'encryption_mode'*requires REST 2.15*"

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod -Times 0 -Exactly
    }

    It 'does not throw on encryption_mode for an array at REST 2.15 or later' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod { [PSCustomObject]@{ items = @() } }

        { Update-PfbSmtpServer -EncryptionMode 'starttls' -Confirm:$false -Array $fakeArray } |
            Should -Not -Throw
    }

    It 'does not throw for relay_host alone on an array below 2.15 (2.0 field)' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod { [PSCustomObject]@{ items = @() } }

        $oldArray = [PSCustomObject]@{
            Endpoint             = 'fb.example.test'
            ApiVersion           = '2.14'
            AuthToken            = 'session-token'
            BearerToken          = $null
            ApiToken             = 'T-fake-token'
            AuthMethod           = 'ApiToken'
            SkipCertificateCheck = $false
        }

        { Update-PfbSmtpServer -RelayHost 'smtp.example.com' -Confirm:$false -Array $oldArray } |
            Should -Not -Throw
    }
}
