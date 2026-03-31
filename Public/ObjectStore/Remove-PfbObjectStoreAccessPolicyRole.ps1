function Remove-PfbObjectStoreAccessPolicyRole {
    <#
    .SYNOPSIS
        Removes the link between an access policy and an object store role.
    .DESCRIPTION
        Deletes the association between an object store access policy and an
        object store role. The role will no longer inherit the permissions
        defined by the policy.
    .PARAMETER PolicyName
        The name of the access policy.
    .PARAMETER MemberName
        The name of the object store role to unlink.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        Remove-PfbObjectStoreAccessPolicyRole -PolicyName "full-access-policy" -MemberName "s3-admin-role"
        Removes the link between the policy and the role.
    .EXAMPLE
        Remove-PfbObjectStoreAccessPolicyRole -PolicyName "temp-policy" -MemberName "temp-role"
        Unlinks a temporary role from its policy.
    .EXAMPLE
        Get-PfbObjectStoreAccessPolicyRole -PolicyName "old-policy" |
            ForEach-Object { Remove-PfbObjectStoreAccessPolicyRole -PolicyName $_.policy.name -MemberName $_.member.name }
        Removes all role links from a policy.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
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

    if ($PSCmdlet.ShouldProcess("Policy=$PolicyName, Role=$MemberName", 'Remove access policy role link')) {
        Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'object-store-access-policies/object-store-roles' -QueryParams $queryParams
    }
}
