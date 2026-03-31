function Remove-PfbBucketAccessPolicy {
    <#
    .SYNOPSIS
        Removes a bucket access policy association from the FlashBlade.
    .DESCRIPTION
        Deletes the association between a bucket and an access policy on the
        FlashBlade. Both the bucket member name and the policy name are required.
        This action is irreversible. Use -Confirm:$false to suppress the
        confirmation prompt in automation scenarios.
    .PARAMETER MemberName
        The name of the bucket to remove the access policy from.
    .PARAMETER PolicyName
        The name of the access policy to detach from the bucket.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbBucketAccessPolicy -MemberName "mybucket" -PolicyName "read-only-policy"

        Removes the 'read-only-policy' from 'mybucket'.
    .EXAMPLE
        Remove-PfbBucketAccessPolicy -MemberName "mybucket" -PolicyName "read-only-policy" -Confirm:$false

        Removes the association without confirmation.
    .EXAMPLE
        Remove-PfbBucketAccessPolicy -MemberName "data-lake" -PolicyName "full-access"

        Removes the 'full-access' policy association from the 'data-lake' bucket.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
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

    if ($PSCmdlet.ShouldProcess("$MemberName / $PolicyName", 'Remove bucket access policy association')) {
        Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'buckets/bucket-access-policies' -QueryParams $queryParams
    }
}
