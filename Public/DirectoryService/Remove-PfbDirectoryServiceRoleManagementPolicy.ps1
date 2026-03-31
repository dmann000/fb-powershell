function Remove-PfbDirectoryServiceRoleManagementPolicy {
    <#
    .SYNOPSIS
        Removes a management access policy assignment from a directory service role.
    .DESCRIPTION
        The Remove-PfbDirectoryServiceRoleManagementPolicy cmdlet removes the assignment between
        a directory service role and a management access policy on the connected Pure Storage
        FlashBlade. This is a destructive operation and requires confirmation by default.
    .PARAMETER MemberName
        The name of the directory service role from which to remove the policy.
    .PARAMETER MemberId
        The ID of the directory service role from which to remove the policy.
    .PARAMETER PolicyName
        The name of the management access policy to unassign.
    .PARAMETER PolicyId
        The ID of the management access policy to unassign.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbDirectoryServiceRoleManagementPolicy -MemberName "ad-admins" -PolicyName "full-access"

        Removes the "full-access" policy from the directory service role "ad-admins".
    .EXAMPLE
        Remove-PfbDirectoryServiceRoleManagementPolicy -MemberName "ops-role" -PolicyName "ops-policy" -Confirm:$false

        Removes the assignment without confirmation.
    .EXAMPLE
        Remove-PfbDirectoryServiceRoleManagementPolicy -MemberId "abc12345" -PolicyId "def67890"

        Removes the assignment using IDs.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter()] [string]$MemberName,
        [Parameter()] [string]$MemberId,
        [Parameter()] [string]$PolicyName,
        [Parameter()] [string]$PolicyId,
        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    if ($MemberName) { $queryParams['member_names'] = $MemberName }
    if ($MemberId)   { $queryParams['member_ids']   = $MemberId }
    if ($PolicyName) { $queryParams['policy_names'] = $PolicyName }
    if ($PolicyId)   { $queryParams['policy_ids']   = $PolicyId }

    $target = "${MemberName}:${PolicyName}"

    if ($PSCmdlet.ShouldProcess($target, 'Remove management access policy from directory service role')) {
        Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'directory-services/roles/management-access-policies' -QueryParams $queryParams
    }
}
