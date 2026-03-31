function Get-PfbPolicyMember {
    <#
    .SYNOPSIS
        Retrieves members (file systems) associated with a policy.
    .PARAMETER PolicyName
        The policy name to list members for.
    .PARAMETER PolicyId
        The policy ID to list members for.
    .PARAMETER MemberName
        Filter by member name.
    .PARAMETER MemberId
        Filter by member ID.
    .PARAMETER Filter
        A server-side filter expression.
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        Get-PfbPolicyMember -PolicyName "daily-snap"
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
    if ($Limit -gt 0) { $queryParams['limit']        = $Limit }

    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'policies/members' -QueryParams $queryParams -AutoPaginate
}
