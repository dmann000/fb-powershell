function Get-PfbArrayClientS3Performance {
    <#
    .SYNOPSIS
        Retrieves S3-specific client performance metrics from a FlashBlade array.
    .DESCRIPTION
        The Get-PfbArrayClientS3Performance cmdlet returns S3-specific client performance
        metrics from the connected Pure Storage FlashBlade, including per-operation latency
        and throughput statistics.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction (e.g., "time" or "time-").
    .PARAMETER Limit
        Maximum number of entries to return.
    .PARAMETER StartTime
        Start of the time range for historical data (epoch milliseconds).
    .PARAMETER EndTime
        End of the time range for historical data (epoch milliseconds).
    .PARAMETER Resolution
        Time resolution for data points in milliseconds (e.g., 30000, 86400000).
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbArrayClientS3Performance

        Retrieves current S3 client performance metrics.
    .EXAMPLE
        Get-PfbArrayClientS3Performance -Resolution 86400000

        Retrieves daily S3 client performance metrics.
    .EXAMPLE
        Get-PfbArrayClientS3Performance -StartTime 1609459200000 -EndTime 1609545600000

        Retrieves S3 client performance for a specific time range.
    #>
    [CmdletBinding()]
    param(
        [Parameter()] [string]$Filter, [Parameter()] [string]$Sort, [Parameter()] [int]$Limit,
        [Parameter()] [long]$StartTime,
        [Parameter()] [long]$EndTime,
        [Parameter()] [long]$Resolution,
        [Parameter()] [PSCustomObject]$Array
    )
    Assert-PfbConnection -Array ([ref]$Array)
    $queryParams = @{}
    if ($Filter) { $queryParams['filter'] = $Filter }
    if ($Sort) { $queryParams['sort'] = $Sort }
    if ($Limit -gt 0) { $queryParams['limit'] = $Limit }
    if ($StartTime) { $queryParams['start_time'] = $StartTime }
    if ($EndTime) { $queryParams['end_time'] = $EndTime }
    if ($Resolution) { $queryParams['resolution'] = $Resolution }
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'arrays/clients/s3-specific-performance' -QueryParams $queryParams -AutoPaginate
}
