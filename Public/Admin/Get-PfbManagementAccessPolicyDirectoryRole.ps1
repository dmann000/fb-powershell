function Get-PfbManagementAccessPolicyDirectoryRole {
    <#
    .SYNOPSIS
        Retrieves directory service role assignments for management access policies.
    .DESCRIPTION
        The Get-PfbManagementAccessPolicyDirectoryRole cmdlet returns the directory service
        role assignments for management access policies on the connected Pure Storage FlashBlade.
        Results can be filtered by policy name or ID, and by member (role) name or ID.
    .PARAMETER PolicyName
        One or more management access policy names to filter by.
    .PARAMETER PolicyId
        One or more management access policy IDs to filter by.
    .PARAMETER MemberName
        One or more directory service role names to filter by.
    .PARAMETER MemberId
        One or more directory service role IDs to filter by.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Limit
        Maximum number of entries to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbManagementAccessPolicyDirectoryRole

        Retrieves all directory service role assignments for management access policies.
    .EXAMPLE
        Get-PfbManagementAccessPolicyDirectoryRole -PolicyName "full-access"

        Retrieves directory service roles assigned to the "full-access" policy.
    .EXAMPLE
        Get-PfbManagementAccessPolicyDirectoryRole -MemberName "ad-admins-role"

        Retrieves policies assigned to the directory service role "ad-admins-role".
    #>
    [CmdletBinding()]
    param(
        [Parameter()] [string[]]$PolicyName,
        [Parameter()] [string[]]$PolicyId,
        [Parameter()] [string[]]$MemberName,
        [Parameter()] [string[]]$MemberId,
        [Parameter()] [string]$Filter,
        [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    if ($PolicyName) { $queryParams['policy_names'] = $PolicyName -join ',' }
    if ($PolicyId)   { $queryParams['policy_ids']   = $PolicyId -join ',' }
    if ($MemberName) { $queryParams['member_names'] = $MemberName -join ',' }
    if ($MemberId)   { $queryParams['member_ids']   = $MemberId -join ',' }
    if ($Filter)     { $queryParams['filter']       = $Filter }
    if ($Limit -gt 0) { $queryParams['limit']       = $Limit }

    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'management-access-policies/directory-services/roles' -QueryParams $queryParams -AutoPaginate
}
