function Get-PfbAdminManagementAccessPolicy {
    <#
    .SYNOPSIS
        Retrieves management access policy assignments for FlashBlade administrators.
    .DESCRIPTION
        The Get-PfbAdminManagementAccessPolicy cmdlet returns the management access policy
        assignments for administrators on the connected Pure Storage FlashBlade. Results can
        be filtered by member (administrator) name or ID, and by policy name or ID. Supports
        automatic pagination and server-side filtering.
    .PARAMETER MemberName
        One or more administrator names to filter by.
    .PARAMETER MemberId
        One or more administrator IDs to filter by.
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
        Get-PfbAdminManagementAccessPolicy

        Retrieves all admin management access policy assignments.
    .EXAMPLE
        Get-PfbAdminManagementAccessPolicy -MemberName "pureuser"

        Retrieves management access policies assigned to the administrator "pureuser".
    .EXAMPLE
        Get-PfbAdminManagementAccessPolicy -PolicyName "full-access" -MemberName "ops-admin"

        Retrieves the specific policy assignment between the policy and administrator.
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

    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'admins/management-access-policies' -QueryParams $queryParams -AutoPaginate
}
