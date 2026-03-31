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
    #>
    [CmdletBinding()]
    param(
        [Parameter()] [string[]]$LocalBucketName,
        [Parameter()] [string[]]$RemoteBucketName,
        [Parameter()] [string]$Filter, [Parameter()] [string]$Sort, [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )
    Assert-PfbConnection -Array ([ref]$Array)
    $queryParams = @{}
    if ($LocalBucketName)  { $queryParams['local_bucket_names']  = $LocalBucketName -join ',' }
    if ($RemoteBucketName) { $queryParams['remote_bucket_names'] = $RemoteBucketName -join ',' }
    if ($Filter) { $queryParams['filter'] = $Filter }
    if ($Sort) { $queryParams['sort'] = $Sort }
    if ($Limit -gt 0) { $queryParams['limit'] = $Limit }
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'bucket-replica-links' -QueryParams $queryParams -AutoPaginate
}
