function Get-PfbArray {
    <#
    .SYNOPSIS
        Retrieves FlashBlade array information.
    .DESCRIPTION
        Returns array attributes including name, OS version, model, and configuration.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        Get-PfbArray
    .EXAMPLE
        Get-PfbArray -Array $array
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'arrays' -AutoPaginate
}
