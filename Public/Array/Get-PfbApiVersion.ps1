function Get-PfbApiVersion {
    <#
    .SYNOPSIS
        Retrieves supported REST API versions from a FlashBlade array.
    .DESCRIPTION
        Queries the FlashBlade for all supported API versions. Does not require authentication.
    .PARAMETER Endpoint
        The hostname or IP address of the FlashBlade. If not specified, uses the default connection's endpoint.
    .PARAMETER Array
        The FlashBlade connection object. Used to derive the endpoint if -Endpoint is not specified.
    .PARAMETER IgnoreCertificateError
        Bypass SSL certificate validation.
    .EXAMPLE
        Get-PfbApiVersion -Endpoint fb01.example.com -IgnoreCertificateError
    .EXAMPLE
        Get-PfbApiVersion
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Endpoint,

        [Parameter()]
        [PSCustomObject]$Array,

        [Parameter()]
        [switch]$IgnoreCertificateError
    )

    if (-not $Endpoint) {
        if ($Array) {
            $Endpoint = $Array.Endpoint
            $IgnoreCertificateError = $Array.SkipCertificateCheck
        }
        elseif ($script:PfbDefaultArray) {
            $Endpoint = $script:PfbDefaultArray.Endpoint
            $IgnoreCertificateError = $script:PfbDefaultArray.SkipCertificateCheck
        }
        else {
            throw "Specify -Endpoint or connect to a FlashBlade first with Connect-PfbArray."
        }
    }

    if ($IgnoreCertificateError) {
        Set-PfbCertificatePolicy
    }

    $uri = "https://${Endpoint}/api/api_version"
    $params = @{
        Method = 'GET'
        Uri    = $uri
    }
    if ($IgnoreCertificateError -and $PSVersionTable.PSVersion.Major -ge 6) {
        $params['SkipCertificateCheck'] = $true
    }

    try {
        $response = Invoke-RestMethod @params -ErrorAction Stop
        return $response.versions
    }
    catch {
        throw "Failed to retrieve API versions from '${Endpoint}': $($_.Exception.Message)"
    }
}
