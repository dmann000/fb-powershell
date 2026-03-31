function Get-PfbAuditFileSystemPolicyMember {
    <#
    .SYNOPSIS
        Retrieves members associated with an audit file-system policy.
    .DESCRIPTION
        The Get-PfbAuditFileSystemPolicyMember cmdlet returns the file-system members that
        are associated with one or more audit file-system policies on the connected Pure
        Storage FlashBlade. Use the cross-reference parameters to filter by policy or member.
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
        Get-PfbAuditFileSystemPolicyMember -PolicyName "audit-fs-pol1"

        Retrieves all members of the audit file-system policy named "audit-fs-pol1".
    .EXAMPLE
        Get-PfbAuditFileSystemPolicyMember -MemberName "fs1"

        Retrieves all audit file-system policy memberships for the file system "fs1".
    .EXAMPLE
        Get-PfbAuditFileSystemPolicyMember -PolicyName "audit-fs-pol1" -MemberName "fs1"

        Retrieves the specific membership between the policy and file system.
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

    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'audit-file-systems-policies/members' -QueryParams $queryParams -AutoPaginate
}
