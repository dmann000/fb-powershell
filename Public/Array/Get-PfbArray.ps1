function Get-PfbArray {
    <#
    .SYNOPSIS
        Retrieves FlashBlade array information.
    .DESCRIPTION
        Returns array attributes including name, OS version, model, and configuration.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction.
    .PARAMETER Limit
        Maximum number of items to return.
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
        [string]$Filter,

        [Parameter()]
        [string]$Sort,

        [Parameter()]
        [int]$Limit,

        [Parameter()]
        [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters

    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'arrays' -QueryParams $queryParams -AutoPaginate
}
