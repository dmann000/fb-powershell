function New-PfbManagementAccessPolicyDirectoryRole {
    <#
    .SYNOPSIS
        Assigns a directory service role to a management access policy.
    .DESCRIPTION
        The New-PfbManagementAccessPolicyDirectoryRole cmdlet creates a new assignment between
        a management access policy and a directory service role on the connected Pure Storage
        FlashBlade. Supports ShouldProcess for confirmation prompts.
    .PARAMETER PolicyName
        The name of the management access policy.
    .PARAMETER PolicyId
        The ID of the management access policy.
    .PARAMETER MemberName
        The name of the directory service role to assign.
    .PARAMETER MemberId
        The ID of the directory service role to assign.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbManagementAccessPolicyDirectoryRole -PolicyName "full-access" -MemberName "ad-admins-role"

        Assigns the directory service role "ad-admins-role" to the "full-access" policy.
    .EXAMPLE
        New-PfbManagementAccessPolicyDirectoryRole -PolicyId "abc12345" -MemberId "def67890"

        Assigns the directory service role to the policy using IDs.
    .EXAMPLE
        New-PfbManagementAccessPolicyDirectoryRole -PolicyName "ops-policy" -MemberName "ops-role" -WhatIf

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

    if ($PSCmdlet.ShouldProcess($target, 'Assign directory service role to management access policy')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'management-access-policies/directory-services/roles' -QueryParams $queryParams
    }
}
