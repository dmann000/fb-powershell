function New-PfbBucketCorsPolicy {
    <#
    .SYNOPSIS
        Creates a new bucket CORS policy on the FlashBlade.
    .DESCRIPTION
        Creates the cross-origin resource sharing (CORS) policy for one or more
        buckets on the FlashBlade array. CORS policies control which web origins
        are permitted to make cross-origin requests to the S3 bucket.

        NOTE: POST /buckets/cross-origin-resource-sharing-policies declares only
        'bucket_names', 'bucket_ids' (and 'context_names' from REST 2.17) as
        query parameters -- there is no 'names' and no 'policy_names' on this
        operation, because a bucket's CORS policy is identified by the bucket
        that owns it. The previous -MemberName / -PolicyName parameters wrote
        'member_names' and 'policy_names', neither of which this endpoint
        declares, so the array silently discarded both. Use
        New-PfbBucketCorsPolicyRule to add rules to the resulting policy.
    .PARAMETER BucketName
        One or more bucket names to create the CORS policy for. Sent as the
        'bucket_names' query parameter.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbBucketCorsPolicy -BucketName "mybucket"

        Creates the CORS policy for 'mybucket'.
    .EXAMPLE
        New-PfbBucketCorsPolicy -BucketName "web-assets","static-content"

        Creates the CORS policy for both buckets in one request.
    .EXAMPLE
        New-PfbBucketCorsPolicy -BucketName "mybucket" -Confirm:$false

        Creates the policy without confirmation.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$BucketName,

        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $queryParams = @{
            'bucket_names' = $BucketName -join ','
        }

        if ($PSCmdlet.ShouldProcess(($BucketName -join ','), 'Create bucket CORS policy')) {
            Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'buckets/cross-origin-resource-sharing-policies' -QueryParams $queryParams
        }
    }
}
