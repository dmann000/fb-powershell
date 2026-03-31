function Get-PfbQuotaGroup {
    <#
    .SYNOPSIS
        Retrieves group quota information from a Pure Storage FlashBlade.
    .DESCRIPTION
        The Get-PfbQuotaGroup cmdlet returns group quota entries configured on the FlashBlade.
        Results can be filtered by group name, file system name, or a server-side filter expression.
        Supports sorting, pagination limits, and automatic pagination.
    .PARAMETER Name
        One or more group quota names to retrieve. When omitted, all group quotas are returned.
    .PARAMETER FileSystemName
        The name of the file system to scope the query to.
    .PARAMETER Filter
        A server-side filter expression to narrow results (e.g., 'quota > 1048576').
    .PARAMETER Sort
        The field and direction to sort results by (e.g., 'quota-' for descending by quota).
    .PARAMETER Limit
        The maximum number of items to return per page.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbQuotaGroup

        Returns all group quotas across all file systems on the connected FlashBlade.
    .EXAMPLE
        Get-PfbQuotaGroup -FileSystemName 'fs-nfs01'

        Returns all group quotas configured on the file system 'fs-nfs01'.
    .EXAMPLE
        Get-PfbQuotaGroup -Name 'fs-nfs01:engineering' -Array $FlashBlade

        Retrieves the group quota for the 'engineering' group on 'fs-nfs01' using a specific FlashBlade connection.
    #>
    [CmdletBinding()]
    param(
        [Parameter()] [string[]]$Name,
        [Parameter(Mandatory, Position = 0)] [string]$FileSystemName,
        [Parameter()] [string]$Filter, [Parameter()] [string]$Sort, [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )
    Assert-PfbConnection -Array ([ref]$Array)
    $queryParams = @{}
    if ($Name) { $queryParams['names'] = $Name -join ',' }
    if ($FileSystemName) { $queryParams['file_system_names'] = $FileSystemName }
    if ($Filter) { $queryParams['filter'] = $Filter }
    if ($Sort) { $queryParams['sort'] = $Sort }
    if ($Limit -gt 0) { $queryParams['limit'] = $Limit }
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'quotas/groups' -QueryParams $queryParams -AutoPaginate
}
