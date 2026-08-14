function Get-PfbArrayConnectionPath {
    <#
    .SYNOPSIS
        Retrieves array connection path information from a FlashBlade array.
    .DESCRIPTION
        The Get-PfbArrayConnectionPath cmdlet returns network path information for array
        connections on the connected Everpure FlashBlade.

        An array connection has no name of its own -- the API resource carries only an id. Its
        human-readable identifier is the REMOTE array's name, so -RemoteName (aliased to -Name
        for compatibility) is how you select one by name.
    .PARAMETER RemoteName
        One or more REMOTE array names whose connection paths to retrieve. Aliased to -Name.
        Accepts pipeline input.
    .PARAMETER Id
        One or more array connection IDs whose paths to retrieve. Accepts pipeline input by
        property name. Legal on its own and alongside -RemoteId.
    .PARAMETER RemoteId
        One or more REMOTE array IDs whose connection paths to retrieve. A selector in its own
        right, and combinable with -Id. Mutually exclusive with -RemoteName: the API declares
        remote_names and remote_ids as alternative ways to name the same remote dimension.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction (e.g., "id" or "id-"). An array connection path has no name
        field, so "name" cannot sort it. The API publishes no enum of sortable fields -- use a
        field the resource actually has, such as "id", "status" or "type".
    .PARAMETER Limit
        Maximum number of entries to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbArrayConnectionPath

        Retrieves all array connection paths from the connected FlashBlade.
    .EXAMPLE
        Get-PfbArrayConnectionPath -RemoteName "FB-B"

        Retrieves connection paths for the specified remote array.
    .EXAMPLE
        Get-PfbArrayConnectionPath -RemoteId "10314f42-020d-7080-8013-000133810cd0"

        Retrieves connection paths for the remote array with the specified remote array ID.
    .EXAMPLE
        Get-PfbArrayConnectionPath -Limit 10

        Retrieves up to 10 array connection paths.
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
                # A piped object that binds to neither -Id nor a name property falls through
                # PowerShell's ByValue-with-coercion pass and gets ToString()-ed into
                # -RemoteName (issue #64 follow-up). Fail here with an actionable message rather
                # than sending remote_names=@{...} and letting the array reject it.
                Assert-PfbRemoteNameNotCoerced -Value $n
                $allRemoteNames.Add($n)
            }
        }
        if ($Id) { foreach ($i in $Id) { $allIds.Add($i) } }
    }

    end {
        $queryParams = @{}
        # No -Names argument: GET /array-connections/path documents no names parameter in any
        # spec version, and an unrecognised key is silently ignored rather than rejected, so the
        # old call returned every path unfiltered (issue #64). remote_names and remote_ids are
        # assigned inline for the reason given in Get-PfbArrayConnection.ps1.
        Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters -Ids $allIds
        if ($allRemoteNames.Count) { $queryParams['remote_names'] = $allRemoteNames -join ',' }
        if ($RemoteId) { $queryParams['remote_ids'] = $RemoteId -join ',' }
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'array-connections/path' -QueryParams $queryParams -AutoPaginate
    }
}
