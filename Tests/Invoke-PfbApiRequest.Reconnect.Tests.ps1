#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule

    function New-MockHttpError {
        param([int]$StatusCode, [string]$Message = 'mock http error')
        $ex = New-Object System.Exception($Message)
        $response = [PSCustomObject]@{ StatusCode = [System.Net.HttpStatusCode]$StatusCode }
        Add-Member -InputObject $ex -MemberType NoteProperty -Name Response -Value $response -Force
        return $ex
    }

    function New-TestConnection {
        param([string]$AuthMethod = 'ApiToken', [string]$AuthToken = 'session-token')
        [PSCustomObject]@{
            Endpoint             = 'fb.test'
            ApiVersion           = '2.26'
            AuthToken            = $AuthToken
            BearerToken          = $null
            ApiToken             = 'T-fake-token'
            AuthMethod           = $AuthMethod
            SkipCertificateCheck = $false
            ConnectedAt          = [datetime]::UtcNow
        }
    }
}

Describe 'Invoke-PfbApiRequest reconnect on session-token rejection' {
    BeforeEach {
        $script:callCount = 0
    }

    It 'reconnects and retries once on a 401 (regression guard for the original behavior)' {
        $array = New-TestConnection
        Mock -ModuleName PureStorageFlashBladePowerShell Connect-PfbArrayInternal {
            [PSCustomObject]@{ AuthToken = 'refreshed-token'; ConnectedAt = [datetime]::UtcNow }
        }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
            $script:callCount++
            if ($script:callCount -eq 1) { throw (New-MockHttpError -StatusCode 401 -Message 'unauthorized') }
            [PSCustomObject]@{ items = @() }
        } -ParameterFilter { $Uri -like '*file-systems*' }

        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ array = $array } {
            Invoke-PfbApiRequest -Array $array -Method GET -Endpoint 'file-systems' | Out-Null
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Connect-PfbArrayInternal -Times 1 -Exactly
        $array.AuthToken | Should -Be 'refreshed-token'
        $script:callCount | Should -Be 2
    }

    It 'reconnects and retries once on a 403 -- real FlashBlade returns 403 (not 401) for an invalid x-auth-token, confirmed live against our lab array' {
        $array = New-TestConnection
        Mock -ModuleName PureStorageFlashBladePowerShell Connect-PfbArrayInternal {
            [PSCustomObject]@{ AuthToken = 'refreshed-token'; ConnectedAt = [datetime]::UtcNow }
        }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
            $script:callCount++
            if ($script:callCount -eq 1) { throw (New-MockHttpError -StatusCode 403 -Message 'Access Denied') }
            [PSCustomObject]@{ items = @() }
        } -ParameterFilter { $Uri -like '*file-systems*' }

        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ array = $array } {
            Invoke-PfbApiRequest -Array $array -Method GET -Endpoint 'file-systems' | Out-Null
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Connect-PfbArrayInternal -Times 1 -Exactly
        $array.AuthToken | Should -Be 'refreshed-token'
        $script:callCount | Should -Be 2
    }

    It 'applies the 403 reconnect for Credential and PSCredential connections too -- same x-auth-token mechanism as ApiToken' {
        foreach ($method in @('Credential', 'PSCredential')) {
            $script:callCount = 0
            $array = New-TestConnection -AuthMethod $method
            Mock -ModuleName PureStorageFlashBladePowerShell Connect-PfbArrayInternal {
                [PSCustomObject]@{ AuthToken = 'refreshed-token'; ConnectedAt = [datetime]::UtcNow }
            }
            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
                $script:callCount++
                if ($script:callCount -eq 1) { throw (New-MockHttpError -StatusCode 403 -Message 'Access Denied') }
                [PSCustomObject]@{ items = @() }
            } -ParameterFilter { $Uri -like '*file-systems*' }

            InModuleScope PureStorageFlashBladePowerShell -Parameters @{ array = $array } {
                Invoke-PfbApiRequest -Array $array -Method GET -Endpoint 'file-systems' | Out-Null
            }

            $array.AuthToken | Should -Be 'refreshed-token'
        }
    }

    It 'does not reconnect on 403 when there is no stored ApiToken to reconnect with' {
        $array = New-TestConnection
        $array.ApiToken = $null
        Mock -ModuleName PureStorageFlashBladePowerShell Connect-PfbArrayInternal { throw 'should not be called' }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
            throw (New-MockHttpError -StatusCode 403 -Message 'Access Denied')
        } -ParameterFilter { $Uri -like '*file-systems*' }

        {
            InModuleScope PureStorageFlashBladePowerShell -Parameters @{ array = $array } {
                Invoke-PfbApiRequest -Array $array -Method GET -Endpoint 'file-systems' | Out-Null
            }
        } | Should -Throw -ExpectedMessage '*FlashBlade API error*'

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Connect-PfbArrayInternal -Times 0
    }

    It 'throws the original error when reconnect itself fails' {
        $array = New-TestConnection
        Mock -ModuleName PureStorageFlashBladePowerShell Connect-PfbArrayInternal { throw 'reconnect failed' }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
            throw (New-MockHttpError -StatusCode 403 -Message 'Access Denied')
        } -ParameterFilter { $Uri -like '*file-systems*' }

        {
            InModuleScope PureStorageFlashBladePowerShell -Parameters @{ array = $array } {
                Invoke-PfbApiRequest -Array $array -Method GET -Endpoint 'file-systems' | Out-Null
            }
        } | Should -Throw -ExpectedMessage '*FlashBlade API error*'
    }

    It 'does not attempt a second reconnect if the retried call also fails' {
        $array = New-TestConnection
        Mock -ModuleName PureStorageFlashBladePowerShell Connect-PfbArrayInternal {
            [PSCustomObject]@{ AuthToken = 'refreshed-token'; ConnectedAt = [datetime]::UtcNow }
        }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
            throw (New-MockHttpError -StatusCode 403 -Message 'Access Denied')
        } -ParameterFilter { $Uri -like '*file-systems*' }

        {
            InModuleScope PureStorageFlashBladePowerShell -Parameters @{ array = $array } {
                Invoke-PfbApiRequest -Array $array -Method GET -Endpoint 'file-systems' | Out-Null
            }
        } | Should -Throw -ExpectedMessage '*FlashBlade API error*'

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Connect-PfbArrayInternal -Times 1 -Exactly
    }

    It 'still throws immediately on an unrelated error code (e.g. 500)' {
        $array = New-TestConnection
        Mock -ModuleName PureStorageFlashBladePowerShell Connect-PfbArrayInternal { throw 'should not be called' }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
            throw (New-MockHttpError -StatusCode 500 -Message 'Internal Server Error')
        } -ParameterFilter { $Uri -like '*file-systems*' }

        {
            InModuleScope PureStorageFlashBladePowerShell -Parameters @{ array = $array } {
                Invoke-PfbApiRequest -Array $array -Method GET -Endpoint 'file-systems' | Out-Null
            }
        } | Should -Throw -ExpectedMessage '*FlashBlade API error*'

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Connect-PfbArrayInternal -Times 0
    }

    It 'carries the HTTP status out of the reconnect-then-throw path, not just the direct one' {
        # WHY SEPARATELY FROM Tests/ConvertTo-PfbApiError.Tests.ps1
        #
        # Invoke-PfbApiRequest has TWO throw sites that both call ConvertTo-PfbApiError, reached by
        # different statuses. A 400 takes the plain else branch. A 401/403 on a reconnectable
        # session goes through reconnect-and-retry first and, when the retry also fails, throws
        # from inside that block instead -- where the ErrorRecord being formatted is the OUTER
        # catch's original error, not the retry's.
        #
        # A live 400 against the lab array confirmed the direct branch end to end. The 403 branch
        # could NOT be provoked live: the lab credential is a full array admin, so no read is
        # refused. This pins the branch that live testing could not reach, and is mocked
        # deliberately rather than presented as live evidence.
        $array = New-TestConnection
        Mock -ModuleName PureStorageFlashBladePowerShell Connect-PfbArrayInternal {
            [PSCustomObject]@{ AuthToken = 'refreshed-token'; ConnectedAt = [datetime]::UtcNow }
        }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
            throw (New-MockHttpError -StatusCode 403 -Message 'Access Denied')
        } -ParameterFilter { $Uri -like '*file-systems*' }

        {
            InModuleScope PureStorageFlashBladePowerShell -Parameters @{ array = $array } {
                Invoke-PfbApiRequest -Array $array -Method GET -Endpoint 'file-systems' | Out-Null
            }
        } | Should -Throw -ExpectedMessage '*(HTTP 403)*'
    }

    It 'reports the ORIGINAL failure, not the reconnect failure, when the two are distinguishable' {
        # The It above cannot detect which error is reported: its fixture makes BOTH the original
        # rejection and the retry a 403, so '*(HTTP 403)*' passes either way. This one makes them
        # tell apart -- the array refuses with a 403, and the re-login then fails with a plain
        # non-HTTP error (DNS/connection class, no .Response at all).
        #
        # WHY THE ORIGINAL IS THE RIGHT ANSWER, and why this test exists at all.
        #
        # MEASURED, because the intuition here is wrong in both directions. `catch` DOES scope $_:
        # after an inner try/catch completes, $_ reverts to the enclosing catch's error record.
        # Confirmed on pwsh 7 and WinPS 5.1 with
        #   try { throw 'OUTER' } catch { try { throw 'INNER' } catch { }; $_.Exception.Message }
        # which prints OUTER on both. So the reconnect-failed site reported the ORIGINAL error both
        # before and after the message construction was hoisted to the top of the outer catch -- the
        # hoist is de-duplication, NOT a fix for a $_-leakage bug. Do not "restore" a bug here that
        # never existed.
        #
        # What was genuinely missing is a test: the It above cannot detect a regression in WHICH
        # error is reported, because its fixture makes both a 403. This one can, and reds if the
        # construction is ever moved into the inner catch.
        $array = New-TestConnection
        Mock -ModuleName PureStorageFlashBladePowerShell Connect-PfbArrayInternal {
            throw 'no such host is known: fb.test'
        }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
            throw (New-MockHttpError -StatusCode 403 -Message 'the array refused the session token')
        } -ParameterFilter { $Uri -like '*file-systems*' }

        $thrown = $null
        try {
            InModuleScope PureStorageFlashBladePowerShell -Parameters @{ array = $array } {
                Invoke-PfbApiRequest -Array $array -Method GET -Endpoint 'file-systems' | Out-Null
            }
        }
        catch { $thrown = $_.Exception.Message }

        # Sanctioned idiom rather than -Not -BeNullOrEmpty, which this branch bans outright.
        ($null -ne $thrown) | Should -BeTrue -Because 'the call must fail once the reconnect fails'
        $thrown | Should -BeLike '*the array refused the session token*'
        $thrown | Should -BeLike '*(HTTP 403)*' -Because 'the status belongs to the original response'
        $thrown | Should -Not -BeLike '*no such host*' -Because 'the reconnect failure must not replace the original'
    }
}
