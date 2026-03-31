function Get-PfbSmtp {
    <#
    .SYNOPSIS
        Retrieves the SMTP configuration from a Pure Storage FlashBlade.
    .DESCRIPTION
        The Get-PfbSmtp cmdlet returns the current SMTP relay and sender domain configuration
        on the FlashBlade. This configuration controls how the FlashBlade sends email alerts
        and notifications. Uses API version 1.12.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbSmtp

        Returns the SMTP configuration for the connected FlashBlade.
    .EXAMPLE
        Get-PfbSmtp -Array $FlashBlade

        Returns the SMTP configuration using a specific FlashBlade connection object.
    .EXAMPLE
        $smtp = Get-PfbSmtp; $smtp.relay_host

        Retrieves the SMTP configuration and displays the configured relay host.
    #>
    [CmdletBinding()]
    param([Parameter()] [PSCustomObject]$Array)
    Assert-PfbConnection -Array ([ref]$Array)
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'smtp' -AutoPaginate -ApiVersionOverride '1.12'
}
