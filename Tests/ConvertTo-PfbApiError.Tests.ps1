#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule

    function New-ErrorRecordWithBody {
        param(
            [string]$Body,
            [string]$Message = 'mock http error',
            # Omitted entirely = an exception with NO .Response at all, i.e. a failure that never
            # reached the array (DNS, timeout, certificate rejection).
            [int]$StatusCode,
            # Attach .Response but with an unusable status, to exercise the range guard.
            [switch]$ResponseWithoutStatus
        )
        $ex = New-Object System.Exception($Message)

        # Duck-typed the same way Tests/Invoke-PfbApiRequest.Reconnect.Tests.ps1 fakes it, which
        # is also how the production reconnect gate reads it. A real HttpResponseException cannot
        # be constructed identically on both PowerShell 5.1 and 7, and this module supports both.
        if ($ResponseWithoutStatus) {
            # An object with no StatusCode member at all. [System.Net.HttpStatusCode]0 cannot be
            # used here -- 0 is not a defined value of that enum and the cast throws.
            $response = [PSCustomObject]@{ ReasonPhrase = 'none' }
            Add-Member -InputObject $ex -MemberType NoteProperty -Name Response -Value $response -Force
        }
        elseif ($PSBoundParameters.ContainsKey('StatusCode')) {
            $response = [PSCustomObject]@{ StatusCode = [System.Net.HttpStatusCode]$StatusCode }
            Add-Member -InputObject $ex -MemberType NoteProperty -Name Response -Value $response -Force
        }

        $errorRecord = New-Object System.Management.Automation.ErrorRecord(
            $ex, 'MockError', [System.Management.Automation.ErrorCategory]::NotSpecified, $null)
        if ($PSBoundParameters.ContainsKey('Body')) {
            $errorRecord.ErrorDetails = New-Object System.Management.Automation.ErrorDetails($Body)
        }
        return $errorRecord
    }

    function Invoke-Convert {
        param([System.Management.Automation.ErrorRecord]$ErrorRecord, [string]$Method = 'GET',
              [string]$Endpoint = 'arrays')
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{
            errorRecord = $ErrorRecord; method = $Method; endpoint = $Endpoint
        } {
            ConvertTo-PfbApiError -Method $method -Endpoint $endpoint -ErrorRecord $errorRecord
        }
    }
}

Describe 'ConvertTo-PfbApiError' {
    It 'extracts the message from a plural .errors[] body' {
        $errorRecord = New-ErrorRecordWithBody -Body '{"errors":[{"code":401,"context":"/api/2.26/arrays","message":"Invalid session token."}]}'

        $result = InModuleScope PureStorageFlashBladePowerShell -Parameters @{ errorRecord = $errorRecord } {
            ConvertTo-PfbApiError -Method 'GET' -Endpoint 'arrays' -ErrorRecord $errorRecord
        }

        $result | Should -Be 'FlashBlade API error: Invalid session token.'
    }

    It 'extracts the message from a singular .error[] body (real FlashBlade 4.8.2 shape)' {
        # Live testing against a real FlashBlade array (Purity//FB 4.8.2 / REST 2.26) proved that its
        # error responses use the singular key "error" (still an array of objects), not the plural
        # "errors" this function previously assumed exclusively:
        # {"error":[{"code":403,"context":"/api/2.26/arrays","message":"Access Denied"}]}
        $errorRecord = New-ErrorRecordWithBody -Body '{"error":[{"code":403,"context":"/api/2.26/arrays","message":"Access Denied"}]}'

        $result = InModuleScope PureStorageFlashBladePowerShell -Parameters @{ errorRecord = $errorRecord } {
            ConvertTo-PfbApiError -Method 'GET' -Endpoint 'arrays' -ErrorRecord $errorRecord
        }

        $result | Should -Be 'FlashBlade API error: Access Denied'
    }

    It 'prefers the plural .errors[] key when both .errors and .error are somehow present' {
        $errorRecord = New-ErrorRecordWithBody -Body '{"errors":[{"code":400,"message":"plural wins"}],"error":[{"code":400,"message":"singular loses"}]}'

        $result = InModuleScope PureStorageFlashBladePowerShell -Parameters @{ errorRecord = $errorRecord } {
            ConvertTo-PfbApiError -Method 'GET' -Endpoint 'arrays' -ErrorRecord $errorRecord
        }

        $result | Should -Be 'FlashBlade API error: plural wins'
    }
}

Describe 'ConvertTo-PfbApiError HTTP status reporting' {
    It 'reports the status on a parsed error body, which replaces the message wholesale' {
        # The regression this guards: the body-parsing branch REPLACES the transport message, and
        # the transport message is where the status text lived. So the failures that carry a
        # readable body -- every deliberate API rejection -- were the ones that lost the status.
        $result = Invoke-Convert (New-ErrorRecordWithBody -StatusCode 403 `
            -Body '{"error":[{"code":403,"context":"/api/2.26/arrays","message":"Access Denied"}]}')

        $result | Should -Be 'FlashBlade API error (HTTP 403): Access Denied'
    }

    It 'reports the status when there is no parseable body' {
        $result = Invoke-Convert (New-ErrorRecordWithBody -StatusCode 503 -Message 'Service Unavailable')

        $result | Should -Be 'FlashBlade API error on GET arrays (HTTP 503): Service Unavailable'
    }

    It 'does not confuse the body error code with the HTTP status' {
        # These are different numbers and only sometimes agree. A write rejected for targeting the
        # wrong array in a fleet comes back as application code 13 inside an HTTP 400. Taking the
        # status from the body would report "(HTTP 13)" -- not a status code at all, yet entirely
        # believable to whatever is reading it.
        $result = Invoke-Convert (New-ErrorRecordWithBody -StatusCode 400 `
            -Body '{"errors":[{"code":13,"message":"Cannot be modified on a member array."}]}')

        $result | Should -Be 'FlashBlade API error (HTTP 400): Cannot be modified on a member array.'
        $result | Should -Not -Match 'HTTP 13'
    }

    It 'omits the status entirely when the failure never produced an HTTP response' {
        # A DNS failure, connection timeout or rejected certificate has no status to report, and
        # must not be given a fabricated one. Absent reads as unknown; wrong gets believed.
        $result = Invoke-Convert (New-ErrorRecordWithBody -Message 'The remote name could not be resolved')

        $result | Should -Be 'FlashBlade API error on GET arrays: The remote name could not be resolved'
        $result | Should -Not -Match 'HTTP'
    }

    It 'omits the status when a response exists but carries no usable one, rather than saying HTTP 0' {
        # Defensive rather than a known live shape: no real HTTP response reports status 0. It
        # guards the [int] cast, which turns an absent StatusCode into 0 rather than $null.
        $result = Invoke-Convert (New-ErrorRecordWithBody -ResponseWithoutStatus -Message 'truncated response')

        $result | Should -Not -Match 'HTTP'
    }

    It 'emits the status in a form a consumer can actually parse back out' {
        # The message string is the whole interface here: callers catching this across a module
        # boundary get a plain RuntimeException with no structured status field to read. So the
        # exact "(HTTP nnn)" shape is the contract, and this asserts it stays machine-readable
        # rather than merely containing the digits somewhere.
        foreach ($code in 400, 403, 404, 500, 503) {
            $result = Invoke-Convert (New-ErrorRecordWithBody -StatusCode $code `
                -Body "{`"errors`":[{`"code`":$code,`"message`":`"rejected`"}]}")

            $result | Should -Match '\(HTTP\s+\d{3}\)'
            [int]([regex]::Match($result, '\(HTTP\s+(\d{3})\)').Groups[1].Value) | Should -Be $code
        }
    }
}
