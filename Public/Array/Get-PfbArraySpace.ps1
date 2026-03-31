function Get-PfbArraySpace {
    <#
    .SYNOPSIS
        Retrieves FlashBlade array space utilization.
    .DESCRIPTION
        Returns storage space metrics including capacity, data reduction, and usage.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .PARAMETER Type
        Filter by space type (e.g., 'array', 'file-system', 'object-store').
    .EXAMPLE
        Get-PfbArraySpace
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [PSCustomObject]$Array,

        [Parameter()]
        [string]$Type
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    if ($Type) { $queryParams['type'] = $Type }

    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'arrays/space' -QueryParams $queryParams -AutoPaginate
}
