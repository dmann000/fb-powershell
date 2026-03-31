function New-PfbManagementAccessPolicyAdmin {
    <#
    .SYNOPSIS
        Assigns an administrator to a management access policy.
    .DESCRIPTION
        The New-PfbManagementAccessPolicyAdmin cmdlet creates a new assignment between a
        management access policy and an administrator on the connected Pure Storage FlashBlade.
        Supports ShouldProcess for confirmation prompts.
    .PARAMETER PolicyName
        The name of the management access policy.
    .PARAMETER PolicyId
        The ID of the management access policy.
    .PARAMETER MemberName
        The name of the administrator to assign.
    .PARAMETER MemberId
        The ID of the administrator to assign.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbManagementAccessPolicyAdmin -PolicyName "full-access" -MemberName "pureuser"

        Assigns the administrator "pureuser" to the "full-access" policy.
    .EXAMPLE
        New-PfbManagementAccessPolicyAdmin -PolicyId "abc12345" -MemberId "def67890"

        Assigns the administrator to the policy using IDs.
    .EXAMPLE
        New-PfbManagementAccessPolicyAdmin -PolicyName "ops-policy" -MemberName "ops-admin" -WhatIf

        Shows what would happen without making changes.
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
    if ($PolicyId)   { $queryParams['policy_ids']   = $PolicyId }
    if ($MemberName) { $queryParams['member_names'] = $MemberName }
    if ($MemberId)   { $queryParams['member_ids']   = $MemberId }

    $target = "${PolicyName}:${MemberName}"

    if ($PSCmdlet.ShouldProcess($target, 'Assign admin to management access policy')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'management-access-policies/admins' -QueryParams $queryParams
    }
}
