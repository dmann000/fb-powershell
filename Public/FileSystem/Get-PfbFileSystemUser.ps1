function Get-PfbFileSystemUser {
    <#
    .SYNOPSIS
        Retrieves users known to file systems on a FlashBlade array.
    .DESCRIPTION
        The Get-PfbFileSystemUser cmdlet returns user identities (UID/name/SID) associated
        with one or more file systems on the connected Pure Storage FlashBlade. Distinct from
        Get-PfbUsageUser (per-user usage statistics) -- this is identity/lookup data, useful
        for building -Subject hashtables for New-PfbUserGroupQuotaPolicyRule.
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
    .PARAMETER TotalOnly
        Return only the total count, not the items.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbFileSystemUser -FileSystemName "fs-home"
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
        [Parameter()] [switch]$TotalOnly,
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

    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'file-systems/users' -QueryParams $queryParams -AutoPaginate
}
