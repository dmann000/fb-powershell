function New-PfbBucketCorsPolicy {
    <#
    .SYNOPSIS
        Creates a new bucket CORS policy association on the FlashBlade.
    .DESCRIPTION
        Associates a cross-origin resource sharing (CORS) policy with a bucket
        on the FlashBlade array. CORS policies control which web origins are
        permitted to make cross-origin requests to the S3 bucket.
    .PARAMETER MemberName
        The name of the bucket to associate the CORS policy with.
    .PARAMETER PolicyName
        The name of the CORS policy to attach to the bucket.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbBucketCorsPolicy -MemberName "mybucket" -PolicyName "allow-all-origins"

        Associates the 'allow-all-origins' CORS policy with 'mybucket'.
    .EXAMPLE
        New-PfbBucketCorsPolicy -MemberName "web-assets" -PolicyName "restricted-cors"

        Associates the 'restricted-cors' policy with the 'web-assets' bucket.
    .EXAMPLE
        New-PfbBucketCorsPolicy -MemberName "mybucket" -PolicyName "allow-all-origins" -Confirm:$false

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

    if ($PSCmdlet.ShouldProcess("$MemberName / $PolicyName", 'Create bucket CORS policy association')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'buckets/cross-origin-resource-sharing-policies' -QueryParams $queryParams
    }
}
