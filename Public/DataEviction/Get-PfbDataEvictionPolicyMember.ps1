function Get-PfbDataEvictionPolicyMember {
    <#
    .SYNOPSIS
        Lists members attached to data eviction policies.
    .DESCRIPTION
        Generic member-listing endpoint covering all resource types attached to data
        eviction policies (currently file systems only, but the endpoint is
        forward-compatible). For the file-system-specific view, use
        Get-PfbDataEvictionPolicyFileSystem.
    .PARAMETER PolicyName
        Policy name(s) to filter by.
    .PARAMETER PolicyId
        Policy ID(s) to filter by.
    .PARAMETER MemberName
        Member resource name(s).
    .PARAMETER MemberId
        Member resource ID(s).
    .PARAMETER Filter
        Server-side filter expression.
    .PARAMETER Sort
        Sort field and direction.
    .PARAMETER Limit
        Max items to return.
    .PARAMETER Array
        FlashBlade connection.
    .EXAMPLE
        Get-PfbDataEvictionPolicyMember -PolicyName 'tier-out-100tb'
    #>
    [CmdletBinding()]
    param(
        [Parameter()] [string[]]$PolicyName,
        [Parameter()] [string[]]$PolicyId,
        [Parameter()] [string[]]$MemberName,
        [Parameter()] [string[]]$MemberId,
        [Parameter()] [string]$Filter,
        [Parameter()] [string]$Sort,
        [Parameter()] [ValidateRange(1, 10000)] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    if ($PolicyName) { $queryParams['policy_names'] = $PolicyName -join ',' }
    if ($PolicyId)   { $queryParams['policy_ids']   = $PolicyId -join ',' }
    if ($MemberName) { $queryParams['member_names'] = $MemberName -join ',' }
    if ($MemberId)   { $queryParams['member_ids']   = $MemberId -join ',' }
    Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters

    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'data-eviction-policies/members' -QueryParams $queryParams -AutoPaginate
}
