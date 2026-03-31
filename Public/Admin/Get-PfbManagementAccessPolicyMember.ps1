function Get-PfbManagementAccessPolicyMember {
    <#
    .SYNOPSIS
        Retrieves all members assigned to management access policies.
    .DESCRIPTION
        The Get-PfbManagementAccessPolicyMember cmdlet returns all member assignments
        (administrators, directory service roles, etc.) for management access policies on the
        connected Pure Storage FlashBlade. This is a read-only cross-reference endpoint.
    .PARAMETER PolicyName
        One or more management access policy names to filter by.
    .PARAMETER PolicyId
        One or more management access policy IDs to filter by.
    .PARAMETER MemberName
        One or more member names to filter by.
    .PARAMETER MemberId
        One or more member IDs to filter by.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Limit
        Maximum number of entries to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbManagementAccessPolicyMember

        Retrieves all members for all management access policies.
    .EXAMPLE
        Get-PfbManagementAccessPolicyMember -PolicyName "full-access"

        Retrieves all members assigned to the "full-access" policy.
    .EXAMPLE
        Get-PfbManagementAccessPolicyMember -MemberName "pureuser"

        Retrieves all policy assignments for the member "pureuser".
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

    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'management-access-policies/members' -QueryParams $queryParams -AutoPaginate
}
