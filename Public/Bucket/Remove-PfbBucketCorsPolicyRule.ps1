function Remove-PfbBucketCorsPolicyRule {
    <#
    .SYNOPSIS
        Removes a bucket CORS policy rule from the FlashBlade.
    .DESCRIPTION
        Deletes a rule from a cross-origin resource sharing (CORS) policy
        identified by rule name. This action is irreversible. Use -Confirm:$false
        to suppress the confirmation prompt in automation scenarios.
    .PARAMETER Name
        The name of the CORS policy rule to remove.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbBucketCorsPolicyRule -Name "allow-all-origins.1"

        Removes the CORS policy rule by name.
    .EXAMPLE
        Remove-PfbBucketCorsPolicyRule -Name "allow-all-origins.1" -Confirm:$false

        Removes the CORS policy rule without confirmation.
    .EXAMPLE
        "cors-policy.1", "cors-policy.2" | Remove-PfbBucketCorsPolicyRule

        Removes multiple CORS policy rules using pipeline input.
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

        if ($PSCmdlet.ShouldProcess($Name, 'Remove bucket CORS policy rule')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'buckets/cross-origin-resource-sharing-policies/rules' -QueryParams $queryParams
        }
    }
}
