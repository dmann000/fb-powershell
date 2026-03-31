function New-PfbObjectStoreAccessPolicyRole {
    <#
    .SYNOPSIS
        Links an object store role to an access policy.
    .DESCRIPTION
        Creates an association between an object store access policy and an
        object store role. Once linked, the role inherits the permissions
        defined by the access policy.
    .PARAMETER PolicyName
        The name of the access policy.
    .PARAMETER MemberName
        The name of the object store role to link.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        New-PfbObjectStoreAccessPolicyRole -PolicyName "full-access-policy" -MemberName "s3-admin-role"
        Links the s3-admin-role to the full-access-policy.
    .EXAMPLE
        New-PfbObjectStoreAccessPolicyRole -PolicyName "readonly-policy" -MemberName "analytics-role"
        Links the analytics-role to a read-only policy.
    .EXAMPLE
        "role-a","role-b" | ForEach-Object {
            New-PfbObjectStoreAccessPolicyRole -PolicyName "shared-policy" -MemberName $_
        }
        Links multiple roles to the same policy.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$PolicyName,

        [Parameter(Mandatory, Position = 1)]
        [string]$MemberName,

        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{
        'policy_names' = $PolicyName
        'member_names' = $MemberName
    }

    if ($PSCmdlet.ShouldProcess("Policy=$PolicyName, Role=$MemberName", 'Create access policy role link')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'object-store-access-policies/object-store-roles' -QueryParams $queryParams
    }
}
