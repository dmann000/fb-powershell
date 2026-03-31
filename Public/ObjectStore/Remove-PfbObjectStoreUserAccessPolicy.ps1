function Remove-PfbObjectStoreUserAccessPolicy {
    <#
    .SYNOPSIS
        Removes the link between an object store user and an access policy.
    .DESCRIPTION
        Deletes the association between an object store user and an access
        policy. The user will no longer inherit the permissions defined by
        that policy.
    .PARAMETER MemberName
        The name of the object store user (account/user format).
    .PARAMETER PolicyName
        The name of the access policy to unlink.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        Remove-PfbObjectStoreUserAccessPolicy -MemberName "acct1/user1" -PolicyName "full-access-policy"
        Removes the link between the user and the access policy.
    .EXAMPLE
        Remove-PfbObjectStoreUserAccessPolicy -MemberName "acct1/temp-user" -PolicyName "temp-policy"
        Unlinks a temporary policy from its user.
    .EXAMPLE
        Get-PfbObjectStoreUserAccessPolicy -MemberName "acct1/old-user" |
            ForEach-Object { Remove-PfbObjectStoreUserAccessPolicy -MemberName $_.member.name -PolicyName $_.policy.name }
        Removes all access policy links from a user.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$MemberName,

        [Parameter(Mandatory, Position = 1)]
        [string]$PolicyName,

        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{
        'member_names' = $MemberName
        'policy_names' = $PolicyName
    }

    if ($PSCmdlet.ShouldProcess("User=$MemberName, Policy=$PolicyName", 'Remove user access policy link')) {
        Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'object-store-users/object-store-access-policies' -QueryParams $queryParams
    }
}
