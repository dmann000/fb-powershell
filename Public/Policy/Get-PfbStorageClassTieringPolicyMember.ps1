function Get-PfbStorageClassTieringPolicyMember {
    <#
    .SYNOPSIS
        Retrieves storage class tiering policy member associations from a FlashBlade array.
    .DESCRIPTION
        The Get-PfbStorageClassTieringPolicyMember cmdlet returns the cross-reference of
        members associated with storage class tiering policies on the connected Pure Storage
        FlashBlade. This is a read-only view.
    .PARAMETER PolicyName
        One or more policy names to filter by.
    .PARAMETER PolicyId
        One or more policy IDs to filter by.
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
        Get-PfbStorageClassTieringPolicyMember

        Retrieves all tiering policy member associations.
    .EXAMPLE
        Get-PfbStorageClassTieringPolicyMember -PolicyName "tier-to-archive"

        Retrieves all members of the specified tiering policy.
    .EXAMPLE
        Get-PfbStorageClassTieringPolicyMember -MemberName "fs1" -Limit 10

        Retrieves up to 10 tiering policy associations for the specified member.
    .NOTES
        <!-- PfbContext: generated from Data/PfbCapabilityMap.json contextScope. Do not edit. -->
        Context requirement (GET /storage-class-tiering-policies/members): the context scope for this endpoint is not
        recorded in the capability map, so the module will not pre-validate a context
        for it. A fleet or array context may still be required by the array itself; if
        a call fails with a context error, set one with Set-PfbContext or scope the
        call with Invoke-PfbInContext.
        <!-- /PfbContext -->
    #>
    [CmdletBinding()]
    param(
        [Parameter()] [string[]]$PolicyName,
        [Parameter()] [string[]]$PolicyId,
        [Parameter()] [string[]]$MemberName,
        [Parameter()] [string[]]$MemberId,
        [Parameter()] [string]$Filter, [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    if ($PolicyName) { $queryParams['policy_names'] = $PolicyName -join ',' }
    if ($PolicyId) { $queryParams['policy_ids'] = $PolicyId -join ',' }
    if ($MemberName) { $queryParams['member_names'] = $MemberName -join ',' }
    if ($MemberId) { $queryParams['member_ids'] = $MemberId -join ',' }
    Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters

    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'storage-class-tiering-policies/members' -QueryParams $queryParams -AutoPaginate
}
