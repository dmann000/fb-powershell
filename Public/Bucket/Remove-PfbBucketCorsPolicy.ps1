function Remove-PfbBucketCorsPolicy {
    <#
    .SYNOPSIS
        Removes a bucket CORS policy association from the FlashBlade.
    .DESCRIPTION
        Deletes the association between a bucket and a cross-origin resource
        sharing (CORS) policy on the FlashBlade. This action is irreversible.
        Use -Confirm:$false to suppress the confirmation prompt in automation
        scenarios.
    .PARAMETER Name
        One or more fully-qualified bucket CORS policy names to remove.
    .PARAMETER BucketName
        One or more bucket names to remove the CORS policy from.
    .PARAMETER MemberId
        The ID of the bucket to remove the CORS policy from.
    .PARAMETER PolicyName
        The name of the CORS policy to detach from the bucket.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbBucketCorsPolicy -BucketName "mybucket" -PolicyName "allow-all-origins"

        Removes the CORS policy association from the specified bucket.
    .EXAMPLE
        Remove-PfbBucketCorsPolicy -MemberId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" -PolicyName "restricted-cors"

        Removes the CORS policy association by bucket ID.
    .EXAMPLE
        Remove-PfbBucketCorsPolicy -Name "mybucket/allow-all-origins" -Confirm:$false

        Removes the CORS policy association without confirmation.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$Name,

        [Parameter(ParameterSetName = 'ByBucketName', Mandatory, ValueFromPipelineByPropertyName)]
        [string[]]$BucketName,

        [Parameter(ParameterSetName = 'ByMemberId', Mandatory)]
        [string]$MemberId,

        [Parameter()]
        [string]$PolicyName,

        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $queryParams = @{}
        if ($Name)       { $queryParams['names']        = $Name -join ',' }
        if ($BucketName) { $queryParams['bucket_names'] = $BucketName -join ',' }
        if ($MemberId)   { $queryParams['member_ids']   = $MemberId }
        if ($PolicyName) { $queryParams['policy_names'] = $PolicyName }

        $target = if ($Name) { $Name -join ',' } elseif ($BucketName) { $BucketName -join ',' } else { $MemberId }
        if ($PolicyName) { $target = "$target / $PolicyName" }

        if ($PSCmdlet.ShouldProcess($target, 'Remove bucket CORS policy association')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'buckets/cross-origin-resource-sharing-policies' -QueryParams $queryParams
        }
    }
}
