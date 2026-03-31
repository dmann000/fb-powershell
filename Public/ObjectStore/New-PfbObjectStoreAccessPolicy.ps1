function New-PfbObjectStoreAccessPolicy {
    <#
    .SYNOPSIS
        Creates a new object store access policy on the FlashBlade.
    .DESCRIPTION
        Creates an IAM-style access policy that defines permissions for object
        store resources. Policies contain rules that specify allowed or denied
        actions on buckets and objects.
    .PARAMETER Name
        The name of the access policy to create.
    .PARAMETER Attributes
        A hashtable of policy properties including rules that define the
        allowed or denied actions, resources, and conditions.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        New-PfbObjectStoreAccessPolicy -Name "readonly-policy" -Attributes @{
            rules = @(
                @{
                    actions = @("s3:GetObject", "s3:ListBucket")
                    resources = @("*")
                    effect = "allow"
                }
            )
        }
        Creates a read-only access policy.
    .EXAMPLE
        New-PfbObjectStoreAccessPolicy -Name "full-access" -Attributes @{
            rules = @(
                @{
                    actions = @("s3:*")
                    resources = @("*")
                    effect = "allow"
                }
            )
        }
        Creates a full-access policy for all S3 actions.
    .EXAMPLE
        New-PfbObjectStoreAccessPolicy -Name "deny-delete" -Attributes @{
            rules = @(
                @{
                    actions = @("s3:DeleteObject")
                    resources = @("*")
                    effect = "deny"
                }
            )
        }
        Creates a policy that denies delete operations.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter()]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $body = if ($Attributes) { $Attributes } else { @{} }
    $queryParams = @{ 'names' = $Name }

    if ($PSCmdlet.ShouldProcess($Name, 'Create object store access policy')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'object-store-access-policies' -Body $body -QueryParams $queryParams
    }
}
