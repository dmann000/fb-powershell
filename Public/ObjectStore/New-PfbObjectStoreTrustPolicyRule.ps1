function New-PfbObjectStoreTrustPolicyRule {
    <#
    .SYNOPSIS
        Creates a new trust policy rule for an object store role.
    .DESCRIPTION
        Adds a rule to the trust policy of an object store role. Trust policy
        rules define which principals are permitted to assume the role and
        under what conditions.
    .PARAMETER PolicyName
        The name of the trust policy to which the rule will be added.
    .PARAMETER Attributes
        A hashtable of rule properties including effect, principals, actions,
        and conditions.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        New-PfbObjectStoreTrustPolicyRule -PolicyName "s3-admin-role/trust-policy" -Attributes @{
            effect     = "allow"
            principals = @("acct1/user1")
            actions    = @("sts:AssumeRole")
        }
        Creates a trust rule allowing a specific user to assume the role.
    .EXAMPLE
        New-PfbObjectStoreTrustPolicyRule -PolicyName "replication-role/trust-policy" -Attributes @{
            effect     = "allow"
            principals = @("*")
            actions    = @("sts:AssumeRole")
        }
        Creates a trust rule allowing any principal to assume the role.
    .EXAMPLE
        New-PfbObjectStoreTrustPolicyRule -PolicyName "analytics-role/trust-policy" -Attributes @{
            effect     = "allow"
            principals = @("acct1/analytics-user")
        }
        Creates a trust rule for an analytics user.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$PolicyName,

        [Parameter()]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $body = if ($Attributes) { $Attributes } else { @{} }
    $queryParams = @{ 'policy_names' = $PolicyName }

    if ($PSCmdlet.ShouldProcess($PolicyName, 'Create trust policy rule')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'object-store-roles/object-store-trust-policies/rules' -Body $body -QueryParams $queryParams
    }
}
