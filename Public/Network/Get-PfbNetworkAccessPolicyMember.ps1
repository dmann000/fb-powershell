function Get-PfbNetworkAccessPolicyMember {
    <#
    .SYNOPSIS
        Retrieves members associated with network access policies on a FlashBlade array.
    .DESCRIPTION
        The Get-PfbNetworkAccessPolicyMember cmdlet returns the associations between network
        access policies and their members on the connected Pure Storage FlashBlade. Results
        can be filtered by policy name, policy ID, member name, or member ID.
    .PARAMETER PolicyName
        One or more network access policy names to filter by.
    .PARAMETER PolicyId
        One or more network access policy IDs to filter by.
    .PARAMETER MemberName
        One or more member names to filter by.
    .PARAMETER MemberId
        One or more member IDs to filter by.
    .PARAMETER Filter
        A server-side filter expression.
    .PARAMETER Sort
        Sort field and direction.
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbNetworkAccessPolicyMember

        Retrieves all network access policy member associations.
    .EXAMPLE
        Get-PfbNetworkAccessPolicyMember -PolicyName "default-network-policy"

        Retrieves all members of the specified network access policy.
    .EXAMPLE
        Get-PfbNetworkAccessPolicyMember -MemberName "vip1" -PolicyName "restricted-policy"

        Retrieves the association between a specific member and policy.
    #>
    [CmdletBinding()]
    param(
        [Parameter()] [string[]]$PolicyName,
        [Parameter()] [string[]]$PolicyId,
        [Parameter()] [string[]]$MemberName,
        [Parameter()] [string[]]$MemberId,
        [Parameter()] [string]$Filter,
        [Parameter()] [string]$Sort,
        [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    if ($PolicyName) { $queryParams['policy_names']  = $PolicyName -join ',' }
    if ($PolicyId)   { $queryParams['policy_ids']    = $PolicyId -join ',' }
    if ($MemberName) { $queryParams['member_names']  = $MemberName -join ',' }
    if ($MemberId)   { $queryParams['member_ids']    = $MemberId -join ',' }
    if ($Filter)     { $queryParams['filter']        = $Filter }
    if ($Sort)       { $queryParams['sort']          = $Sort }
    if ($Limit -gt 0) { $queryParams['limit']        = $Limit }

    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'network-access-policies/members' -QueryParams $queryParams -AutoPaginate
}
