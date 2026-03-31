function Get-PfbSyslogServerSettings {
    <#
    .SYNOPSIS
        Retrieves syslog server settings from a FlashBlade array.
    .DESCRIPTION
        The Get-PfbSyslogServerSettings cmdlet returns the global syslog server settings
        from the connected Pure Storage FlashBlade. This is a singleton endpoint.
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
    param([Parameter()] [PSCustomObject]$Array)
    Assert-PfbConnection -Array ([ref]$Array)
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'syslog-servers/settings'
}
