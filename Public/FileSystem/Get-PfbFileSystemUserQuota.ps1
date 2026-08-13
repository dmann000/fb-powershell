function Get-PfbFileSystemUserQuota {
    <#
    .SYNOPSIS
        Retrieves per-user quota usage and limits for file systems on a FlashBlade array.
    .DESCRIPTION
        The Get-PfbFileSystemUserQuota cmdlet returns the effective user-group-quota-policy
        usage/limit entries for individual users on one or more file systems. Distinct from
        Get-PfbQuotaUser (the legacy per-filesystem purequota/purefs quota model) -- this cmdlet
        reports quotas from the newer policy-based user-group-quota-policy model.
    .PARAMETER FileSystemName
        One or more file system names to filter by.
    .PARAMETER FileSystemId
        One or more file system IDs to filter by.
    .PARAMETER UserName
        One or more user names to filter by.
    .PARAMETER UserId
        One or more numeric UIDs to filter by.
    .PARAMETER UserSid
        One or more user SIDs to filter by.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction.
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbFileSystemUserQuota -FileSystemName "fs-home"
    #>
    [CmdletBinding()]
    param(
        [Parameter()] [string[]]$FileSystemName,
        [Parameter()] [string[]]$FileSystemId,
        [Parameter()] [string[]]$UserName,
        [Parameter()] [string[]]$UserId,
        [Parameter()] [string[]]$UserSid,
        [Parameter()] [string]$Filter,
        [Parameter()] [string]$Sort,
        [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    if ($FileSystemName) { $queryParams['file_system_names'] = $FileSystemName -join ',' }
    if ($FileSystemId)   { $queryParams['file_system_ids']   = $FileSystemId -join ',' }
    if ($UserName) { $queryParams['user_names'] = $UserName -join ',' }
    if ($UserId)   { $queryParams['uids']       = $UserId -join ',' }
    if ($UserSid)  { $queryParams['user_sids']  = $UserSid -join ',' }
    Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters

    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'file-system-user-quotas' -QueryParams $queryParams -AutoPaginate
}
