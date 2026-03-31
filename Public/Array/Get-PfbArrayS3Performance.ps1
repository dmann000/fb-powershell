function Get-PfbArrayS3Performance {
    <#
    .SYNOPSIS
        Retrieves S3-specific performance metrics from the FlashBlade.
    .DESCRIPTION
        Returns S3 protocol-specific performance counters for the array
        including per-operation latency, IOPS, and throughput for S3 operations.
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
        Get-PfbArrayS3Performance
        Returns current S3-specific performance metrics.
    .EXAMPLE
        Get-PfbArrayS3Performance -Resolution 30000
        Returns S3 performance metrics at 30-second resolution.
    .EXAMPLE
        Get-PfbArrayS3Performance -StartTime 1609459200000 -EndTime 1609545600000
        Returns S3 performance metrics for a specific time range.
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

        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'arrays/s3-specific-performance' -QueryParams $queryParams -AutoPaginate
    }
}
