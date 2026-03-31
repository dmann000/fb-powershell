function Disconnect-PfbArray {
    <#
    .SYNOPSIS
        Disconnects from a Pure Storage FlashBlade array.
    .DESCRIPTION
        Invalidates the REST API session and removes the cached connection.
    .PARAMETER Array
        The FlashBlade connection object to disconnect. If not specified, disconnects the default array.
    .EXAMPLE
        Disconnect-PfbArray
    .EXAMPLE
        Disconnect-PfbArray -Array $array
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        [PSCustomObject]$Array
    )

    process {
        if (-not $Array) {
            $Array = $script:PfbDefaultArray
        }

        if (-not $Array) {
            Write-Warning "No active FlashBlade connection to disconnect."
            return
        }

        $endpoint = $Array.Endpoint

        # Logout from the array
        $logoutUri = "https://${endpoint}/api/logout"
        $logoutHeaders = @{
            'x-auth-token' = $Array.AuthToken
        }
        $logoutParams = @{
            Method  = 'POST'
            Uri     = $logoutUri
            Headers = $logoutHeaders
        }
        if ($Array.SkipCertificateCheck -and $PSVersionTable.PSVersion.Major -ge 6) {
            $logoutParams['SkipCertificateCheck'] = $true
        }

        try {
            Invoke-RestMethod @logoutParams -ErrorAction Stop | Out-Null
        }
        catch {
            Write-Warning "Logout request failed for '${endpoint}': $($_.Exception.Message)"
        }

        # Remove from cache
        if ($script:PfbArrays.ContainsKey($endpoint)) {
            $script:PfbArrays.Remove($endpoint)
        }

        if ($script:PfbDefaultArray -and $script:PfbDefaultArray.Endpoint -eq $endpoint) {
            # Set default to the next available connection, if any
            if ($script:PfbArrays.Count -gt 0) {
                $script:PfbDefaultArray = $script:PfbArrays.Values | Select-Object -First 1
            }
            else {
                $script:PfbDefaultArray = $null
            }
        }

        Write-Verbose "Disconnected from FlashBlade '${endpoint}'."
    }
}
