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
        Legal on its own and alongside -RemoteId.
    .PARAMETER RemoteId
        One or more REMOTE array IDs whose connections to retrieve. A selector in its own right,
        and combinable with -Id. Mutually exclusive with -RemoteName: the API declares
        remote_names and remote_ids as alternative ways to name the same remote dimension.
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
        Get-PfbArrayConnection -RemoteId "10314f42-020d-7080-8013-000133810cd0"

        Retrieves the connection to the remote array with the specified remote array ID.
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

        [Parameter(ParameterSetName = 'ByRemoteId')]
        [string[]]$RemoteId,

        # -Id is declared in all three sets so it binds on its own (resolving to the default List
        # set), composes with either remote-dimension selector, and still absorbs a piped
        # connection object at binding pass 2. Of the keys these cmdlets emit, remote_names +
        # remote_ids is the only combination the spec forbids ("This cannot be provided together
        # with the `remote_ids` query parameter"), so only those two occupy exclusive sets. The
        # ids-versus-names exclusion the spec also declares cannot arise here: no
        # array-connection cmdlet emits a names key at all (issue #64).
        [Parameter(ParameterSetName = 'List', ValueFromPipelineByPropertyName)]
        [Parameter(ParameterSetName = 'ByRemoteName', ValueFromPipelineByPropertyName)]
        [Parameter(ParameterSetName = 'ByRemoteId', ValueFromPipelineByPropertyName)]
        [string[]]$Id,

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
        # remote_names and remote_ids are assigned inline rather than added to
        # Add-PfbCommonQueryParams: they are replication-family filters on 11 endpoints, not
        # among the ~148-endpoint common keys the helper centralizes, and the other cmdlets in
        # this module that emit them all do it inline too (issue #64). The comma-join is what the
        # helper used to provide.
        Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters -Ids $allIds
        if ($allRemoteNames.Count) { $queryParams['remote_names'] = $allRemoteNames -join ',' }
        if ($RemoteId) { $queryParams['remote_ids'] = $RemoteId -join ',' }
        if (Test-PfbEmptyPipelineRead -Caller $PSCmdlet -QueryParams $queryParams) { return }
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'array-connections' -QueryParams $queryParams -AutoPaginate
    }
}
