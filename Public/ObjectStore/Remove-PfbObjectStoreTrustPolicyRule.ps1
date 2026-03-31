function Remove-PfbObjectStoreTrustPolicyRule {
    <#
    .SYNOPSIS
        Removes a trust policy rule from an object store role.
    .DESCRIPTION
        Deletes the specified trust policy rule. Removing all rules from a
        trust policy effectively prevents any principal from assuming the role.
    .PARAMETER Name
        The fully-qualified name of the trust policy rule to remove.
    .PARAMETER PolicyName
        The name of the trust policy that contains the rule.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        Remove-PfbObjectStoreTrustPolicyRule -Name "s3-admin-role/trust-policy/rule1"
        Removes the specified trust policy rule.
    .EXAMPLE
        Remove-PfbObjectStoreTrustPolicyRule -Name "replication-role/trust-policy/rule1" -PolicyName "replication-role/trust-policy"
        Removes a rule using both name and policy name.
    .EXAMPLE
        Get-PfbObjectStoreTrustPolicyRule -PolicyName "old-role/trust-policy" |
            ForEach-Object { Remove-PfbObjectStoreTrustPolicyRule -Name $_.name }
        Removes all trust policy rules from the specified policy.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter()]
        [string]$PolicyName,

        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $queryParams = @{ 'names' = $Name }
        if ($PolicyName) { $queryParams['policy_names'] = $PolicyName }

        if ($PSCmdlet.ShouldProcess($Name, 'Remove trust policy rule')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'object-store-roles/object-store-trust-policies/rules' -QueryParams $queryParams
        }
    }
}
