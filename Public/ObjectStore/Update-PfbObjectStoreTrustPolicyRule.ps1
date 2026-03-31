function Update-PfbObjectStoreTrustPolicyRule {
    <#
    .SYNOPSIS
        Updates an existing trust policy rule for an object store role.
    .DESCRIPTION
        Modifies the properties of a trust policy rule, such as its effect,
        principals, actions, or conditions.
    .PARAMETER Name
        The fully-qualified name of the trust policy rule to update.
    .PARAMETER Attributes
        A hashtable of rule properties to update.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        Update-PfbObjectStoreTrustPolicyRule -Name "s3-admin-role/trust-policy/rule1" -Attributes @{
            principals = @("acct1/user1", "acct1/user2")
        }
        Updates the principals allowed to assume the role.
    .EXAMPLE
        Update-PfbObjectStoreTrustPolicyRule -Name "replication-role/trust-policy/rule1" -Attributes @{
            effect = "deny"
        }
        Changes the rule effect to deny.
    .EXAMPLE
        Update-PfbObjectStoreTrustPolicyRule -Name "analytics-role/trust-policy/rule1" -Attributes @{
            actions = @("sts:AssumeRole", "sts:AssumeRoleWithWebIdentity")
        }
        Updates the allowed actions in the trust policy rule.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter()]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $body = if ($Attributes) { $Attributes } else { @{} }
        $queryParams = @{ 'names' = $Name }

        if ($PSCmdlet.ShouldProcess($Name, 'Update trust policy rule')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'object-store-roles/object-store-trust-policies/rules' -Body $body -QueryParams $queryParams
        }
    }
}
