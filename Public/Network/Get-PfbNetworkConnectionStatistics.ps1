function Get-PfbNetworkConnectionStatistics {
    <#
    .SYNOPSIS
        Retrieves network connection statistics for FlashBlade network interfaces.
    .DESCRIPTION
        The Get-PfbNetworkConnectionStatistics cmdlet returns connection-level statistics
        for network interfaces on the connected Pure Storage FlashBlade. This includes
        counters for active connections, connection rates, and protocol-level statistics.
    .PARAMETER Name
        One or more interface names to retrieve statistics for.
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
        Get-PfbNetworkConnectionStatistics -Name "vip1"

        Retrieves connection statistics for the specified interface.
    .EXAMPLE
        Get-PfbNetworkConnectionStatistics -Filter "interface_type='vip'" -Sort "name" -Limit 10

        Retrieves connection statistics for up to 10 VIP interfaces sorted by name.
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)] [string[]]$Name,
        [Parameter()] [string]$Filter,
        [Parameter()] [string]$Sort,
        [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )
    begin {
        Assert-PfbConnection -Array ([ref]$Array)
        $allNames = [System.Collections.Generic.List[string]]::new()
    }
    process {
        if ($Name) { foreach ($n in $Name) { $allNames.Add($n) } }
    }
    end {
        $queryParams = @{}
        if ($allNames.Count -gt 0) { $queryParams['names']  = $allNames -join ',' }
        if ($Filter)               { $queryParams['filter'] = $Filter }
        if ($Sort)                 { $queryParams['sort']   = $Sort }
        if ($Limit -gt 0)         { $queryParams['limit']  = $Limit }
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'network-interfaces/network-connection-statistics' -QueryParams $queryParams -AutoPaginate
    }
}
