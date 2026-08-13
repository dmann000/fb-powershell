function Get-PfbPolicyFileSystemReplicaLink {
    <#
    .SYNOPSIS
        Retrieves policy file system replica link associations from a FlashBlade array.
    .DESCRIPTION
        The Get-PfbPolicyFileSystemReplicaLink cmdlet returns the cross-reference between
        policies and file system replica links on the connected Pure Storage FlashBlade.

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
    .PARAMETER Limit
        Maximum number of entries to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbPolicyFileSystemReplicaLink

        Retrieves all policy file system replica link associations.
    .EXAMPLE
        Get-PfbPolicyFileSystemReplicaLink -PolicyName "daily-snap"

        Retrieves replica link associations for the specified policy.
    .EXAMPLE
        Get-PfbPolicyFileSystemReplicaLink -Limit 10

        Retrieves up to 10 policy replica link associations.
    .EXAMPLE
        Get-PfbPolicyFileSystemReplicaLink -PolicyName "daily-snap" -RemoteName "remote-fb"

        Queries the 'daily-snap' associations with remote_names=remote-fb.
    #>
    [CmdletBinding()]
    param(
        [Parameter()] [string[]]$PolicyName,
        [Parameter()] [string[]]$PolicyId,
        [Parameter()] [string[]]$MemberId,
        [Parameter()] [ValidateNotNullOrEmpty()] [string[]]$RemoteName,
        [Parameter()] [ValidateNotNullOrEmpty()] [string[]]$RemoteId,
        [Parameter()] [string]$Filter, [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )

    if ($PSBoundParameters.ContainsKey('RemoteName') -and $PSBoundParameters.ContainsKey('RemoteId')) {
        throw '-RemoteName and -RemoteId cannot be used together: remote_names and remote_ids are mutually exclusive.'
    }

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters
    if ($PolicyName) { $queryParams['policy_names'] = $PolicyName -join ',' }
    if ($PolicyId) { $queryParams['policy_ids'] = $PolicyId -join ',' }
    if ($MemberId) { $queryParams['member_ids'] = $MemberId -join ',' }
    # remote_names and remote_ids are assigned inline rather than through
    # Add-PfbCommonQueryParams: they are replication-family keys, not common ones.
    if ($RemoteName) { $queryParams['remote_names'] = $RemoteName -join ',' }
    if ($RemoteId) { $queryParams['remote_ids'] = $RemoteId -join ',' }

    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'policies/file-system-replica-links' -QueryParams $queryParams -AutoPaginate
}
