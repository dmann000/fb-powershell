function Get-PfbBucketReplicaLink {
    <#
    .SYNOPSIS
        Retrieves FlashBlade bucket replica links.
    .DESCRIPTION
        The Get-PfbBucketReplicaLink cmdlet returns bucket replica link information from the
        connected Pure Storage FlashBlade. Bucket replica links represent active S3 bucket
        replication relationships between local and remote arrays. Results can be filtered by
        local or remote bucket name, or by a server-side filter expression.
    .PARAMETER LocalBucketName
        One or more local bucket names to filter replica links by.
    .PARAMETER RemoteBucketName
        One or more remote bucket names to filter replica links by.
    .PARAMETER Id
        One or more bucket replica link IDs to retrieve. A selector in its own right, and
        combinable with either remote-array selector.
    .PARAMETER RemoteName
        One or more REMOTE ARRAY names whose replica links to retrieve. Distinct from
        -RemoteBucketName, which filters on the remote BUCKET. Mutually exclusive with
        -RemoteId: the API declares remote_names and remote_ids as alternative ways to name
        the same remote dimension.
    .PARAMETER RemoteId
        One or more REMOTE ARRAY IDs whose replica links to retrieve. Mutually exclusive with
        -RemoteName.
    .PARAMETER Filter
        A server-side filter expression to narrow results (e.g., "status='replicating'").
    .PARAMETER Sort
        Sort field and direction (e.g., "direction" or "direction-").
    .PARAMETER Limit
        Maximum number of bucket replica link entries to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbBucketReplicaLink

        Retrieves all bucket replica links from the connected FlashBlade.
    .EXAMPLE
        Get-PfbBucketReplicaLink -LocalBucketName "s3-backup"

        Retrieves replica links for the local bucket named "s3-backup".
    .EXAMPLE
        Get-PfbBucketReplicaLink -RemoteBucketName "s3-archive-dr" -Limit 5

        Retrieves up to 5 replica links targeting the remote bucket "s3-archive-dr".
    .EXAMPLE
        Get-PfbBucketReplicaLink -RemoteId "10314f42-020d-7080-8013-000133810cd0"

        Retrieves the replica links pointing at the remote array with that ID.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter()] [string[]]$LocalBucketName,
        [Parameter()] [string[]]$RemoteBucketName,

        # -Id is declared in all three sets so it binds on its own (resolving to the default
        # List set) and composes with either remote-array selector. Of the keys this cmdlet
        # emits, remote_names + remote_ids is the only combination the spec forbids ("This
        # cannot be provided together with the `remote_ids` query parameter"), so only those
        # two occupy exclusive sets.
        [Parameter(ParameterSetName = 'List')]
        [Parameter(ParameterSetName = 'ByRemoteName')]
        [Parameter(ParameterSetName = 'ByRemoteId')]
        [string[]]$Id,

        [Parameter(ParameterSetName = 'ByRemoteName')]
        [string[]]$RemoteName,

        [Parameter(ParameterSetName = 'ByRemoteId')]
        [string[]]$RemoteId,

        [Parameter()] [string]$Filter, [Parameter()] [string]$Sort, [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )
    Assert-PfbConnection -Array ([ref]$Array)
    $queryParams = @{}
    # remote_names and remote_ids are assigned inline rather than added to
    # Add-PfbCommonQueryParams: they are replication-family filters on 11 endpoints, not among
    # the ~148-endpoint common keys the helper centralizes, and every other cmdlet in this
    # module that emits them does it inline too (issue #64). The comma-join is what the helper
    # provides for ids.
    Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters -Ids $Id
    if ($LocalBucketName)  { $queryParams['local_bucket_names']  = $LocalBucketName -join ',' }
    if ($RemoteBucketName) { $queryParams['remote_bucket_names'] = $RemoteBucketName -join ',' }
    if ($RemoteName) { $queryParams['remote_names'] = $RemoteName -join ',' }
    if ($RemoteId)   { $queryParams['remote_ids']   = $RemoteId   -join ',' }
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'bucket-replica-links' -QueryParams $queryParams -AutoPaginate
}
