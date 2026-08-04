function Get-PfbArrayConnectionPerformanceReplication {
    <#
    .SYNOPSIS
        Retrieves replication performance metrics for array connections from a FlashBlade.
    .DESCRIPTION
        The Get-PfbArrayConnectionPerformanceReplication cmdlet returns replication performance
        metrics per array connection, including bytes sent/received and throughput.

        An array connection has no name of its own -- the API resource carries only an id. Its
        human-readable identifier is the REMOTE array's name, so -RemoteName (aliased to -Name
        for compatibility) is how you select one by name.
    .PARAMETER RemoteName
        One or more REMOTE array names whose connection performance to retrieve. Aliased to -Name.
        Accepts pipeline input.
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
    .PARAMETER Type
        Restricts results to replication performance for a specific object type. Valid values
        are "all", "file-system", and "object-store".
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbArrayConnectionPerformanceReplication

        Retrieves current replication performance for all array connections.
    .EXAMPLE
        Get-PfbArrayConnectionPerformanceReplication -RemoteName "FB-B" -Resolution 86400000

        Retrieves daily replication performance for the specified remote array.
    .EXAMPLE
        Get-PfbArrayConnectionPerformanceReplication -StartTime 1609459200000 -EndTime 1609545600000

        Retrieves replication performance for a specific time range.
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [string[]]$RemoteName,

        [Parameter()] [string]$Filter, [Parameter()] [string]$Sort, [Parameter()] [int]$Limit,
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
        $allRemoteNames = [System.Collections.Generic.List[string]]::new()
    }

    process {
        if ($RemoteName) {
            foreach ($n in $RemoteName) {
                # No -Id parameter here either, so a piped object coerces into -RemoteName --
                # see Get-PfbArrayConnectionPath.ps1 for the binding-pass explanation.
                Assert-PfbRemoteNameNotCoerced -Value $n
                $allRemoteNames.Add($n)
            }
        }
    }

    end {
        $queryParams = @{}
        # No -Names argument, and remote_names assigned inline -- see Get-PfbArrayConnectionPath.ps1.
        Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters
        if ($allRemoteNames.Count) { $queryParams['remote_names'] = $allRemoteNames -join ',' }
        if ($StartTime) { $queryParams['start_time'] = $StartTime }
        if ($EndTime) { $queryParams['end_time'] = $EndTime }
        if ($Resolution) { $queryParams['resolution'] = $Resolution }
        if ($Type) { $queryParams['type'] = $Type }
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'array-connections/performance/replication' -QueryParams $queryParams -AutoPaginate
    }
}
