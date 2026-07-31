function Get-PfbWorkloadPlacementRecommendation {
    <#
    .SYNOPSIS
        Retrieves stored workload placement recommendations.
    .DESCRIPTION
        Returns previously generated placement recommendations. To compute new
        recommendations from a set of inputs, use New-PfbWorkloadPlacementRecommendation.
    .PARAMETER Name
        One or more recommendation names to retrieve.
    .PARAMETER Id
        One or more recommendation IDs to retrieve.
    .PARAMETER Filter
        Server-side filter expression.
    .PARAMETER Sort
        Sort field and direction.
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER Array
        FlashBlade connection.
    .EXAMPLE
        Get-PfbWorkloadPlacementRecommendation
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(ParameterSetName = 'ByName')]
        [string[]]$Name,

        [Parameter(ParameterSetName = 'ById')]
        [string[]]$Id,

        [Parameter()] [string]$Filter,
        [Parameter()] [string]$Sort,
        [Parameter()] [ValidateRange(1, 10000)] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters -Names $Name -Ids $Id

    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'workloads/placement-recommendations' -QueryParams $queryParams -AutoPaginate
}
