function Remove-PfbObjectStoreAccessPolicyRule {
    <#
    .SYNOPSIS
        Removes a rule from an object store access policy.
    .DESCRIPTION
        Deletes the specified rule from its parent access policy. The rule can
        be identified by its fully-qualified name or by the combination of
        policy name and rule name.
    .PARAMETER Name
        The fully-qualified name of the rule to remove (policy/rule format).
    .PARAMETER PolicyName
        The name of the access policy that contains the rule to remove.
        Used together with the API names parameter.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        Remove-PfbObjectStoreAccessPolicyRule -Name "full-access-policy/rule1"
        Removes the specified rule by its fully-qualified name.
    .EXAMPLE
        Remove-PfbObjectStoreAccessPolicyRule -PolicyName "readonly-policy" -Name "readonly-policy/rule1"
        Removes a rule using both policy and rule identifiers.
    .EXAMPLE
        Get-PfbObjectStoreAccessPolicyRule -PolicyName "temp-policy" |
            ForEach-Object { Remove-PfbObjectStoreAccessPolicyRule -Name $_.name }
        Removes all rules from the specified policy.
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

        if ($PSCmdlet.ShouldProcess($Name, 'Remove access policy rule')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'object-store-access-policies/rules' -QueryParams $queryParams
        }
    }
}
