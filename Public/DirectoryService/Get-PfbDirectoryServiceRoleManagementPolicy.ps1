function Get-PfbDirectoryServiceRoleManagementPolicy {
    <#
    .SYNOPSIS
        Retrieves management access policy assignments for directory service roles.
    .DESCRIPTION
        The Get-PfbDirectoryServiceRoleManagementPolicy cmdlet returns the management access
        policy assignments for directory service roles on the connected Pure Storage FlashBlade.
        Results can be filtered by member (role) name or ID, and by policy name or ID.
    .PARAMETER MemberName
        One or more directory service role names to filter by.
    .PARAMETER MemberId
        One or more directory service role IDs to filter by.
    .PARAMETER PolicyName
        One or more management access policy names to filter by.
    .PARAMETER PolicyId
        One or more management access policy IDs to filter by.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Limit
        Maximum number of entries to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbDirectoryServiceRoleManagementPolicy

        Retrieves all management access policy assignments for directory service roles.
    .EXAMPLE
        Get-PfbDirectoryServiceRoleManagementPolicy -MemberName "ad-admins"

        Retrieves management access policies assigned to the directory service role "ad-admins".
    .EXAMPLE
        Get-PfbDirectoryServiceRoleManagementPolicy -PolicyName "full-access" -MemberName "ad-admins"

        Retrieves the specific assignment between the policy and directory service role.
    #>
    [CmdletBinding()]
    param(
        [Parameter()] [string[]]$MemberName,
        [Parameter()] [string[]]$MemberId,
        [Parameter()] [string[]]$PolicyName,
        [Parameter()] [string[]]$PolicyId,
        [Parameter()] [string]$Filter,
        [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    if ($MemberName) { $queryParams['member_names'] = $MemberName -join ',' }
    if ($MemberId)   { $queryParams['member_ids']   = $MemberId -join ',' }
    if ($PolicyName) { $queryParams['policy_names'] = $PolicyName -join ',' }
    if ($PolicyId)   { $queryParams['policy_ids']   = $PolicyId -join ',' }
    if ($Filter)     { $queryParams['filter']       = $Filter }
    if ($Limit -gt 0) { $queryParams['limit']       = $Limit }

    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'directory-services/roles/management-access-policies' -QueryParams $queryParams -AutoPaginate
}
