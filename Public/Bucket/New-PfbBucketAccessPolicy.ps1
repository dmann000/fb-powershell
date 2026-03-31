function New-PfbBucketAccessPolicy {
    <#
    .SYNOPSIS
        Creates a new bucket access policy on the FlashBlade.
    .DESCRIPTION
        Associates an access policy with a bucket on the FlashBlade array.
        Bucket access policies provide S3-compatible bucket-level access
        controls. Both the bucket member name and the policy name are required.
    .PARAMETER MemberName
        The name of the bucket to associate the access policy with.
    .PARAMETER PolicyName
        The name of the access policy to attach to the bucket.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbBucketAccessPolicy -MemberName "mybucket" -PolicyName "read-only-policy"

        Associates the 'read-only-policy' access policy with 'mybucket'.
    .EXAMPLE
        New-PfbBucketAccessPolicy -MemberName "data-lake" -PolicyName "full-access"

        Associates the 'full-access' policy with the 'data-lake' bucket.
    .EXAMPLE
        New-PfbBucketAccessPolicy -MemberName "mybucket" -PolicyName "read-only-policy" -Confirm:$false

        Creates the association without confirmation.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$MemberName,

        [Parameter(Mandatory, Position = 1)]
        [string]$PolicyName,

        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{
        'member_names' = $MemberName
        'policy_names' = $PolicyName
    }

    if ($PSCmdlet.ShouldProcess("$MemberName / $PolicyName", 'Create bucket access policy association')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'buckets/bucket-access-policies' -QueryParams $queryParams
    }
}
