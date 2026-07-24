function Get-PfbDataEvictionPolicy {
    <#
    .SYNOPSIS
        Retrieves data eviction policies from the FlashBlade.
    .DESCRIPTION
        Data eviction policies control tiered-storage data movement off the array when
        the configured `keep_size` threshold is exceeded. Each policy can be attached to
        one or more file systems via Add-PfbDataEvictionPolicyFileSystem.
    .PARAMETER Name
        Policy name(s) to retrieve.
    .PARAMETER Id
        Policy ID(s) to retrieve.
    .PARAMETER Filter
        Server-side filter expression.
    .PARAMETER Sort
        Sort field and direction.
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER Array
        FlashBlade connection.
    .EXAMPLE
        Get-PfbDataEvictionPolicy
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(ParameterSetName = 'ByName', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$Name,

        [Parameter(ParameterSetName = 'ById')]
        [string[]]$Id,

        [Parameter()] [string]$Filter,
        [Parameter()] [string]$Sort,
        [Parameter()] [ValidateRange(1, 10000)] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )

    begin { Assert-PfbConnection -Array ([ref]$Array) }

    process {
        $queryParams = @{}
        Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters -Names $Name -Ids $Id

        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'data-eviction-policies' -QueryParams $queryParams -AutoPaginate
    }
}
