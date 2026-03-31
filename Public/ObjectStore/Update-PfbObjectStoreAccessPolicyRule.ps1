function Update-PfbObjectStoreAccessPolicyRule {
    <#
    .SYNOPSIS
        Updates an existing object store access policy rule.
    .DESCRIPTION
        Modifies properties of an access policy rule, such as its effect,
        actions, resources, or conditions. The rule is identified by its
        fully-qualified name (policy/rule format).
    .PARAMETER Name
        The fully-qualified name of the rule to update (policy/rule format).
    .PARAMETER Attributes
        A hashtable of rule properties to update.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        Update-PfbObjectStoreAccessPolicyRule -Name "full-access-policy/rule1" -Attributes @{
            effect = "deny"
        }
        Changes the rule effect to deny.
    .EXAMPLE
        Update-PfbObjectStoreAccessPolicyRule -Name "readonly-policy/rule1" -Attributes @{
            actions = @("s3:GetObject", "s3:ListBucket", "s3:GetBucketLocation")
        }
        Updates the allowed actions on the specified rule.
    .EXAMPLE
        Update-PfbObjectStoreAccessPolicyRule -Name "upload-policy/rule1" -Attributes @{
            resources = @("mybucket/*")
        }
        Restricts the rule to a specific bucket.
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

        if ($PSCmdlet.ShouldProcess($Name, 'Update access policy rule')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'object-store-access-policies/rules' -Body $body -QueryParams $queryParams
        }
    }
}
