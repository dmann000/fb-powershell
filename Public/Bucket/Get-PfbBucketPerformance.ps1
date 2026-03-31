function Get-PfbBucketPerformance {
    <#
    .SYNOPSIS
        Retrieves bucket performance metrics from the FlashBlade.
    .DESCRIPTION
        Returns performance counters for buckets including IOPS, throughput,
        and latency. Can be filtered to specific buckets by name or ID.
    .PARAMETER Name
        One or more bucket names to retrieve performance for.
    .PARAMETER Id
        One or more bucket IDs to retrieve performance for.
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
    .PARAMETER TotalOnly
        If specified, returns only the aggregate total.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbBucketPerformance
        Returns performance metrics for all buckets.
    .EXAMPLE
        Get-PfbBucketPerformance -Name "my-bucket" -Resolution 30000
        Returns 30-second resolution performance data for 'my-bucket'.
    .EXAMPLE
        Get-PfbBucketPerformance -TotalOnly
        Returns only the aggregate performance total across all buckets.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(ParameterSetName = 'ByName', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$Name,

        [Parameter(ParameterSetName = 'ById')]
        [string[]]$Id,

        [Parameter()] [string]$Filter,
        [Parameter()] [string]$Sort,
        [Parameter()] [int]$Limit,
        [Parameter()] [long]$StartTime,
        [Parameter()] [long]$EndTime,
        [Parameter()] [long]$Resolution,
        [Parameter()] [switch]$TotalOnly,
        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
        $allNames = [System.Collections.Generic.List[string]]::new()
        $allIds = [System.Collections.Generic.List[string]]::new()
    }

    process {
        if ($Name) { foreach ($n in $Name) { $allNames.Add($n) } }
        if ($Id)   { foreach ($i in $Id)   { $allIds.Add($i) } }
    }

    end {
        $queryParams = @{}
        if ($allNames.Count -gt 0) { $queryParams['names']      = $allNames -join ',' }
        if ($allIds.Count -gt 0)   { $queryParams['ids']        = $allIds -join ',' }
        if ($Filter)               { $queryParams['filter']     = $Filter }
        if ($Sort)                 { $queryParams['sort']       = $Sort }
        if ($Limit -gt 0)          { $queryParams['limit']      = $Limit }
        if ($StartTime)            { $queryParams['start_time'] = $StartTime }
        if ($EndTime)              { $queryParams['end_time']   = $EndTime }
        if ($Resolution)           { $queryParams['resolution'] = $Resolution }
        if ($TotalOnly)            { $queryParams['total_only'] = 'true' }

        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'buckets/performance' -QueryParams $queryParams -AutoPaginate
    }
}
