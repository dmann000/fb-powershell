function Get-PfbFileSystemReplicaLinkPolicy {
    <#
    .SYNOPSIS
        Retrieves policies associated with file system replica links on the FlashBlade.
    .DESCRIPTION
        Returns the mapping between file system replica links and their attached policies.
        Can be filtered by policy name/ID, member (replica link) ID, or the remote side of
        the link.

        This endpoint selects members by ID only: `member_ids` is a declared query
        parameter and `member_names` is not, so -MemberId is its only member filter.
    .PARAMETER PolicyName
        One or more policy names to filter by. Sent as `policy_names`.
    .PARAMETER PolicyId
        One or more policy IDs to filter by. Sent as `policy_ids`.
    .PARAMETER MemberId
        One or more replica link IDs to filter by. Sent as the declared `member_ids`
        query parameter.
    .PARAMETER RemoteName
        One or more REMOTE ARRAY names, sent as the declared `remote_names` query
        parameter. Mutually exclusive with -RemoteId: the API declares remote_names and
        remote_ids as alternative ways to name the same remote dimension.
    .PARAMETER RemoteId
        One or more REMOTE ARRAY IDs, sent as the declared `remote_ids` query parameter.
        Mutually exclusive with -RemoteName.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction.
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        Get-PfbFileSystemReplicaLinkPolicy
        Returns all replica-link-to-policy mappings.
    .EXAMPLE
        Get-PfbFileSystemReplicaLinkPolicy -MemberId "10314f42-020d-7080-8013-000133810cd0"
        Returns all policies attached to the replica link with that ID.
    .EXAMPLE
        Get-PfbFileSystemReplicaLinkPolicy -PolicyName "repl-daily" -RemoteName "remote-fb"
        Queries the 'repl-daily' attachments with remote_names=remote-fb.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter()] [string[]]$PolicyName,
        [Parameter()] [string[]]$PolicyId,
        [Parameter()] [string[]]$MemberId,
        [Parameter()] [ValidateNotNullOrEmpty()] [string[]]$RemoteName,
        [Parameter()] [ValidateNotNullOrEmpty()] [string[]]$RemoteId,
        [Parameter()] [string]$Filter,
        [Parameter()] [string]$Sort,
        [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        if ($PSBoundParameters.ContainsKey('RemoteName') -and $PSBoundParameters.ContainsKey('RemoteId')) {
            throw '-RemoteName and -RemoteId cannot be used together: remote_names and remote_ids are mutually exclusive.'
        }
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $queryParams = @{}
        Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters
        if ($PolicyName) { $queryParams['policy_names'] = $PolicyName -join ',' }
        if ($PolicyId)   { $queryParams['policy_ids']   = $PolicyId -join ',' }
        if ($MemberId)   { $queryParams['member_ids']    = $MemberId -join ',' }
        # remote_names and remote_ids are assigned inline rather than through
        # Add-PfbCommonQueryParams: they are replication-family keys, not common ones.
        if ($RemoteName) { $queryParams['remote_names']  = $RemoteName -join ',' }
        if ($RemoteId)   { $queryParams['remote_ids']    = $RemoteId -join ',' }

        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'file-system-replica-links/policies' -QueryParams $queryParams -AutoPaginate
    }
}
