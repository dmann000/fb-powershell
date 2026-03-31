function Remove-PfbObjectStoreRoleAccessPolicy {
    <#
    .SYNOPSIS
        Removes the link between an object store role and an access policy.
    .DESCRIPTION
        Deletes the association between an object store role and an access
        policy. The role will no longer inherit the permissions defined by
        that policy.
    .PARAMETER RoleName
        The name of the object store role.
    .PARAMETER MemberName
        The name of the access policy to unlink.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        Remove-PfbObjectStoreRoleAccessPolicy -RoleName "s3-admin-role" -MemberName "full-access-policy"
        Removes the link between the role and the access policy.
    .EXAMPLE
        Remove-PfbObjectStoreRoleAccessPolicy -RoleName "temp-role" -MemberName "temp-policy"
        Unlinks a temporary policy from its role.
    .EXAMPLE
        Get-PfbObjectStoreRoleAccessPolicy -RoleName "old-role" |
            ForEach-Object { Remove-PfbObjectStoreRoleAccessPolicy -RoleName $_.role.name -MemberName $_.member.name }
        Removes all access policy links from a role.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
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

    if ($PSCmdlet.ShouldProcess("Role=$RoleName, Policy=$MemberName", 'Remove role access policy link')) {
        Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'object-store-roles/object-store-access-policies' -QueryParams $queryParams
    }
}
