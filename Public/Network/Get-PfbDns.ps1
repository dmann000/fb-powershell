function Get-PfbDns {
    <#
    .SYNOPSIS
        Retrieves FlashBlade DNS configuration.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction.
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        Get-PfbDns
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Filter,

        [Parameter()]
        [string]$Sort,

        [Parameter()]
        [int]$Limit,

        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)
    $queryParams = @{}
    Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'dns' -QueryParams $queryParams -AutoPaginate
}
