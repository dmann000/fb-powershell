function Remove-PfbManagementAccessPolicyAdmin {
    <#
    .SYNOPSIS
        Removes an administrator assignment from a management access policy.
    .DESCRIPTION
        The Remove-PfbManagementAccessPolicyAdmin cmdlet removes the assignment between a
        management access policy and an administrator on the connected Pure Storage FlashBlade.
        This is a destructive operation and requires confirmation by default.
    .PARAMETER PolicyName
        The name of the management access policy.
    .PARAMETER PolicyId
        The ID of the management access policy.
    .PARAMETER MemberName
        The name of the administrator to unassign.
    .PARAMETER MemberId
        The ID of the administrator to unassign.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbManagementAccessPolicyAdmin -PolicyName "full-access" -MemberName "pureuser"

        Removes the administrator "pureuser" from the "full-access" policy.
    .EXAMPLE
        Remove-PfbManagementAccessPolicyAdmin -PolicyName "ops-policy" -MemberName "ops-admin" -Confirm:$false

        Removes the assignment without confirmation.
    .EXAMPLE
        Remove-PfbManagementAccessPolicyAdmin -PolicyId "abc12345" -MemberId "def67890"

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

    if ($PSCmdlet.ShouldProcess($target, 'Remove admin from management access policy')) {
        Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'management-access-policies/admins' -QueryParams $queryParams
    }
}
