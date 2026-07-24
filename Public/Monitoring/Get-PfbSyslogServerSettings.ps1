function Get-PfbSyslogServerSettings {
    <#
    .SYNOPSIS
        Retrieves syslog server settings from a FlashBlade array.
    .DESCRIPTION
        The Get-PfbSyslogServerSettings cmdlet returns the global syslog server settings
        from the connected Pure Storage FlashBlade. This is a singleton endpoint.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction.
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbSyslogServerSettings

        Returns the syslog server settings for the connected FlashBlade.
    .EXAMPLE
        Get-PfbSyslogServerSettings -Array $FlashBlade

        Returns the syslog settings using a specific FlashBlade connection.
    .EXAMPLE
        (Get-PfbSyslogServerSettings).ca_certificate

        Retrieves the CA certificate from the syslog settings.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Filter,

        [Parameter()]
        [string]$Sort,

        [Parameter()]
        [ValidateRange(1, 10000)]
        [int]$Limit,

        [Parameter()]
        [PSCustomObject]$Array
    )
    Assert-PfbConnection -Array ([ref]$Array)
    $queryParams = @{}
    Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'syslog-servers/settings' -QueryParams $queryParams
}
