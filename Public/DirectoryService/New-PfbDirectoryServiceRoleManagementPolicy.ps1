function New-PfbDirectoryServiceRoleManagementPolicy {
    <#
    .SYNOPSIS
        Assigns a management access policy to a directory service role.
    .DESCRIPTION
        The New-PfbDirectoryServiceRoleManagementPolicy cmdlet creates a new assignment between
        a directory service role and a management access policy on the connected Pure Storage
        FlashBlade. Supports ShouldProcess for confirmation prompts.
    .PARAMETER MemberName
        The name of the directory service role to assign the policy to.
    .PARAMETER MemberId
        The ID of the directory service role to assign the policy to.
    .PARAMETER PolicyName
        The name of the management access policy to assign.
    .PARAMETER PolicyId
        The ID of the management access policy to assign.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbDirectoryServiceRoleManagementPolicy -MemberName "ad-admins" -PolicyName "full-access"

        Assigns the "full-access" policy to the directory service role "ad-admins".
    .EXAMPLE
        New-PfbDirectoryServiceRoleManagementPolicy -MemberId "abc12345" -PolicyId "def67890"

        Assigns the policy to the directory service role using IDs.
    .EXAMPLE
        New-PfbDirectoryServiceRoleManagementPolicy -MemberName "ops-role" -PolicyName "ops-policy" -WhatIf

        Shows what would happen without making changes.
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

    if ($PSCmdlet.ShouldProcess($target, 'Assign management access policy to directory service role')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'directory-services/roles/management-access-policies' -QueryParams $queryParams
    }
}
