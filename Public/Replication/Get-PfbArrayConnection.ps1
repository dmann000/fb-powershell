function Get-PfbArrayConnection {
    <#
    .SYNOPSIS
        Retrieves FlashBlade array connections (replication links between arrays).
    .DESCRIPTION
        The Get-PfbArrayConnection cmdlet returns array connection configurations from the
        connected Everpure FlashBlade. Array connections define replication links between
        FlashBlade arrays and are required for file system and bucket replication. Supports
        pipeline input, server-side filtering, and automatic pagination.

        An array connection has no name of its own -- the API resource carries only an id. Its
        human-readable identifier is the REMOTE array's name, so -RemoteName (aliased to -Name
        for compatibility) is how you select one by name.
    .PARAMETER RemoteName
        One or more REMOTE array names whose connections to retrieve. Aliased to -Name. Accepts
        pipeline input.
    .PARAMETER Id
        One or more array connection IDs to retrieve. Accepts pipeline input by property name.
    .PARAMETER Filter
        A server-side filter expression to narrow results (e.g., "status='connected'").
    .PARAMETER Sort
        Sort field and direction (e.g., "id" or "id-"). An array connection has no name field, so
        "name" cannot sort it. The API publishes no enum of sortable fields -- use a field the
        resource actually has, such as "id", "status" or "type".
    .PARAMETER Limit
        Maximum number of array connection entries to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbArrayConnection

        Retrieves all array connections from the connected FlashBlade.
    .EXAMPLE
        Get-PfbArrayConnection -RemoteName "FB-B"

        Retrieves the connection to the remote array named "FB-B".
    .EXAMPLE
        Get-PfbArrayConnection | Where-Object type -eq 'async-replication'

        Retrieves only the asynchronous replication connections, excluding the
        system-managed fleet-management ones.
    .EXAMPLE
        Get-PfbArrayConnection -Filter "status='connected'" -Sort "id" -Limit 10

        Retrieves up to 10 connected array connections sorted by id.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(ParameterSetName = 'ByRemoteName', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [string[]]$RemoteName,

        [Parameter(ParameterSetName = 'ById', ValueFromPipelineByPropertyName)] [string[]]$Id,
        [Parameter()] [string]$Filter, [Parameter()] [string]$Sort, [Parameter()] [int]$Limit,
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
                Assert-PfbRemoteNameNotCoerced -Value $n
                $allRemoteNames.Add($n)
            }
        }
        if ($Id) { foreach ($i in $Id) { $allIds.Add($i) } }
    }

    end {
        $queryParams = @{}
        # remote_names is assigned inline rather than added to Add-PfbCommonQueryParams: it is a
        # replication-family filter on 11 endpoints, not one of the ~148-endpoint common keys the
        # helper centralizes, and the five other cmdlets in this module that emit it all do it
        # inline too (issue #64). The comma-join is what the helper used to provide.
        Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters -Ids $allIds
        if ($allRemoteNames.Count) { $queryParams['remote_names'] = $allRemoteNames -join ',' }
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'array-connections' -QueryParams $queryParams -AutoPaginate
    }
}
