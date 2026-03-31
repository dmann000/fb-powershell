function Remove-PfbAdminSshCaPolicy {
    <#
    .SYNOPSIS
        Removes an SSH certificate authority policy assignment from a FlashBlade administrator.
    .DESCRIPTION
        The Remove-PfbAdminSshCaPolicy cmdlet removes the assignment between an administrator
        and an SSH certificate authority policy on the connected Pure Storage FlashBlade. This
        is a destructive operation and requires confirmation by default.
    .PARAMETER MemberName
        The name of the administrator from which to remove the SSH CA policy.
    .PARAMETER MemberId
        The ID of the administrator from which to remove the SSH CA policy.
    .PARAMETER PolicyName
        The name of the SSH CA policy to unassign.
    .PARAMETER PolicyId
        The ID of the SSH CA policy to unassign.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbAdminSshCaPolicy -MemberName "pureuser" -PolicyName "ssh-ca-prod"

        Removes the "ssh-ca-prod" SSH CA policy from the administrator "pureuser".
    .EXAMPLE
        Remove-PfbAdminSshCaPolicy -MemberName "ops-admin" -PolicyName "ssh-ca-ops" -Confirm:$false

        Removes the SSH CA policy assignment without confirmation.
    .EXAMPLE
        Remove-PfbAdminSshCaPolicy -MemberId "10314f42-020d-7080-8013-000ddt400012" -PolicyId "abc12345-6789-0abc-def0-123456789abc"

        Removes the SSH CA policy assignment using IDs.
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

    if ($PSCmdlet.ShouldProcess($target, 'Remove SSH CA policy from admin')) {
        Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'admins/ssh-certificate-authority-policies' -QueryParams $queryParams
    }
}
