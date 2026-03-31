function Get-PfbQuotaSettings {
    <#
    .SYNOPSIS
        Retrieves quota settings from a FlashBlade array.
    .DESCRIPTION
        The Get-PfbQuotaSettings cmdlet returns the global quota settings from the connected
        Pure Storage FlashBlade. This is a singleton endpoint that returns the array-wide
        quota configuration.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbQuotaSettings

        Returns the quota settings for the connected FlashBlade.
    .EXAMPLE
        Get-PfbQuotaSettings -Array $FlashBlade

        Returns the quota settings using a specific FlashBlade connection.
    .EXAMPLE
        (Get-PfbQuotaSettings).contact_info

        Retrieves the contact information from the quota settings.
    #>
    [CmdletBinding()]
    param([Parameter()] [PSCustomObject]$Array)
    Assert-PfbConnection -Array ([ref]$Array)
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'quotas/settings'
}
