function New-PfbObjectStoreRoleAccessPolicy {
    <#
    .SYNOPSIS
        Links an access policy to an object store role.
    .DESCRIPTION
        Creates an association between an object store role and an access
        policy. Once linked, the role inherits the permissions defined by
        the access policy when assumed.
    .PARAMETER RoleName
        The name of the object store role.
    .PARAMETER MemberName
        The name of the access policy to link.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        New-PfbObjectStoreRoleAccessPolicy -RoleName "s3-admin-role" -MemberName "full-access-policy"
        Links the full-access-policy to the s3-admin-role.
    .EXAMPLE
        New-PfbObjectStoreRoleAccessPolicy -RoleName "analytics-role" -MemberName "readonly-policy"
        Links a read-only policy to the analytics role.
    .EXAMPLE
        "policy-a","policy-b" | ForEach-Object {
            New-PfbObjectStoreRoleAccessPolicy -RoleName "shared-role" -MemberName $_
        }
        Links multiple access policies to the same role.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$RoleName,

        [Parameter(Mandatory, Position = 1)]
        [string]$MemberName,

        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{
        'role_names'   = $RoleName
        'member_names' = $MemberName
    }

    if ($PSCmdlet.ShouldProcess("Role=$RoleName, Policy=$MemberName", 'Create role access policy link')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'object-store-roles/object-store-access-policies' -QueryParams $queryParams
    }
}
