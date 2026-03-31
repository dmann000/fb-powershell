function Get-PfbFileSystemUserPerformance {
    <#
    .SYNOPSIS
        Retrieves user-level performance data for file systems on the FlashBlade.
    .DESCRIPTION
        Returns per-user performance metrics for file systems, including IOPS,
        throughput, and latency. Supports time-range queries for historical data
        and resolution-based aggregation.
    .PARAMETER Name
        One or more file system names to retrieve user performance for. Accepts pipeline input.
    .PARAMETER Id
        One or more file system IDs to retrieve user performance for.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction.
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER TotalOnly
        Return only the total count, not the items.
    .PARAMETER StartTime
        Start of the time range in milliseconds since epoch.
    .PARAMETER EndTime
        End of the time range in milliseconds since epoch.
    .PARAMETER Resolution
        Time resolution in milliseconds for data aggregation.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        Get-PfbFileSystemUserPerformance
        Returns user performance data for all file systems.
    .EXAMPLE
        Get-PfbFileSystemUserPerformance -Name "fs01" -StartTime 1700000000000 -EndTime 1700086400000
        Returns user performance data for 'fs01' within the specified time range.
    .EXAMPLE
        Get-PfbFileSystemUserPerformance -Resolution 86400000 -Limit 100
        Returns daily-aggregated user performance data, limited to 100 records.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByName')]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByName', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ById')]
        [ValidateNotNullOrEmpty()]
        [string[]]$Id,

        [Parameter()]
        [string]$Filter,

        [Parameter()]
        [string]$Sort,

        [Parameter()]
        [ValidateRange(1, 10000)]
        [int]$Limit,

        [Parameter()]
        [switch]$TotalOnly,

        [Parameter()]
        [long]$StartTime,

        [Parameter()]
        [long]$EndTime,

        [Parameter()]
        [long]$Resolution,

        [Parameter()]
        [PSCustomObject]$Array
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
        if ($allNames.Count -gt 0) { $queryParams['file_system_names'] = $allNames -join ',' }
        if ($allIds.Count -gt 0)   { $queryParams['file_system_ids']  = $allIds -join ',' }
        if ($Filter)               { $queryParams['filter']     = $Filter }
        if ($Sort)                 { $queryParams['sort']       = $Sort }
        if ($Limit -gt 0)         { $queryParams['limit']      = $Limit }
        if ($TotalOnly)            { $queryParams['total_only'] = 'true' }
        if ($StartTime -gt 0)     { $queryParams['start_time'] = $StartTime }
        if ($EndTime -gt 0)       { $queryParams['end_time']   = $EndTime }
        if ($Resolution -gt 0)    { $queryParams['resolution'] = $Resolution }

        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'file-systems/users/performance' -QueryParams $queryParams -AutoPaginate
    }
}
