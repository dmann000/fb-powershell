function New-PfbAdminManagementAccessPolicy {
    <#
    .SYNOPSIS
        Assigns a management access policy to a FlashBlade administrator.
    .DESCRIPTION
        The New-PfbAdminManagementAccessPolicy cmdlet creates a new assignment between an
        administrator and a management access policy on the connected Pure Storage FlashBlade.
        Both the administrator and policy must be identified by name. Supports ShouldProcess
        for confirmation prompts.
    .PARAMETER MemberName
        The name of the administrator to assign the policy to.
    .PARAMETER MemberId
        The ID of the administrator to assign the policy to.
    .PARAMETER PolicyName
        The name of the management access policy to assign.
    .PARAMETER PolicyId
        The ID of the management access policy to assign.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbAdminManagementAccessPolicy -MemberName "pureuser" -PolicyName "full-access"

        Assigns the "full-access" management access policy to the administrator "pureuser".
    .EXAMPLE
        New-PfbAdminManagementAccessPolicy -MemberId "10314f42-020d-7080-8013-000ddt400012" -PolicyName "readonly-access"

        Assigns the "readonly-access" policy to the administrator identified by ID.
    .EXAMPLE
        New-PfbAdminManagementAccessPolicy -MemberName "ops-admin" -PolicyName "ops-policy" -WhatIf

        Shows what would happen if the policy were assigned without making changes.
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

    if ($PSCmdlet.ShouldProcess($target, 'Assign management access policy to admin')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'admins/management-access-policies' -QueryParams $queryParams
    }
}
