function Invoke-PfbApiRequest {
    <#
    .SYNOPSIS
        Core REST API invoker for all FlashBlade API calls.
    .DESCRIPTION
        Every public cmdlet delegates to this function. Handles URL construction,
        authentication headers, query parameters, pagination, SSL bypass, and error handling.
        Supports auto-reconnect using a stored API token when the session token is rejected.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Array,

        [Parameter(Mandatory)]
        [ValidateSet('GET', 'POST', 'PATCH', 'DELETE')]
        [string]$Method,

        [Parameter(Mandatory)]
        [string]$Endpoint,

        [Parameter()]
        [hashtable]$Body,

        [Parameter()]
        [hashtable]$QueryParams,

        [Parameter()]
        [switch]$AutoPaginate,

        [Parameter()]
        [switch]$Raw,

        [Parameter()]
        [string]$ApiVersionOverride
    )

    # Fail fast if the connected array's REST version doesn't support this endpoint/param/
    # field, before any network call is made. Never sent if incompatible: see
    # Assert-PfbApiCapability's header for why an unrecognized endpoint is a silent no-op.
    Assert-PfbApiCapability -Array $Array -Method $Method -Endpoint $Endpoint -Body $Body -QueryParams $QueryParams -ApiVersion $ApiVersionOverride

    # Certificate/OAuth2 sessions: proactively refresh the access token before it expires,
    # rather than waiting for a 401. A proactive refresh generates no failed-authentication
    # entry in the array's session log, unlike a reactive 401-triggered refresh.
    if ($Array.AuthMethod -eq 'Certificate' -and $Array.TokenExpiresAt) {
        $buffer = [Math]::Min(30, $Array.TokenTtlSeconds * 0.10)
        $refreshAt = $Array.TokenExpiresAt.AddSeconds(-$buffer)
        if ((Get-Date).ToUniversalTime() -ge $refreshAt) {
            # A failure here is NOT fatal: the current token may still be valid (we're only
            # inside the buffer window, not past actual expiry). Warn and fall through to
            # attempt the request with the existing token -- the reactive 401 path below is
            # the real safety net if the token has genuinely become invalid.
            try {
                $refreshed = Invoke-PfbOAuth2Login -Endpoint $Array.Endpoint -ClientId $Array.ClientId `
                    -Issuer $Array.Issuer -KeyId $Array.KeyId -Username $Array.Username `
                    -PrivateKeyFile $Array.PrivateKeyFile -PrivateKeyPassword $Array.PrivateKeyPassword `
                    -SkipCertificateCheck:$Array.SkipCertificateCheck
                $Array.BearerToken = $refreshed.AccessToken
                $Array.AuthToken = $refreshed.AccessToken
                $Array.TokenExpiresAt = $refreshed.ExpiresAt
                $Array.TokenTtlSeconds = $refreshed.TtlSeconds

                if ($script:PfbDefaultArray -and $script:PfbDefaultArray.Endpoint -eq $Array.Endpoint) {
                    $script:PfbDefaultArray = $Array
                }
                if ($script:PfbArrays.ContainsKey($Array.Endpoint)) {
                    $script:PfbArrays[$Array.Endpoint] = $Array
                }
            }
            catch {
                Write-Warning "FlashBlade proactive OAuth2 token refresh failed for $($Array.Endpoint): $($_.Exception.Message). Proceeding with the existing token."
            }
        }
    }

    $apiVer = if ($ApiVersionOverride) { $ApiVersionOverride } else { $Array.ApiVersion }
    $baseUrl = "https://$($Array.Endpoint)/api/${apiVer}"
    $queryString = ConvertTo-PfbQueryString -Parameters $QueryParams
    $uri = "${baseUrl}/${Endpoint}${queryString}"

    Write-Verbose "FlashBlade API: $Method $uri"

    $headers = @{
        'Content-Type' = 'application/json'
    }
    if ($Array.BearerToken) {
        $headers['Authorization'] = "Bearer $($Array.BearerToken)"
    }
    else {
        $headers['x-auth-token'] = $Array.AuthToken
    }

    $restParams = @{
        Method  = $Method
        Uri     = $uri
        Headers = $headers
    }

    if ($Body -and ($Method -eq 'POST' -or $Method -eq 'PATCH')) {
        $restParams['Body'] = ($Body | ConvertTo-Json -Depth 10 -Compress)
    }

    # SSL handling
    if ($Array.SkipCertificateCheck -and $PSVersionTable.PSVersion.Major -ge 6) {
        $restParams['SkipCertificateCheck'] = $true
    }

    # HTTP timeout handling — default to 30s if the connection object predates this field
    $restParams['TimeoutSec'] = if ($Array.HttpTimeoutMs) { [int][Math]::Ceiling($Array.HttpTimeoutMs / 1000.0) } else { 30 }

    # If the caller set a page-size/limit query param (every Get-Pfb* cmdlet's -Limit maps to
    # this), treat it as a hard cap on the running total across pages -- Purity//FB REST treats
    # `limit` as page size only and keeps returning a continuation_token even once the caller's
    # desired item count has been reached, so AutoPaginate must stop itself.
    $requestedLimit = $null
    if ($QueryParams -and $QueryParams.ContainsKey('limit') -and [int]$QueryParams['limit'] -gt 0) {
        $requestedLimit = [int]$QueryParams['limit']
    }

    $allItems = [System.Collections.Generic.List[object]]::new()
    $totalItemCount = $null
    $hasMore = $true
    $isFirstRequest = $true

    $pageIndex = 0
    while ($hasMore) {
        $pageIndex++
        if ($pageIndex -gt 1) { Write-Verbose "FlashBlade API: $Method $uri (page $pageIndex)" }
        try {
            $response = Invoke-RestMethod @restParams -ErrorAction Stop
        }
        catch {
            $statusCode = $null
            if ($_.Exception.Response) {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            # Auto-reconnect on an auth failure: ApiToken/Credential/PSCredential sessions
            # have a cached long-lived API token to re-login with; Certificate sessions
            # refresh the OAuth2 access token instead (fallback for what the proactive check
            # above can't anticipate: clock skew, or early revocation).
            $canReconnect = ($isFirstRequest -and (
                -not [string]::IsNullOrEmpty($Array.ApiToken) -or $Array.AuthMethod -eq 'Certificate'
            ))

            # Live testing against real FlashBlade arrays proved they return HTTP 403, not 401,
            # for a missing/invalid token -- confirmed for BOTH the x-auth-token session header
            # (ApiToken/Credential/PSCredential) and the OAuth2 Bearer token (Certificate). So the
            # reconnect gate must fire on 401 OR 403 for every auth method; a 401-only (or
            # 403-Certificate-only) gate never actually triggers against a real array.
            $isAuthFailureStatus = ($statusCode -eq 401 -or $statusCode -eq 403)
            if ($isAuthFailureStatus -and $canReconnect) {
                $reconnectSucceeded = $false
                try {
                    if ($Array.AuthMethod -eq 'Certificate') {
                        $refreshed = Invoke-PfbOAuth2Login -Endpoint $Array.Endpoint -ClientId $Array.ClientId `
                            -Issuer $Array.Issuer -KeyId $Array.KeyId -Username $Array.Username `
                            -PrivateKeyFile $Array.PrivateKeyFile -PrivateKeyPassword $Array.PrivateKeyPassword `
                            -SkipCertificateCheck:$Array.SkipCertificateCheck
                        $Array.BearerToken = $refreshed.AccessToken
                        $Array.AuthToken = $refreshed.AccessToken
                        $Array.TokenExpiresAt = $refreshed.ExpiresAt
                        $Array.TokenTtlSeconds = $refreshed.TtlSeconds
                        $headers['Authorization'] = "Bearer $($Array.BearerToken)"
                    }
                    else {
                        $reconnected = Connect-PfbArrayInternal -Endpoint $Array.Endpoint -ApiToken $Array.ApiToken -ApiVersion $Array.ApiVersion -SkipCertificateCheck:$Array.SkipCertificateCheck -TimeoutSec $restParams['TimeoutSec']
                        $Array.AuthToken = $reconnected.AuthToken
                        $Array.ConnectedAt = $reconnected.ConnectedAt
                        $headers['x-auth-token'] = $Array.AuthToken
                    }
                    $restParams['Headers'] = $headers

                    # Update the stored connection
                    if ($script:PfbDefaultArray -and $script:PfbDefaultArray.Endpoint -eq $Array.Endpoint) {
                        $script:PfbDefaultArray = $Array
                    }
                    if ($script:PfbArrays.ContainsKey($Array.Endpoint)) {
                        $script:PfbArrays[$Array.Endpoint] = $Array
                    }

                    $response = Invoke-RestMethod @restParams -ErrorAction Stop
                    $reconnectSucceeded = $true
                }
                catch {
                    # Reconnect failed — fall through to error formatting below
                }

                if (-not $reconnectSucceeded) {
                    throw (ConvertTo-PfbApiError -Method $Method -Endpoint $Endpoint -ErrorRecord $_)
                }
            }
            else {
                throw (ConvertTo-PfbApiError -Method $Method -Endpoint $Endpoint -ErrorRecord $_)
            }
        }

        $isFirstRequest = $false

        # Return raw response if requested
        if ($Raw) {
            return $response
        }

        # Collect items
        if ($null -ne $response.items) {
            foreach ($item in $response.items) {
                $allItems.Add($item)
            }
        }
        elseif ($null -ne $response) {
            # Some endpoints return data directly (not wrapped in items)
            return $response
        }

        # Track total count from first response
        if ($null -eq $totalItemCount -and $null -ne $response.total_item_count) {
            $totalItemCount = $response.total_item_count
        }

        # Handle pagination
        $limitReached = ($null -ne $requestedLimit -and $allItems.Count -ge $requestedLimit)
        if ($AutoPaginate -and $response.continuation_token -and -not $limitReached) {
            # Update the URI with continuation token
            if (-not $QueryParams) { $QueryParams = @{} }
            $QueryParams['continuation_token'] = $response.continuation_token
            $queryString = ConvertTo-PfbQueryString -Parameters $QueryParams
            $uri = "${baseUrl}/${Endpoint}${queryString}"
            $restParams['Uri'] = $uri
        }
        else {
            $hasMore = $false
        }
    }

    # The last page fetched may have overshot the requested limit (server-side page size is
    # independent of it) -- trim so callers get exactly what they asked for.
    if ($null -ne $requestedLimit -and $allItems.Count -gt $requestedLimit) {
        $allItems = $allItems.GetRange(0, $requestedLimit)
    }

    # If TotalOnly was requested and we got a count but no items, return the count
    if ($allItems.Count -eq 0 -and $null -ne $totalItemCount) {
        return [PSCustomObject]@{ total_item_count = $totalItemCount }
    }

    return $allItems.ToArray()
}

function Connect-PfbArrayInternal {
    <#
    .SYNOPSIS
        Internal helper to perform the login API call.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Endpoint,

        [Parameter(Mandatory)]
        [string]$ApiToken,

        [Parameter()]
        [string]$ApiVersion = '2.0',

        [Parameter()]
        [switch]$SkipCertificateCheck,

        [Parameter()]
        [int]$TimeoutSec = 30
    )

    $loginUri = "https://${Endpoint}/api/login"
    $loginHeaders = @{
        'api-token' = $ApiToken
    }

    $loginParams = @{
        Method  = 'POST'
        Uri     = $loginUri
        Headers = $loginHeaders
        TimeoutSec = $TimeoutSec
    }

    if ($SkipCertificateCheck -and $PSVersionTable.PSVersion.Major -ge 6) {
        $loginParams['SkipCertificateCheck'] = $true
    }

    $loginResponse = Invoke-WebRequest @loginParams -UseBasicParsing -ErrorAction Stop
    $authToken = $loginResponse.Headers['x-auth-token']
    if ($authToken -is [array]) { $authToken = $authToken[0] }

    return [PSCustomObject]@{
        AuthToken   = $authToken
        ConnectedAt = [datetime]::UtcNow
    }
}

function ConvertTo-PfbApiError {
    <#
    .SYNOPSIS
        Formats a FlashBlade API error into a readable message, preserving the original exception.
    #>
    [CmdletBinding()]
    param(
        [string]$Method,
        [string]$Endpoint,
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $errorMessage = "FlashBlade API error on ${Method} ${Endpoint}: $($ErrorRecord.Exception.Message)"
    if ($ErrorRecord.ErrorDetails.Message) {
        try {
            $apiError = $ErrorRecord.ErrorDetails.Message | ConvertFrom-Json
            # Most FlashBlade error bodies use the plural key "errors", but some real-world
            # responses (confirmed live against Purity//FB 4.8.2 / REST 2.26) use the singular
            # "error" instead -- same array-of-objects shape, different key name. Prefer plural
            # if both are somehow present.
            $errorList = if ($apiError.errors) { $apiError.errors } else { $apiError.error }
            if ($errorList) {
                $errorMessage = "FlashBlade API error: $($errorList[0].message)"
            }
        }
        catch { }
    }

    return $errorMessage
}
