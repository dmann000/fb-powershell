function Remove-PfbBucketCorsPolicy {
    <#
    .SYNOPSIS
        Removes a bucket CORS policy association from the FlashBlade.
    .DESCRIPTION
        Deletes the association between a bucket and a cross-origin resource
        sharing (CORS) policy on the FlashBlade. This action is irreversible.
        Use -Confirm:$false to suppress the confirmation prompt in automation
        scenarios.

        NOTE: DELETE /buckets/cross-origin-resource-sharing-policies declares
        only 'names', 'bucket_names' and 'bucket_ids'. There is no policy-level
        selector, so -BucketName and -BucketId delete EVERY CORS policy
        association on the specified bucket(s). Use the fully-qualified -Name
        to remove a single association.
    .PARAMETER Name
        One or more fully-qualified bucket CORS policy names to remove. This is
        the only way to target a single association.
    .PARAMETER BucketName
        One or more bucket names. Removes all CORS policy associations on those
        buckets.
    .PARAMETER BucketId
        One or more bucket IDs. Removes all CORS policy associations on those
        buckets.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbBucketCorsPolicy -Name "mybucket/allow-all-origins"

        Removes the single CORS policy association 'allow-all-origins' from 'mybucket'.
    .EXAMPLE
        Remove-PfbBucketCorsPolicy -BucketName "mybucket"

        Removes ALL CORS policy associations from the bucket named 'mybucket'.
    .EXAMPLE
        Remove-PfbBucketCorsPolicy -Name "mybucket/allow-all-origins" -Confirm:$false

        Removes the CORS policy association without confirmation.
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
            $target = "CORS policy association(s) $($Name -join ',')"
        }
        elseif ($BucketName) {
            $target = "ALL CORS policy associations on bucket(s) $($BucketName -join ',')"
        }
        else {
            $target = "ALL CORS policy associations on bucket ID(s) $($BucketId -join ',')"
        }

        if ($PSCmdlet.ShouldProcess($target, 'Remove bucket CORS policy association')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'buckets/cross-origin-resource-sharing-policies' -QueryParams $queryParams
        }
    }
}
