function Remove-PfbBucketAccessPolicyRule {
    <#
    .SYNOPSIS
        Removes a bucket access policy rule from the FlashBlade.
    .DESCRIPTION
        Deletes a rule from a bucket access policy identified by rule name.
        This action is irreversible. Use -Confirm:$false to suppress the
        confirmation prompt in automation scenarios.
    .PARAMETER Name
        The name of the bucket access policy rule to remove.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbBucketAccessPolicyRule -Name "mybucket.read-only-policy.1"

        Removes the bucket access policy rule by name.
    .EXAMPLE
        Remove-PfbBucketAccessPolicyRule -Name "mybucket.read-only-policy.1" -Confirm:$false

        Removes the rule without confirmation.
    .EXAMPLE
        "mybucket.policy.1", "mybucket.policy.2" | Remove-PfbBucketAccessPolicyRule

        Removes multiple rules using pipeline input.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $queryParams = @{ 'names' = $Name }

        if ($PSCmdlet.ShouldProcess($Name, 'Remove bucket access policy rule')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'buckets/bucket-access-policies/rules' -QueryParams $queryParams
        }
    }
}
