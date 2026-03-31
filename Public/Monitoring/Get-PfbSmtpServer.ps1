function Get-PfbSmtpServer {
    <#
    .SYNOPSIS
        Retrieves the SMTP server configuration from a FlashBlade array.
    .DESCRIPTION
        The Get-PfbSmtpServer cmdlet returns the SMTP server configuration from the connected
        Pure Storage FlashBlade. This is a singleton endpoint returning the mail relay settings.
        This cmdlet is an alias for Get-PfbSmtp using the newer API endpoint.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbSmtpServer

        Returns the SMTP server configuration for the connected FlashBlade.
    .EXAMPLE
        Get-PfbSmtpServer -Array $FlashBlade

        Returns the SMTP server configuration using a specific connection.
    .EXAMPLE
        (Get-PfbSmtpServer).relay_host

        Retrieves the configured SMTP relay host.
    #>
    [CmdletBinding()]
    param([Parameter()] [PSCustomObject]$Array)
    Assert-PfbConnection -Array ([ref]$Array)
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'smtp-servers'
}
