function Get-PfbNetworkConnectionStatistics {
    <#
    .SYNOPSIS
        Retrieves network connection statistics for FlashBlade network interfaces.
    .DESCRIPTION
        The Get-PfbNetworkConnectionStatistics cmdlet returns connection-level statistics
        for network interfaces on the connected Pure Storage FlashBlade. This includes
        counters for active connections, connection rates, and protocol-level statistics.
    .PARAMETER Filter
        A server-side filter expression.
    .PARAMETER Sort
        Sort field and direction.
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbNetworkConnectionStatistics

        Retrieves connection statistics for all network interfaces.
    .EXAMPLE
        Get-PfbNetworkConnectionStatistics -Filter "interface_type='vip'" -Sort "name" -Limit 10

        Retrieves connection statistics for up to 10 VIP interfaces sorted by name.
    #>
    [CmdletBinding()]
    param(
        [Parameter()] [string]$Filter,
        [Parameter()] [string]$Sort,
        [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )
    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }
    end {
        $queryParams = @{}
        Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'network-interfaces/network-connection-statistics' -QueryParams $queryParams -AutoPaginate
    }
}
