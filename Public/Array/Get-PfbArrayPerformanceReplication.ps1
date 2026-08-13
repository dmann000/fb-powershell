function Get-PfbArrayPerformanceReplication {
    <#
    .SYNOPSIS
        Retrieves array replication performance metrics from the FlashBlade.
    .DESCRIPTION
        Returns replication-specific performance counters for the array including
        bytes sent/received, throughput, and latency for replication operations.
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
    .PARAMETER Type
        Restricts results to replication performance for a specific object type. Valid values
        are "all", "file-system", and "object-store".
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbArrayPerformanceReplication
        Returns current replication performance metrics.
    .EXAMPLE
        Get-PfbArrayPerformanceReplication -Resolution 86400000
        Returns daily replication performance metrics.
    .EXAMPLE
        Get-PfbArrayPerformanceReplication -StartTime 1609459200000 -EndTime 1609545600000
        Returns replication performance metrics for a specific time range.
    .NOTES
        <!-- PfbContext (generated; do not edit) -->
        Context requirement (GET /arrays/performance/replication): the context scope for this endpoint is not
        recorded in the capability map, so the module will not pre-validate a context
        for it. A fleet or array context may still be required by the array itself; if
        a call fails with a context error, set one with Set-PfbContext or scope the
        call with Invoke-PfbInContext.
        <!-- /PfbContext -->
    #>
    [CmdletBinding()]
    param(
        [Parameter()] [string]$Filter,
        [Parameter()] [string]$Sort,
        [Parameter()] [int]$Limit,
        [Parameter()] [long]$StartTime,
        [Parameter()] [long]$EndTime,
        [Parameter()] [long]$Resolution,
        [Parameter()]
        [ValidateSet('all', 'file-system', 'object-store')]
        [string]$Type,
        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $queryParams = @{}
        Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters
        if ($StartTime)    { $queryParams['start_time'] = $StartTime }
        if ($EndTime)      { $queryParams['end_time']   = $EndTime }
        if ($Resolution)   { $queryParams['resolution'] = $Resolution }
        if ($Type)         { $queryParams['type']       = $Type }

        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'arrays/performance/replication' -QueryParams $queryParams -AutoPaginate
    }
}
