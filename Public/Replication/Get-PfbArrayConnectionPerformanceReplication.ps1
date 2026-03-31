function Get-PfbArrayConnectionPerformanceReplication {
    <#
    .SYNOPSIS
        Retrieves replication performance metrics for array connections from a FlashBlade.
    .DESCRIPTION
        The Get-PfbArrayConnectionPerformanceReplication cmdlet returns replication performance
        metrics per array connection, including bytes sent/received and throughput.
    .PARAMETER Name
        One or more connection names to retrieve performance for. Accepts pipeline input.
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
        Get-PfbArrayConnectionPerformanceReplication

        Retrieves current replication performance for all array connections.
    .EXAMPLE
        Get-PfbArrayConnectionPerformanceReplication -Name "remote-fb-dc2" -Resolution 86400000

        Retrieves daily replication performance for the specified connection.
    .EXAMPLE
        Get-PfbArrayConnectionPerformanceReplication -StartTime 1609459200000 -EndTime 1609545600000

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
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'array-connections/performance/replication' -QueryParams $queryParams -AutoPaginate
    }
}
