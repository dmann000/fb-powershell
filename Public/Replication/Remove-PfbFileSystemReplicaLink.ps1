function Remove-PfbFileSystemReplicaLink {
    <#
    .SYNOPSIS
        Removes a file system replica link.
    .DESCRIPTION
        Deletes the replication relationship between a local file system and a remote
        target. Does NOT delete the file systems themselves on either side. By default,
        in-progress transfers are allowed to complete; pass -CancelInProgressTransfers
        to abort them.
    .PARAMETER LocalFileSystemName
        Local file system name whose replica link should be removed.
    .PARAMETER RemoteArrayName
        Remote array name. Together with -LocalFileSystemName uniquely identifies a link.
        Mutually exclusive with -RemoteId: the API declares remote_names and remote_ids as
        alternative ways to name the same remote dimension.
    .PARAMETER RemoteId
        Remote array ID -- the ID counterpart of -RemoteArrayName, sent as remote_ids. It names
        the remote side only, so -LocalFileSystemName is still required alongside it; use -Id
        to identify a link on its own.
    .PARAMETER RemoteFileSystemName
        Remote file system name (optional, for further disambiguation).
    .PARAMETER Id
        Replica link ID. Alternative to the name-based parameters.
    .PARAMETER CancelInProgressTransfers
        Cancel any in-progress replication transfers when removing the link.
    .PARAMETER Array
        FlashBlade connection.
    .EXAMPLE
        Remove-PfbFileSystemReplicaLink -LocalFileSystemName fs01 -RemoteArrayName remote-fb
    .EXAMPLE
        Remove-PfbFileSystemReplicaLink -LocalFileSystemName fs01 `
            -RemoteId 10314f42-020d-7080-8013-000133810cd0
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'ByName')]
    param(
        # The remote selectors are alternatives to each other, not to the local identity, so
        # -LocalFileSystemName stays mandatory in both composite sets. Only -Id identifies a
        # link on its own.
        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [Parameter(Mandatory, ParameterSetName = 'ByRemoteId')]
        [ValidateScript({ Assert-PfbSafeName $_ })]
        [string]$LocalFileSystemName,

        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [ValidateScript({ Assert-PfbSafeName $_ })]
        [string]$RemoteArrayName,

        [Parameter(Mandatory, ParameterSetName = 'ByRemoteId')]
        [ValidateNotNullOrEmpty()]
        [string]$RemoteId,

        [Parameter(ParameterSetName = 'ByName')]
        [Parameter(ParameterSetName = 'ByRemoteId')]
        [string]$RemoteFileSystemName,

        [Parameter(Mandatory, ParameterSetName = 'ById')]
        [ValidateNotNullOrEmpty()]
        [string]$Id,

        [Parameter()]
        [switch]$CancelInProgressTransfers,

        [Parameter()]
        [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    switch ($PSCmdlet.ParameterSetName) {
        'ByName' {
            $queryParams['local_file_system_names'] = $LocalFileSystemName
            $queryParams['remote_names']            = $RemoteArrayName
            if ($RemoteFileSystemName) { $queryParams['remote_file_system_names'] = $RemoteFileSystemName }
            $target = "$LocalFileSystemName -> $RemoteArrayName"
        }
        'ByRemoteId' {
            $queryParams['local_file_system_names'] = $LocalFileSystemName
            $queryParams['remote_ids']              = $RemoteId
            if ($RemoteFileSystemName) { $queryParams['remote_file_system_names'] = $RemoteFileSystemName }
            $target = "$LocalFileSystemName -> $RemoteId"
        }
        default {
            $queryParams['ids'] = $Id
            $target = $Id
        }
    }
    if ($CancelInProgressTransfers) { $queryParams['cancel_in_progress_transfers'] = 'true' }

    if ($PSCmdlet.ShouldProcess($target, 'Remove file system replica link')) {
        Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'file-system-replica-links' -QueryParams $queryParams
    }
}
