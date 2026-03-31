function Get-PfbTargetPerformanceReplication {
    <#
    .SYNOPSIS
        Retrieves target replication performance metrics from a FlashBlade array.
    .DESCRIPTION
        The Get-PfbTargetPerformanceReplication cmdlet returns replication performance metrics
        for targets on the connected Pure Storage FlashBlade, including bytes sent/received,
        throughput, and latency. Supports time-range queries and resolution settings.
    .PARAMETER Name
        One or more target names to retrieve performance data for. Accepts pipeline input.
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
        Get-PfbTargetPerformanceReplication

        Retrieves current replication performance metrics for all targets.
    .EXAMPLE
        Get-PfbTargetPerformanceReplication -Name "s3-target-aws" -Resolution 86400000

        Retrieves daily replication performance for the specified target.
    .EXAMPLE
        Get-PfbTargetPerformanceReplication -StartTime 1609459200000 -EndTime 1609545600000

        Retrieves replication performance for a specific time range.
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)] [string[]]$Name,
        [Parameter()] [string]$Filter, [Parameter()] [string]$Sort, [Parameter()] [int]$Limit,
        [Parameter()] [long]$StartTime,
        [Parameter()] [long]$EndTime,
        [Parameter()] [long]$Resolution,
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
        if ($allNames.Count -gt 0) { $queryParams['names'] = $allNames -join ',' }
        if ($Filter) { $queryParams['filter'] = $Filter }
        if ($Sort) { $queryParams['sort'] = $Sort }
        if ($Limit -gt 0) { $queryParams['limit'] = $Limit }
        if ($StartTime) { $queryParams['start_time'] = $StartTime }
        if ($EndTime) { $queryParams['end_time'] = $EndTime }
        if ($Resolution) { $queryParams['resolution'] = $Resolution }
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'targets/performance/replication' -QueryParams $queryParams -AutoPaginate
    }
}
