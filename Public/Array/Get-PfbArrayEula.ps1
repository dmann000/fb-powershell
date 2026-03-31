function Get-PfbArrayEula {
    <#
    .SYNOPSIS
        Retrieves the EULA status from a FlashBlade array.
    .DESCRIPTION
        The Get-PfbArrayEula cmdlet returns the current End User License Agreement acceptance
        status from the connected Pure Storage FlashBlade. This is a singleton endpoint.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbArrayEula

        Returns the EULA status for the connected FlashBlade.
    .EXAMPLE
        Get-PfbArrayEula -Array $FlashBlade

        Returns the EULA status using a specific FlashBlade connection.
    .EXAMPLE
        (Get-PfbArrayEula).accepted

        Retrieves the EULA status and displays whether it has been accepted.
    #>
    [CmdletBinding()]
    param([Parameter()] [PSCustomObject]$Array)
    Assert-PfbConnection -Array ([ref]$Array)
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'arrays/eula'
}
