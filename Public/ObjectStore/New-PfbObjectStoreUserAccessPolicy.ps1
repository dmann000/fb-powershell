function New-PfbObjectStoreUserAccessPolicy {
    <#
    .SYNOPSIS
        Links an access policy to an object store user.
    .DESCRIPTION
        Creates an association between an object store user and an access
        policy. Once linked, the user inherits the permissions defined by
        the access policy.
    .PARAMETER MemberName
        The name of the object store user (account/user format).
    .PARAMETER PolicyName
        The name of the access policy to link.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        New-PfbObjectStoreUserAccessPolicy -MemberName "acct1/user1" -PolicyName "full-access-policy"
        Links the full-access-policy to the specified user.
    .EXAMPLE
        New-PfbObjectStoreUserAccessPolicy -MemberName "acct1/reader" -PolicyName "readonly-policy"
        Links a read-only policy to a reader user.
    .EXAMPLE
        "acct1/user1","acct1/user2" | ForEach-Object {
            New-PfbObjectStoreUserAccessPolicy -MemberName $_ -PolicyName "shared-policy"
        }
        Links the same policy to multiple users.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
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

    if ($PSCmdlet.ShouldProcess("User=$MemberName, Policy=$PolicyName", 'Create user access policy link')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'object-store-users/object-store-access-policies' -QueryParams $queryParams
    }
}
