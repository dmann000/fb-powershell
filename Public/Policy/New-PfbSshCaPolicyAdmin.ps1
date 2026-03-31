function New-PfbSshCaPolicyAdmin {
    <#
    .SYNOPSIS
        Adds an admin to an SSH certificate authority policy on a FlashBlade array.
    .DESCRIPTION
        The New-PfbSshCaPolicyAdmin cmdlet associates an admin user with an SSH CA policy
        on the connected Pure Storage FlashBlade.
    .PARAMETER PolicyName
        The SSH CA policy name.
    .PARAMETER PolicyId
        The SSH CA policy ID.
    .PARAMETER MemberName
        The admin name to associate with the policy.
    .PARAMETER MemberId
        The admin ID to associate with the policy.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbSshCaPolicyAdmin -PolicyName "ssh-ca-prod" -MemberName "pureuser"

        Associates "pureuser" with the SSH CA policy "ssh-ca-prod".
    .EXAMPLE
        New-PfbSshCaPolicyAdmin -PolicyName "ssh-ca-prod" -MemberName "admin1" -WhatIf

        Shows what would happen without actually adding the admin.
    .EXAMPLE
        New-PfbSshCaPolicyAdmin -PolicyName "ssh-ca-dev" -MemberName "devuser"

        Associates "devuser" with the SSH CA policy "ssh-ca-dev".
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
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

    if ($PSCmdlet.ShouldProcess($target, 'Add SSH CA policy admin')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'ssh-certificate-authority-policies/admins' -QueryParams $queryParams
    }
}
