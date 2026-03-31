function Remove-PfbSshCaPolicyAdmin {
    <#
    .SYNOPSIS
        Removes an admin from an SSH certificate authority policy on a FlashBlade array.
    .DESCRIPTION
        The Remove-PfbSshCaPolicyAdmin cmdlet removes the association between an admin user
        and an SSH CA policy on the connected Pure Storage FlashBlade.
    .PARAMETER PolicyName
        The SSH CA policy name.
    .PARAMETER PolicyId
        The SSH CA policy ID.
    .PARAMETER MemberName
        The admin name to remove from the policy.
    .PARAMETER MemberId
        The admin ID to remove from the policy.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbSshCaPolicyAdmin -PolicyName "ssh-ca-prod" -MemberName "pureuser"

        Removes "pureuser" from the SSH CA policy after prompting for confirmation.
    .EXAMPLE
        Remove-PfbSshCaPolicyAdmin -PolicyName "ssh-ca-prod" -MemberName "admin1" -Confirm:$false

        Removes the admin association without prompting.
    .EXAMPLE
        Remove-PfbSshCaPolicyAdmin -PolicyName "ssh-ca-test" -MemberName "devuser"

        Removes "devuser" from the SSH CA policy after prompting.
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
    if ($PolicyId) { $queryParams['policy_ids'] = $PolicyId }
    if ($MemberName) { $queryParams['member_names'] = $MemberName }
    if ($MemberId) { $queryParams['member_ids'] = $MemberId }

    $target = "${PolicyName}:${MemberName}"

    if ($PSCmdlet.ShouldProcess($target, 'Remove SSH CA policy admin')) {
        Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'ssh-certificate-authority-policies/admins' -QueryParams $queryParams
    }
}
