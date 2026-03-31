function Invoke-PfbApiRequest {
    <#
    .SYNOPSIS
        Core REST API invoker for all FlashBlade API calls.
    .DESCRIPTION
        Every public cmdlet delegates to this function. Handles URL construction,
        authentication headers, query parameters, pagination, SSL bypass, and error handling.
        Supports auto-reconnect on 401 using stored API token.
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

    $apiVer = if ($ApiVersionOverride) { $ApiVersionOverride } else { $Array.ApiVersion }
    $baseUrl = "https://$($Array.Endpoint)/api/${apiVer}"
    $queryString = ConvertTo-PfbQueryString -Parameters $QueryParams
    $uri = "${baseUrl}/${Endpoint}${queryString}"

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

    $allItems = [System.Collections.Generic.List[object]]::new()
    $totalItemCount = $null
    $hasMore = $true
    $isFirstRequest = $true

    while ($hasMore) {
        try {
            $response = Invoke-RestMethod @restParams -ErrorAction Stop
        }
        catch {
            $statusCode = $null
            if ($_.Exception.Response) {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            # Auto-reconnect on 401 if we have a stored API token
            if ($statusCode -eq 401 -and $isFirstRequest -and -not [string]::IsNullOrEmpty($Array.ApiToken)) {
                $reconnectSucceeded = $false
                try {
                    $reconnected = Connect-PfbArrayInternal -Endpoint $Array.Endpoint -ApiToken $Array.ApiToken -ApiVersion $Array.ApiVersion -SkipCertificateCheck:$Array.SkipCertificateCheck
                    $Array.AuthToken = $reconnected.AuthToken
                    $Array.ConnectedAt = $reconnected.ConnectedAt
                    $headers['x-auth-token'] = $Array.AuthToken
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
        if ($AutoPaginate -and $response.continuation_token) {
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
        [switch]$SkipCertificateCheck
    )

    $loginUri = "https://${Endpoint}/api/login"
    $loginHeaders = @{
        'api-token' = $ApiToken
    }

    $loginParams = @{
        Method  = 'POST'
        Uri     = $loginUri
        Headers = $loginHeaders
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
            if ($apiError.errors) {
                $errorMessage = "FlashBlade API error: $($apiError.errors[0].message)"
            }
        }
        catch { }
    }

    return $errorMessage
}
