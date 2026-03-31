function Remove-PfbManagementAccessPolicyDirectoryRole {
    <#
    .SYNOPSIS
        Removes a directory service role assignment from a management access policy.
    .DESCRIPTION
        The Remove-PfbManagementAccessPolicyDirectoryRole cmdlet removes the assignment between
        a management access policy and a directory service role on the connected Pure Storage
        FlashBlade. This is a destructive operation and requires confirmation by default.
    .PARAMETER PolicyName
        The name of the management access policy.
    .PARAMETER PolicyId
        The ID of the management access policy.
    .PARAMETER MemberName
        The name of the directory service role to unassign.
    .PARAMETER MemberId
        The ID of the directory service role to unassign.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbManagementAccessPolicyDirectoryRole -PolicyName "full-access" -MemberName "ad-admins-role"

        Removes the directory service role "ad-admins-role" from the "full-access" policy.
    .EXAMPLE
        Remove-PfbManagementAccessPolicyDirectoryRole -PolicyName "ops-policy" -MemberName "ops-role" -Confirm:$false

        Removes the assignment without confirmation.
    .EXAMPLE
        Remove-PfbManagementAccessPolicyDirectoryRole -PolicyId "abc12345" -MemberId "def67890"

        Removes the assignment using IDs.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter()] [string]$PolicyName,
        [Parameter()] [string]$PolicyId,
        [Parameter()] [string]$MemberName,
        [Parameter()] [string]$MemberId,
        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    if ($PolicyName) { $queryParams['policy_names'] = $PolicyName }
    if ($PolicyId)   { $queryParams['policy_ids']   = $PolicyId }
    if ($MemberName) { $queryParams['member_names'] = $MemberName }
    if ($MemberId)   { $queryParams['member_ids']   = $MemberId }

    $target = "${PolicyName}:${MemberName}"

    if ($PSCmdlet.ShouldProcess($target, 'Remove directory service role from management access policy')) {
        Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'management-access-policies/directory-services/roles' -QueryParams $queryParams
    }
}
