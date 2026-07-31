function Get-PfbDataEvictionPolicyFileSystem {
    <#
    .SYNOPSIS
        Lists file system attachments for data eviction policies.
    .DESCRIPTION
        Returns the file-system-to-policy membership records. Filter by policy or by
        file-system member.
    .PARAMETER PolicyName
        Policy name(s) to filter by.
    .PARAMETER PolicyId
        Policy ID(s) to filter by.
    .PARAMETER MemberName
        File system name(s) to filter by.
    .PARAMETER MemberId
        File system ID(s) to filter by.
    .PARAMETER Filter
        Server-side filter expression.
    .PARAMETER Sort
        Sort field and direction.
    .PARAMETER Limit
        Max items to return.
    .PARAMETER Array
        FlashBlade connection.
    .EXAMPLE
        Get-PfbDataEvictionPolicyFileSystem -PolicyName 'tier-out-100tb'
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

    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'data-eviction-policies/file-systems' -QueryParams $queryParams -AutoPaginate
}
