function Get-PfbLoginResponseUsername {
    <#
    .SYNOPSIS
        Reads the authenticated admin's name out of a POST /api/login 200 response body.
    .DESCRIPTION
        `POST /api/login` returns the authenticated admin's name in its 200 body, and has done in
        EVERY REST version 2.0 through 2.28 -- charted across all 29 cached specs: the endpoint is
        present in every version, its 200 response has a body in every version, and `username` is a
        property of that body in every version. Only the schema ARRANGEMENT changed (inline, then a
        named `Login` ref at 2.17, then `allOf: [Username]` at 2.26). What 2.26 added is acceptance
        of a username/password REQUEST body -- neither the endpoint nor the response field. Do not
        confuse the two, and do not add a version gate here: there is no version at which this
        needs one.

        The $null return is therefore MALFORMED-BODY TOLERANCE and nothing else. Do not re-justify
        it on version grounds. Nothing in here is allowed to throw: a login that already
        authenticated must never fail because a proxy rewrote the body or a test double omitted it.

        Reads through PSObject.Properties rather than touching .Content / .username directly.
        This is defensive BY CHOICE, not forced: this module does not set StrictMode anywhere, so
        a direct read of an absent property would return $null rather than throwing. The reason to
        keep it is that a real Invoke-WebRequest response always carries .Content while test
        doubles and proxied/rewritten responses may not, and the property-bag read states that
        expectation instead of relying on the absence of StrictMode to stay true.
        (An earlier version of this comment claimed the module runs under StrictMode and that the
        direct read would therefore be a terminating PropertyNotFound error. That was false --
        `Set-StrictMode` appears nowhere in the module or the Pester harness. Do not reintroduce
        the claim; if StrictMode is ever adopted, this read is already correct for it.)
    .PARAMETER Response
        The full response object from Invoke-WebRequest. $null and a Content-less object are both
        acceptable inputs and both yield $null.
    .OUTPUTS
        [string] -- the array's own spelling of the admin name, or $null if the body did not carry
        one. Never an empty string: unset and explicit-empty must not collapse.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [AllowNull()]
        $Response
    )

    if ($null -eq $Response) { return $null }

    $contentProperty = $Response.PSObject.Properties['Content']
    if ($null -eq $contentProperty) { return $null }

    # Invoke-WebRequest -UseBasicParsing gives Content as [string] on both editions; a byte[]
    # body would simply fail the parse below and land on the $null return.
    $content = [string]$contentProperty.Value
    if ([string]::IsNullOrWhiteSpace($content)) { return $null }

    try { $parsed = $content | ConvertFrom-Json -ErrorAction Stop }
    catch { return $null }
    if ($null -eq $parsed) { return $null }

    # A JSON array (or a bare scalar) has no such property and correctly yields $null.
    $nameProperty = $parsed.PSObject.Properties['username']
    if ($null -eq $nameProperty) { return $null }

    $name = [string]$nameProperty.Value
    if ([string]::IsNullOrEmpty($name)) { return $null }
    return $name
}

function Invoke-PfbApiTokenLogin {
    <#
    .SYNOPSIS
        Exchanges a FlashBlade API token for an x-auth-token session.
    .DESCRIPTION
        Shared by Connect-PfbArray's ApiToken parameter set and the post-SSH step of
        the Credential/PSCredential Posh-SSH fallback, via the unversioned /api/login
        endpoint, which accepts an api-token header on every FlashBlade REST version.
    .PARAMETER Endpoint
        The hostname or IP address of the FlashBlade array.
    .PARAMETER ApiToken
        The API token to exchange for a session token.
    .PARAMETER SkipCertificateCheck
        Bypass SSL certificate validation.
    .OUTPUTS
        [PSCustomObject] with AuthToken and Username. NOT a bare token string -- the 200 body
        carries the array's own spelling of the admin name, which is what GET /admins?names= has
        to match, and discarding it left the admin-locality gate inert for the default -ApiToken
        parameter set. Username is $null when the body did not supply one; see
        Get-PfbLoginResponseUsername.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)] [string]$Endpoint,
        [Parameter(Mandatory)] [string]$ApiToken,
        [Parameter()] [switch]$SkipCertificateCheck,
        [Parameter()] [int]$TimeoutSec = 30
    )

    $loginParams = @{
        Method     = 'POST'
        Uri        = "https://${Endpoint}/api/login"
        Headers    = @{ 'api-token' = $ApiToken }
        TimeoutSec = $TimeoutSec
    }
    if ($SkipCertificateCheck -and $PSVersionTable.PSVersion.Major -ge 6) {
        $loginParams['SkipCertificateCheck'] = $true
    }

    try {
        $loginResponse = Invoke-WebRequest @loginParams -UseBasicParsing -ErrorAction Stop
    }
    catch {
        throw "Authentication failed for FlashBlade '${Endpoint}': $(ConvertTo-PfbApiError -Method 'POST' -Endpoint 'login' -ErrorRecord $_)"
    }

    $authToken = $loginResponse.Headers['x-auth-token']
    if ($authToken -is [array]) { $authToken = $authToken[0] }
    return [PSCustomObject]@{
        AuthToken = $authToken
        Username  = Get-PfbLoginResponseUsername -Response $loginResponse
    }
}
