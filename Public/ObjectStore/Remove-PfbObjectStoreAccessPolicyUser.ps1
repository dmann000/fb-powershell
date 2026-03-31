function Remove-PfbObjectStoreAccessPolicyUser {
    <#
    .SYNOPSIS
        Removes the link between an access policy and an object store user.
    .DESCRIPTION
        Deletes the association between an object store access policy and an
        object store user. The user will no longer inherit the permissions
        defined by the policy.
    .PARAMETER PolicyName
        The name of the access policy.
    .PARAMETER MemberName
        The name of the object store user to unlink (account/user format).
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        Remove-PfbObjectStoreAccessPolicyUser -PolicyName "full-access-policy" -MemberName "acct1/user1"
        Removes the link between the policy and the user.
    .EXAMPLE
        Remove-PfbObjectStoreAccessPolicyUser -PolicyName "temp-policy" -MemberName "acct1/temp-user"
        Unlinks a temporary user from its policy.
    .EXAMPLE
        Get-PfbObjectStoreAccessPolicyUser -PolicyName "old-policy" |
            ForEach-Object { Remove-PfbObjectStoreAccessPolicyUser -PolicyName $_.policy.name -MemberName $_.member.name }
        Removes all user links from a policy.
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

    if ($PSCmdlet.ShouldProcess("Policy=$PolicyName, User=$MemberName", 'Remove access policy user link')) {
        Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'object-store-access-policies/object-store-users' -QueryParams $queryParams
    }
}
