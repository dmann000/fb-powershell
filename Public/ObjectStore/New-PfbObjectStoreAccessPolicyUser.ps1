function New-PfbObjectStoreAccessPolicyUser {
    <#
    .SYNOPSIS
        Links an object store user to an access policy.
    .DESCRIPTION
        Creates an association between an object store access policy and an
        object store user. Once linked, the user inherits the permissions
        defined by the access policy.
    .PARAMETER PolicyName
        The name of the access policy.
    .PARAMETER MemberName
        The name of the object store user to link (account/user format).
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        New-PfbObjectStoreAccessPolicyUser -PolicyName "full-access-policy" -MemberName "acct1/user1"
        Links the user to the full-access-policy.
    .EXAMPLE
        New-PfbObjectStoreAccessPolicyUser -PolicyName "readonly-policy" -MemberName "acct1/reader"
        Links a reader user to a read-only policy.
    .EXAMPLE
        "acct1/user1","acct1/user2" | ForEach-Object {
            New-PfbObjectStoreAccessPolicyUser -PolicyName "shared-policy" -MemberName $_
        }
        Links multiple users to the same policy.
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

    if ($PSCmdlet.ShouldProcess("Policy=$PolicyName, User=$MemberName", 'Create access policy user link')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'object-store-access-policies/object-store-users' -QueryParams $queryParams
    }
}
