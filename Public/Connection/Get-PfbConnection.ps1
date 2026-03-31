function Get-PfbConnection {
    <#
    .SYNOPSIS
        Returns active FlashBlade connection(s).
    .DESCRIPTION
        Shows the currently cached FlashBlade connection(s) including endpoint, API version,
        and connection time. Does not expose sensitive tokens.
    .PARAMETER Endpoint
        Filter by a specific endpoint. If not specified, returns all connections.
    .EXAMPLE
        Get-PfbConnection
    .EXAMPLE
        Get-PfbConnection -Endpoint fb01.example.com
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Endpoint
    )

    if ($Endpoint) {
        if ($script:PfbArrays.ContainsKey($Endpoint)) {
            $conn = $script:PfbArrays[$Endpoint]
            [PSCustomObject]@{
                Endpoint       = $conn.Endpoint
                HttpEndpoint   = $conn.HttpEndpoint
                Username       = $conn.Username
                ApiVersion     = $conn.ApiVersion
                RestApiVersion = $conn.RestApiVersion
                AuthMethod     = $conn.AuthMethod
                ConnectedAt    = $conn.ConnectedAt
                IsDefault      = ($script:PfbDefaultArray -and $script:PfbDefaultArray.Endpoint -eq $conn.Endpoint)
            }
        }
        else {
            Write-Warning "No connection found for endpoint '${Endpoint}'."
        }
    }
    else {
        foreach ($key in $script:PfbArrays.Keys) {
            $conn = $script:PfbArrays[$key]
            [PSCustomObject]@{
                Endpoint       = $conn.Endpoint
                HttpEndpoint   = $conn.HttpEndpoint
                Username       = $conn.Username
                ApiVersion     = $conn.ApiVersion
                RestApiVersion = $conn.RestApiVersion
                AuthMethod     = $conn.AuthMethod
                ConnectedAt    = $conn.ConnectedAt
                IsDefault      = ($script:PfbDefaultArray -and $script:PfbDefaultArray.Endpoint -eq $conn.Endpoint)
            }
        }
    }
}
