function Get-PfbTlsPolicyMember {
    <#
    .SYNOPSIS
        Retrieves TLS policy member associations from a FlashBlade array.
    .DESCRIPTION
        The Get-PfbTlsPolicyMember cmdlet returns the cross-reference of members associated
        with TLS policies on the connected Pure Storage FlashBlade. This is a read-only view
        showing which resources are governed by each TLS policy.
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
        Get-PfbTlsPolicyMember

        Retrieves all TLS policy member associations.
    .EXAMPLE
        Get-PfbTlsPolicyMember -PolicyName "tls-strict"

        Retrieves all members of the specified TLS policy.
    .EXAMPLE
        Get-PfbTlsPolicyMember -PolicyName "tls-strict" -Limit 20

        Retrieves up to 20 members of the specified TLS policy.
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
    if ($Filter) { $queryParams['filter'] = $Filter }
    if ($Limit -gt 0) { $queryParams['limit'] = $Limit }

    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'tls-policies/members' -QueryParams $queryParams -AutoPaginate
}
