function Get-PfbFileSystemGroup {
    <#
    .SYNOPSIS
        Retrieves groups known to file systems on a FlashBlade array.
    .DESCRIPTION
        The Get-PfbFileSystemGroup cmdlet returns group identities (GID/name) associated with
        one or more file systems on the connected Pure Storage FlashBlade. Distinct from
        Get-PfbUsageGroup (per-group usage statistics) — this is identity/lookup data, useful
        for building -Subject hashtables for New-PfbUserGroupQuotaPolicyRule.
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
        Get-PfbFileSystemGroup -FileSystemName "fs-home"
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

    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'file-systems/groups' -QueryParams $queryParams -AutoPaginate
}
