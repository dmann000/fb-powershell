function New-PfbFileSystemReplicaLink {
    <#
    .SYNOPSIS
        Creates a file system replica link between a local file system and a remote array.
    .DESCRIPTION
        Establishes a replication relationship from a local file system on this FlashBlade
        to a target file system on a remote array. Prerequisite: an active ArrayConnection
        must already exist to the remote array (see Get-PfbArrayConnection /
        New-PfbArrayConnection).

        After the link is created, any snapshot of the local file system is automatically
        replicated to the remote. Use New-PfbFileSystemSnapshot to trigger one. Use
        Get-PfbFileSystemReplicaLinkTransfer to poll transfer status.

        Note: The misleadingly-named New-PfbFileSystemReplicaLinkPolicy cmdlet attaches a
        policy to an existing replica link (POST /file-system-replica-links/policies); it
        does NOT create the link itself. This cmdlet is the one you want for that.
    .PARAMETER LocalFileSystemName
        Name of the local file system to replicate.
    .PARAMETER RemoteArrayName
        Name of the remote FlashBlade (as it appears in Get-PfbArrayConnection.remote.name).
        Mutually exclusive with -RemoteId: the API declares remote_names and remote_ids as
        alternative ways to name the same remote dimension.
    .PARAMETER RemoteId
        ID of the remote FlashBlade (as it appears in Get-PfbArrayConnection.remote.id) -- the
        ID counterpart of -RemoteArrayName, sent as remote_ids. It names the remote side only;
        -LocalFileSystemName is still required, because a replica link is created from a
        local/remote pair and the remote selector alone does not identify one.
    .PARAMETER Id
        Sent verbatim as the ids query parameter, which this endpoint publishes. The published
        spec does not document what ids means on a create, so no create behaviour is claimed
        for it here.
    .PARAMETER RemoteFileSystemName
        Name of the target file system on the remote array. If omitted, the FlashBlade
        will name it after the local file system.
    .PARAMETER RemoteDefaultExports
        Controls whether default NFS/SMB exports are created on the remote file system after
        replication. Tri-state:
          - omitted: the array's own default is used (the FlashBlade creates default exports),
          - $true:   explicitly create default exports on the remote,
          - $false:  suppress the default exports so the remote file system has none.
        Pass -RemoteDefaultExports $false to keep replica file systems export-free (previously
        impossible: this was a [switch] that could only ever request 'true').
    .PARAMETER Array
        FlashBlade connection (the source/local array).
    .EXAMPLE
        New-PfbFileSystemReplicaLink -Array $sourceFb `
            -LocalFileSystemName 'project-data' `
            -RemoteArrayName 'remote-fb'
    .EXAMPLE
        New-PfbFileSystemReplicaLink -Array $sourceFb `
            -LocalFileSystemName 'fs01' -RemoteArrayName 'remote-fb' `
            -RemoteFileSystemName 'fs01-dr'
    .EXAMPLE
        New-PfbFileSystemReplicaLink -Array $sourceFb `
            -LocalFileSystemName 'fs01' -RemoteId '10314f42-020d-7080-8013-000133810cd0'
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByRemoteName')]
    param(
        # Declared without a set name, so it stays mandatory in both: the remote selectors are
        # alternatives to each other, never to the local identity.
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$LocalFileSystemName,

        [Parameter(Mandatory, ParameterSetName = 'ByRemoteName')]
        [ValidateNotNullOrEmpty()]
        [string]$RemoteArrayName,

        [Parameter(Mandatory, ParameterSetName = 'ByRemoteId')]
        [ValidateNotNullOrEmpty()]
        [string]$RemoteId,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string[]]$Id,

        [Parameter()]
        [string]$RemoteFileSystemName,

        [Parameter()]
        [Nullable[bool]]$RemoteDefaultExports,

        [Parameter()]
        [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{
        'local_file_system_names' = $LocalFileSystemName
    }
    # remote_names and remote_ids are the two forms of the same remote dimension; the parameter
    # sets guarantee exactly one of them is bound.
    if ($PSCmdlet.ParameterSetName -eq 'ByRemoteId') {
        $queryParams['remote_ids'] = $RemoteId
        $remoteTarget = $RemoteId
    } else {
        $queryParams['remote_names'] = $RemoteArrayName
        $remoteTarget = $RemoteArrayName
    }
    if ($Id)                     { $queryParams['ids'] = $Id -join ',' }
    if ($RemoteFileSystemName)   { $queryParams['remote_file_system_names'] = $RemoteFileSystemName }
    # Send only when the caller bound it, so an omitted value defers to the array default.
    # $false must reach the wire to suppress the exports, so guard on presence not truthiness.
    if ($PSBoundParameters.ContainsKey('RemoteDefaultExports')) {
        $queryParams['remote_default_exports'] = if ($RemoteDefaultExports) { 'true' } else { 'false' }
    }

    # POST /file-system-replica-links requires a body even if empty
    $body = @{}

    $target = "$LocalFileSystemName -> $remoteTarget"
    if ($PSCmdlet.ShouldProcess($target, 'Create file system replica link')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'file-system-replica-links' -QueryParams $queryParams -Body $body
    }
}
