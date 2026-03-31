function New-PfbObjectStoreAccessPolicyRule {
    <#
    .SYNOPSIS
        Creates a new rule within an object store access policy.
    .DESCRIPTION
        Adds a rule to an existing access policy. Each rule defines an effect
        (allow or deny), a set of actions, and optional resource and condition
        constraints.
    .PARAMETER PolicyName
        The name of the access policy to which the rule will be added.
    .PARAMETER Attributes
        A hashtable of rule properties including effect, actions, resources,
        and conditions.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        New-PfbObjectStoreAccessPolicyRule -PolicyName "full-access-policy" -Attributes @{
            effect  = "allow"
            actions = @("s3:GetObject", "s3:PutObject")
            resources = @("*")
        }
        Creates a rule allowing get and put operations on all resources.
    .EXAMPLE
        New-PfbObjectStoreAccessPolicyRule -PolicyName "readonly-policy" -Attributes @{
            effect  = "allow"
            actions = @("s3:GetObject", "s3:ListBucket")
        }
        Creates a read-only rule in the specified policy.
    .EXAMPLE
        New-PfbObjectStoreAccessPolicyRule -PolicyName "deny-delete-policy" -Attributes @{
            effect  = "deny"
            actions = @("s3:DeleteObject")
            resources = @("*")
        }
        Creates a rule that explicitly denies delete operations.
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

    if ($PSCmdlet.ShouldProcess($PolicyName, 'Create access policy rule')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'object-store-access-policies/rules' -Body $body -QueryParams $queryParams
    }
}
