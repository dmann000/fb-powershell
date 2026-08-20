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
    .PARAMETER Name
        The name of the rule to create. The REST endpoint requires a rule name,
        so this parameter is mandatory.
    .PARAMETER Attributes
        A hashtable of rule properties including effect, actions, resources,
        and conditions.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        New-PfbObjectStoreAccessPolicyRule -PolicyName "full-access-policy" -Name "get-put-all" -Attributes @{
            effect  = "allow"
            actions = @("s3:GetObject", "s3:PutObject")
            resources = @("*")
        }
        Creates a rule allowing get and put operations on all resources.
    .EXAMPLE
        New-PfbObjectStoreAccessPolicyRule -PolicyName "readonly-policy" -Name "read-only" -Attributes @{
            effect  = "allow"
            actions = @("s3:GetObject", "s3:ListBucket")
        }
        Creates a read-only rule in the specified policy.
    .EXAMPLE
        New-PfbObjectStoreAccessPolicyRule -PolicyName "deny-delete-policy" -Name "no-deletes" -Attributes @{
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

        [Parameter(Mandatory, Position = 1)]
        [string]$Name,

        [Parameter()]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $body = if ($Attributes) { $Attributes } else { @{} }
    $queryParams = @{
        'names'        = $Name
        'policy_names' = $PolicyName
    }

    if ($PSCmdlet.ShouldProcess($Name, 'Create access policy rule')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'object-store-access-policies/rules' -Body $body -QueryParams $queryParams
    }
}
