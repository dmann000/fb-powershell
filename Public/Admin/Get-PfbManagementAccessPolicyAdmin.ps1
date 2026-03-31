function Get-PfbManagementAccessPolicyAdmin {
    <#
    .SYNOPSIS
        Retrieves administrator assignments for management access policies.
    .DESCRIPTION
        The Get-PfbManagementAccessPolicyAdmin cmdlet returns the administrator assignments
        for management access policies on the connected Pure Storage FlashBlade. Results can
        be filtered by policy name or ID, and by member (administrator) name or ID.
    .PARAMETER PolicyName
        One or more management access policy names to filter by.
    .PARAMETER PolicyId
        One or more management access policy IDs to filter by.
    .PARAMETER MemberName
        One or more administrator names to filter by.
    .PARAMETER MemberId
        One or more administrator IDs to filter by.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Limit
        Maximum number of entries to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbManagementAccessPolicyAdmin

        Retrieves all administrator assignments for management access policies.
    .EXAMPLE
        Get-PfbManagementAccessPolicyAdmin -PolicyName "full-access"

        Retrieves administrators assigned to the "full-access" policy.
    .EXAMPLE
        Get-PfbManagementAccessPolicyAdmin -MemberName "pureuser" -PolicyName "ops-policy"

        Retrieves the specific assignment between the administrator and policy.
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

    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'management-access-policies/admins' -QueryParams $queryParams -AutoPaginate
}
