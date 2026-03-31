function Remove-PfbAdminManagementAccessPolicy {
    <#
    .SYNOPSIS
        Removes a management access policy assignment from a FlashBlade administrator.
    .DESCRIPTION
        The Remove-PfbAdminManagementAccessPolicy cmdlet removes the assignment between an
        administrator and a management access policy on the connected Pure Storage FlashBlade.
        This is a destructive operation and requires confirmation by default.
    .PARAMETER MemberName
        The name of the administrator from which to remove the policy assignment.
    .PARAMETER MemberId
        The ID of the administrator from which to remove the policy assignment.
    .PARAMETER PolicyName
        The name of the management access policy to unassign.
    .PARAMETER PolicyId
        The ID of the management access policy to unassign.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbAdminManagementAccessPolicy -MemberName "pureuser" -PolicyName "full-access"

        Removes the "full-access" policy assignment from the administrator "pureuser".
    .EXAMPLE
        Remove-PfbAdminManagementAccessPolicy -MemberName "ops-admin" -PolicyName "ops-policy" -Confirm:$false

        Removes the policy assignment without confirmation.
    .EXAMPLE
        Remove-PfbAdminManagementAccessPolicy -MemberId "10314f42-020d-7080-8013-000ddt400012" -PolicyId "abc12345-6789-0abc-def0-123456789abc"

        Removes the policy assignment using IDs.
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

    if ($PSCmdlet.ShouldProcess($target, 'Remove management access policy from admin')) {
        Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'admins/management-access-policies' -QueryParams $queryParams
    }
}
