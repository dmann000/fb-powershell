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
    .PARAMETER Id
        One or more array connection IDs whose performance to retrieve. Accepts pipeline input by
        property name. Legal on its own and alongside -RemoteId.
    .PARAMETER RemoteId
        One or more REMOTE array IDs whose connection performance to retrieve. A selector in its
        own right, and combinable with -Id. Mutually exclusive with -RemoteName: the API declares
        remote_names and remote_ids as alternative ways to name the same remote dimension.
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
        Get-PfbArrayConnectionPerformanceReplication -RemoteId "10314f42-020d-7080-8013-000133810cd0"

        Retrieves replication performance for the remote array with the specified remote array ID.
    .EXAMPLE
        Get-PfbArrayConnectionPerformanceReplication -StartTime 1609459200000 -EndTime 1609545600000

        Retrieves replication performance for a specific time range.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(ParameterSetName = 'ByRemoteName', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [string[]]$RemoteName,

        [Parameter(ParameterSetName = 'ByRemoteId')]
        [string[]]$RemoteId,

        # Declared in all three sets -- see Get-PfbArrayConnection.ps1 for why.
        [Parameter(ParameterSetName = 'List', ValueFromPipelineByPropertyName)]
        [Parameter(ParameterSetName = 'ByRemoteName', ValueFromPipelineByPropertyName)]
        [Parameter(ParameterSetName = 'ByRemoteId', ValueFromPipelineByPropertyName)]
        [string[]]$Id,

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
        $allIds = [System.Collections.Generic.List[string]]::new()
    }

    process {
        if ($RemoteName) {
            foreach ($n in $RemoteName) {
                # A piped object that binds to neither -Id nor a name property still coerces into
                # -RemoteName -- see Get-PfbArrayConnectionPath.ps1 for the binding-pass explanation.
                Assert-PfbRemoteNameNotCoerced -Value $n
                $allRemoteNames.Add($n)
            }
        }
        if ($Id) { foreach ($i in $Id) { $allIds.Add($i) } }
    }

    end {
        $queryParams = @{}
        # No -Names argument, and remote_names/remote_ids assigned inline -- see
        # Get-PfbArrayConnectionPath.ps1.
        Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters -Ids $allIds
        if ($allRemoteNames.Count) { $queryParams['remote_names'] = $allRemoteNames -join ',' }
        if ($RemoteId) { $queryParams['remote_ids'] = $RemoteId -join ',' }
        if ($StartTime) { $queryParams['start_time'] = $StartTime }
        if ($EndTime) { $queryParams['end_time'] = $EndTime }
        if ($Resolution) { $queryParams['resolution'] = $Resolution }
        if ($Type) { $queryParams['type'] = $Type }
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'array-connections/performance/replication' -QueryParams $queryParams -AutoPaginate
    }
}
