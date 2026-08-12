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
    .PARAMETER Id
        One or more replica link IDs to retrieve. A selector in its own right, and combinable
        with either remote-array selector.
    .PARAMETER RemoteName
        One or more REMOTE ARRAY names whose replica links to retrieve. Distinct from
        -RemoteFileSystemName, which filters on the remote FILE SYSTEM. Mutually exclusive with
        -RemoteId: the API declares remote_names and remote_ids as alternative ways to name the
        same remote dimension.
    .PARAMETER RemoteId
        One or more REMOTE ARRAY IDs whose replica links to retrieve. Mutually exclusive with
        -RemoteName.
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
    .EXAMPLE
        Get-PfbFileSystemReplicaLink -RemoteId "10314f42-020d-7080-8013-000133810cd0"

        Retrieves the replica links pointing at the remote array with that ID.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter()] [string[]]$LocalFileSystemName,
        [Parameter()] [string[]]$RemoteFileSystemName,

        # -Id is declared in all three sets so it binds on its own (resolving to the default
        # List set) and composes with either remote-array selector. Of the keys this cmdlet
        # emits, remote_names + remote_ids is the only combination the spec forbids ("This
        # cannot be provided together with the `remote_ids` query parameter"), so only those
        # two occupy exclusive sets.
        [Parameter(ParameterSetName = 'List')]
        [Parameter(ParameterSetName = 'ByRemoteName')]
        [Parameter(ParameterSetName = 'ByRemoteId')]
        [string[]]$Id,

        [Parameter(ParameterSetName = 'ByRemoteName')]
        [string[]]$RemoteName,

        [Parameter(ParameterSetName = 'ByRemoteId')]
        [string[]]$RemoteId,

        [Parameter()] [string]$Filter, [Parameter()] [string]$Sort, [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )
    Assert-PfbConnection -Array ([ref]$Array)
    $queryParams = @{}
    # remote_names and remote_ids are assigned inline for the reason given in
    # Get-PfbArrayConnection.ps1: they are replication-family keys, not common ones.
    Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters -Ids $Id
    if ($LocalFileSystemName)  { $queryParams['local_file_system_names']  = $LocalFileSystemName -join ',' }
    if ($RemoteFileSystemName) { $queryParams['remote_file_system_names'] = $RemoteFileSystemName -join ',' }
    if ($RemoteName) { $queryParams['remote_names'] = $RemoteName -join ',' }
    if ($RemoteId)   { $queryParams['remote_ids']   = $RemoteId   -join ',' }
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'file-system-replica-links' -QueryParams $queryParams -AutoPaginate
}
