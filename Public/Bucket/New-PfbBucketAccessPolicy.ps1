function New-PfbBucketAccessPolicy {
    <#
    .SYNOPSIS
        Creates a new bucket access policy on the FlashBlade.
    .DESCRIPTION
        Creates the bucket access policy for one or more buckets on the
        FlashBlade array. Bucket access policies provide S3-compatible
        bucket-level access controls.

        NOTE: POST /buckets/bucket-access-policies declares only 'bucket_names',
        'bucket_ids' (and 'context_names' from REST 2.17) as query parameters --
        there is no 'names' and no 'policy_names' on this operation, because a
        bucket's access policy is identified by the bucket that owns it. The
        previous -MemberName / -PolicyName parameters wrote 'member_names' and
        'policy_names', neither of which this endpoint declares, so the array
        silently discarded both. Use Get-PfbBucketAccessPolicy to read the
        resulting policy, and New-PfbBucketAccessPolicyRule to add rules to it.
    .PARAMETER BucketName
        One or more bucket names to create the access policy for. Sent as the
        'bucket_names' query parameter.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbBucketAccessPolicy -BucketName "mybucket"

        Creates the bucket access policy for 'mybucket'.
    .EXAMPLE
        New-PfbBucketAccessPolicy -BucketName "data-lake","web-assets"

        Creates the bucket access policy for both buckets in one request.
    .EXAMPLE
        New-PfbBucketAccessPolicy -BucketName "mybucket" -Confirm:$false

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

        if ($PSCmdlet.ShouldProcess(($BucketName -join ','), 'Create bucket access policy')) {
            Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'buckets/bucket-access-policies' -QueryParams $queryParams
        }
    }
}
