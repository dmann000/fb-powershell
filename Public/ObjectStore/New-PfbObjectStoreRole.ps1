function New-PfbObjectStoreRole {
    <#
    .SYNOPSIS
        Creates a new object store role on the FlashBlade.
    .DESCRIPTION
        Creates an IAM-style object store role that can be assumed by federated
        users or services. The role can later be associated with access policies
        and a trust policy to control who may assume it and what permissions it grants.
    .PARAMETER Name
        The name of the role to create.
    .PARAMETER Attributes
        A hashtable of role properties such as description or assume_role_policy.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        New-PfbObjectStoreRole -Name "s3-admin-role"
        Creates a new role with the specified name.
    .EXAMPLE
        New-PfbObjectStoreRole -Name "replication-role" -Attributes @{
            description = "Role for cross-region replication"
        }
        Creates a role with additional attributes.
    .EXAMPLE
        New-PfbObjectStoreRole -Name "analytics-role" -Attributes @{
            description = "Read-only analytics access"
        }
        Creates a role intended for analytics workloads.
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

    if ($PSCmdlet.ShouldProcess($Name, 'Create object store role')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'object-store-roles' -Body $body -QueryParams $queryParams
    }
}
