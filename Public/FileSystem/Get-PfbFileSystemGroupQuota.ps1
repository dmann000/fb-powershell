function Get-PfbFileSystemGroupQuota {
    <#
    .SYNOPSIS
        Retrieves per-group quota usage and limits for file systems on a FlashBlade array.
    .DESCRIPTION
        The Get-PfbFileSystemGroupQuota cmdlet returns the effective user-group-quota-policy
        usage/limit entries for individual groups on one or more file systems.
    .PARAMETER FileSystemName
        One or more file system names to filter by.
    .PARAMETER FileSystemId
        One or more file system IDs to filter by.
    .PARAMETER GroupName
        One or more group names to filter by.
    .PARAMETER GroupId
        One or more numeric GIDs to filter by.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction.
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbFileSystemGroupQuota -FileSystemName "fs-home"
    #>
    [CmdletBinding()]
    param(
        [Parameter()] [string[]]$FileSystemName,
        [Parameter()] [string[]]$FileSystemId,
        [Parameter()] [string[]]$GroupName,
        [Parameter()] [string[]]$GroupId,
        [Parameter()] [string]$Filter,
        [Parameter()] [string]$Sort,
        [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    if ($FileSystemName) { $queryParams['file_system_names'] = $FileSystemName -join ',' }
    if ($FileSystemId)   { $queryParams['file_system_ids']   = $FileSystemId -join ',' }
    if ($GroupName) { $queryParams['group_names'] = $GroupName -join ',' }
    if ($GroupId)   { $queryParams['gids']        = $GroupId -join ',' }
    if ($Filter) { $queryParams['filter'] = $Filter }
    if ($Sort)   { $queryParams['sort']   = $Sort }
    if ($Limit -gt 0) { $queryParams['limit'] = $Limit }

    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'file-system-group-quotas' -QueryParams $queryParams -AutoPaginate
}
