function Remove-PfbBucketAccessPolicy {
    <#
    .SYNOPSIS
        Removes a bucket access policy from the FlashBlade.
    .DESCRIPTION
        Deletes a bucket access policy on the FlashBlade. This action is
        irreversible. Use -Confirm:$false to suppress the confirmation prompt in
        automation scenarios.

        NOTE: DELETE /buckets/bucket-access-policies declares only 'names',
        'bucket_names' and 'bucket_ids'. There is no policy-level selector, so
        -BucketName and -BucketId delete EVERY access policy on the specified
        bucket(s). Use the fully-qualified -Name to remove a single policy. The
        previous -MemberName / -PolicyName parameters wrote 'member_names' and
        'policy_names', neither of which this endpoint declares; behaviour when
        undeclared query keys are sent is undefined by the published API contract.
    .PARAMETER Name
        One or more fully-qualified bucket access policy names to remove. This is
        the only way to target a single policy.
    .PARAMETER BucketName
        One or more bucket names. Removes all access policies on those buckets.
    .PARAMETER BucketId
        One or more bucket IDs. Removes all access policies on those buckets.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbBucketAccessPolicy -Name "mybucket/myaccount:read-only-policy"

        Removes the single access policy 'read-only-policy' from 'mybucket'.
    .EXAMPLE
        Remove-PfbBucketAccessPolicy -BucketName "mybucket"

        Removes ALL access policies from the bucket named 'mybucket'.
    .EXAMPLE
        Remove-PfbBucketAccessPolicy -Name "mybucket/myaccount:read-only-policy" -Confirm:$false

        Removes the access policy without confirmation.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, ValueFromPipelineByPropertyName)]
        [string[]]$Name,

        [Parameter(ParameterSetName = 'ByBucketName', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$BucketName,

        [Parameter(ParameterSetName = 'ByBucketId', Mandatory)]
        [string[]]$BucketId,

        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $queryParams = @{}
        if ($Name)       { $queryParams['names']        = $Name -join ',' }
        if ($BucketName) { $queryParams['bucket_names'] = $BucketName -join ',' }
        if ($BucketId)   { $queryParams['bucket_ids']   = $BucketId -join ',' }

        if ($Name) {
            $target = "access policy/policies $($Name -join ',')"
        }
        elseif ($BucketName) {
            $target = "ALL access policies on bucket(s) $($BucketName -join ',')"
        }
        else {
            $target = "ALL access policies on bucket ID(s) $($BucketId -join ',')"
        }

        if ($PSCmdlet.ShouldProcess($target, 'Remove bucket access policy')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'buckets/bucket-access-policies' -QueryParams $queryParams
        }
    }
}
