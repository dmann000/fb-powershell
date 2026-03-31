function New-PfbAdminSshCaPolicy {
    <#
    .SYNOPSIS
        Assigns an SSH certificate authority policy to a FlashBlade administrator.
    .DESCRIPTION
        The New-PfbAdminSshCaPolicy cmdlet creates a new assignment between an administrator
        and an SSH certificate authority policy on the connected Pure Storage FlashBlade. Both
        the administrator and policy can be identified by name or ID. Supports ShouldProcess
        for confirmation prompts.
    .PARAMETER MemberName
        The name of the administrator to assign the SSH CA policy to.
    .PARAMETER MemberId
        The ID of the administrator to assign the SSH CA policy to.
    .PARAMETER PolicyName
        The name of the SSH CA policy to assign.
    .PARAMETER PolicyId
        The ID of the SSH CA policy to assign.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbAdminSshCaPolicy -MemberName "pureuser" -PolicyName "ssh-ca-prod"

        Assigns the "ssh-ca-prod" SSH CA policy to the administrator "pureuser".
    .EXAMPLE
        New-PfbAdminSshCaPolicy -MemberName "ops-admin" -PolicyName "ssh-ca-ops" -WhatIf

        Shows what would happen if the SSH CA policy were assigned without making changes.
    .EXAMPLE
        New-PfbAdminSshCaPolicy -MemberId "10314f42-020d-7080-8013-000ddt400012" -PolicyId "abc12345-6789-0abc-def0-123456789abc"

        Assigns the SSH CA policy using IDs.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
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

    if ($PSCmdlet.ShouldProcess($target, 'Assign SSH CA policy to admin')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'admins/ssh-certificate-authority-policies' -QueryParams $queryParams
    }
}
