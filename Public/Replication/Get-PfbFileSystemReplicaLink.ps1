function Get-PfbFileSystemReplicaLink {
    <#
    .SYNOPSIS
        Retrieves FlashBlade file system replica links.
    .DESCRIPTION
        The Get-PfbFileSystemReplicaLink cmdlet returns file system replica link information
        from the connected Pure Storage FlashBlade. Replica links represent active replication
        relationships between local and remote file systems. Results can be filtered by local
        or remote file system name, or by a server-side filter expression.
    .PARAMETER LocalFileSystemName
        One or more local file system names to filter replica links by.
    .PARAMETER RemoteFileSystemName
        One or more remote file system names to filter replica links by.
    .PARAMETER Filter
        A server-side filter expression to narrow results (e.g., "status='replicating'").
    .PARAMETER Sort
        Sort field and direction (e.g., "direction" or "direction-").
    .PARAMETER Limit
        Maximum number of replica link entries to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbFileSystemReplicaLink

        Retrieves all file system replica links from the connected FlashBlade.
    .EXAMPLE
        Get-PfbFileSystemReplicaLink -LocalFileSystemName "fs-data"

        Retrieves replica links for the local file system named "fs-data".
    .EXAMPLE
        Get-PfbFileSystemReplicaLink -Filter "status='replicating'" -Limit 20

        Retrieves up to 20 actively replicating file system replica links.
    #>
    [CmdletBinding()]
    param(
        [Parameter()] [string[]]$LocalFileSystemName,
        [Parameter()] [string[]]$RemoteFileSystemName,
        [Parameter()] [string]$Filter, [Parameter()] [string]$Sort, [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )
    Assert-PfbConnection -Array ([ref]$Array)
    $queryParams = @{}
    if ($LocalFileSystemName)  { $queryParams['local_file_system_names']  = $LocalFileSystemName -join ',' }
    if ($RemoteFileSystemName) { $queryParams['remote_file_system_names'] = $RemoteFileSystemName -join ',' }
    if ($Filter) { $queryParams['filter'] = $Filter }
    if ($Sort) { $queryParams['sort'] = $Sort }
    if ($Limit -gt 0) { $queryParams['limit'] = $Limit }
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'file-system-replica-links' -QueryParams $queryParams -AutoPaginate
}
