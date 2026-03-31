function Get-PfbArrayFactoryResetToken {
    <#
    .SYNOPSIS
        Retrieves the factory reset token from a FlashBlade array.
    .DESCRIPTION
        The Get-PfbArrayFactoryResetToken cmdlet returns the current factory reset token
        status from the connected Pure Storage FlashBlade. This is a singleton endpoint.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbArrayFactoryResetToken

        Returns the factory reset token status for the connected FlashBlade.
    .EXAMPLE
        Get-PfbArrayFactoryResetToken -Array $FlashBlade

        Returns the factory reset token using a specific connection.
    .EXAMPLE
        (Get-PfbArrayFactoryResetToken).token

        Retrieves the factory reset token value.
    #>
    [CmdletBinding()]
    param([Parameter()] [PSCustomObject]$Array)
    Assert-PfbConnection -Array ([ref]$Array)
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'arrays/factory-reset-token'
}
