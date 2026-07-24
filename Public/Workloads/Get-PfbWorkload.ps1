function Get-PfbWorkload {
    <#
    .SYNOPSIS
        Retrieves FlashBlade workloads.
    .DESCRIPTION
        Returns one or more workloads from the FlashBlade. A workload is a managed grouping
        of storage resources instantiated from a workload preset (see Get-PfbPresetWorkload).
        Supports filter, sort, and pagination.
    .PARAMETER Name
        One or more workload names to retrieve.
    .PARAMETER Id
        One or more workload IDs to retrieve.
    .PARAMETER Filter
        Server-side filter expression.
    .PARAMETER Sort
        Sort field and direction.
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER Destroyed
        Include destroyed workloads.
    .PARAMETER Array
        FlashBlade connection.
    .EXAMPLE
        Get-PfbWorkload
    .EXAMPLE
        Get-PfbWorkload -Name 'analytics-prod'
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(ParameterSetName = 'ByName', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Name,

        [Parameter(ParameterSetName = 'ById')]
        [ValidateNotNullOrEmpty()]
        [string[]]$Id,

        [Parameter()] [string]$Filter,
        [Parameter()] [string]$Sort,
        [Parameter()] [ValidateRange(1, 10000)] [int]$Limit,
        [Parameter()] [switch]$Destroyed,
        [Parameter()] [PSCustomObject]$Array
    )

    begin { Assert-PfbConnection -Array ([ref]$Array) }

    process {
        $queryParams = @{}
        Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters -Names $Name -Ids $Id
        if ($Destroyed) { $queryParams['destroyed'] = 'true' }

        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'workloads' -QueryParams $queryParams -AutoPaginate
    }
}
