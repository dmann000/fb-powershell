function Get-PfbFileSystemUserGroupQuotaPolicy {
    <#
    .SYNOPSIS
        Retrieves user/group quota policies attached to file systems on a FlashBlade array.
    .DESCRIPTION
        The Get-PfbFileSystemUserGroupQuotaPolicy cmdlet returns the mapping between file
        systems and their attached user-group-quota policies. Same underlying relationship as
        Get-PfbUserGroupQuotaPolicyFileSystem, queried from the file-system side.
    .PARAMETER PolicyName
        One or more policy names to filter by.
    .PARAMETER PolicyId
        One or more policy IDs to filter by.
    .PARAMETER MemberName
        One or more file system names to filter by.
    .PARAMETER MemberId
        One or more file system IDs to filter by.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction.
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER TotalOnly
        Return only the total count, not the items.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbFileSystemUserGroupQuotaPolicy -MemberName "fs1"

        Retrieves the user-group-quota policies attached to file system 'fs1'.
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
        [Parameter()] [switch]$TotalOnly,
        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    if ($PolicyName) { $queryParams['policy_names'] = $PolicyName -join ',' }
    if ($PolicyId)   { $queryParams['policy_ids']   = $PolicyId -join ',' }
    if ($MemberName) { $queryParams['member_names'] = $MemberName -join ',' }
    if ($MemberId)   { $queryParams['member_ids']   = $MemberId -join ',' }
    Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters

    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'file-systems/user-group-quota-policies' -QueryParams $queryParams -AutoPaginate
}
