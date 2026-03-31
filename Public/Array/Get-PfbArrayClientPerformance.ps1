function Get-PfbArrayClientPerformance {
    <#
    .SYNOPSIS
        Retrieves per-client performance metrics from the FlashBlade.
    .DESCRIPTION
        Returns performance counters broken down by client, including IOPS,
        throughput, and latency for each client connected to the array.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction (e.g. 'time' or 'time-').
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER StartTime
        Start of the time range for historical data (epoch milliseconds or datetime string).
    .PARAMETER EndTime
        End of the time range for historical data (epoch milliseconds or datetime string).
    .PARAMETER Resolution
        Time resolution for data points in milliseconds (e.g. 30000, 86400000).
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbArrayClientPerformance
        Returns current per-client performance metrics.
    .EXAMPLE
        Get-PfbArrayClientPerformance -Limit 10 -Sort 'bytes_per_op-'
        Returns the top 10 clients sorted by bytes per operation descending.
    .EXAMPLE
        Get-PfbArrayClientPerformance -Filter "name='10.0.0.1'"
        Returns performance metrics for a specific client IP.
    #>
    [CmdletBinding()]
    param(
        [Parameter()] [string]$Filter,
        [Parameter()] [string]$Sort,
        [Parameter()] [int]$Limit,
        [Parameter()] [long]$StartTime,
        [Parameter()] [long]$EndTime,
        [Parameter()] [long]$Resolution,
        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $queryParams = @{}
        if ($Filter)       { $queryParams['filter']     = $Filter }
        if ($Sort)         { $queryParams['sort']       = $Sort }
        if ($Limit -gt 0)  { $queryParams['limit']      = $Limit }
        if ($StartTime)    { $queryParams['start_time'] = $StartTime }
        if ($EndTime)      { $queryParams['end_time']   = $EndTime }
        if ($Resolution)   { $queryParams['resolution'] = $Resolution }

        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'arrays/clients/performance' -QueryParams $queryParams -AutoPaginate
    }
}
