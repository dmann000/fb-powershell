function Get-PfbAuditObjectStorePolicyMember {
    <#
    .SYNOPSIS
        Retrieves members associated with an audit object-store policy.
    .DESCRIPTION
        The Get-PfbAuditObjectStorePolicyMember cmdlet returns the object-store account
        members that are associated with one or more audit object-store policies on the
        connected Pure Storage FlashBlade. Use cross-reference parameters to filter results.
    .PARAMETER PolicyName
        One or more policy names to filter members by.
    .PARAMETER PolicyId
        One or more policy IDs to filter members by.
    .PARAMETER MemberName
        One or more member names to filter by.
    .PARAMETER MemberId
        One or more member IDs to filter by.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction (e.g., "member.name" or "member.name-").
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbAuditObjectStorePolicyMember -PolicyName "audit-obj-pol1"

        Retrieves all members of the audit object-store policy named "audit-obj-pol1".
    .EXAMPLE
        Get-PfbAuditObjectStorePolicyMember -MemberName "account1"

        Retrieves all audit object-store policy memberships for the account "account1".
    .EXAMPLE
        Get-PfbAuditObjectStorePolicyMember -PolicyName "audit-obj-pol1" -MemberName "account1"

        Retrieves the specific membership between the policy and account.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string[]]$PolicyName,

        [Parameter()]
        [string[]]$PolicyId,

        [Parameter()]
        [string[]]$MemberName,

        [Parameter()]
        [string[]]$MemberId,

        [Parameter()] [string]$Filter,
        [Parameter()] [string]$Sort,
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
    if ($Sort)       { $queryParams['sort']         = $Sort }
    if ($Limit -gt 0) { $queryParams['limit']       = $Limit }

    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'audit-object-store-policies/members' -QueryParams $queryParams -AutoPaginate
}
