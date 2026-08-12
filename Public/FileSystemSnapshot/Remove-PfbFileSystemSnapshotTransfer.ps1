function Remove-PfbFileSystemSnapshotTransfer {
    <#
    .SYNOPSIS
        Removes a file system snapshot transfer from the FlashBlade.
    .DESCRIPTION
        Cancels or removes an in-progress or completed file system snapshot transfer.
        This is a disruptive operation that stops replication of the snapshot to
        the remote target.

        -RemoteName and -RemoteId are qualifiers rather than identities: one of -Name or -Id
        is always required, and a remote selector only narrows that transfer further.
    .PARAMETER Name
        The name of the snapshot transfer to remove.
    .PARAMETER Id
        The ID of the snapshot transfer to remove.
    .PARAMETER RemoteName
        One or more REMOTE ARRAY names, narrowing the removal to transfers targeting those
        remotes. A qualifier on -Name or -Id, not a replacement for them. Mutually exclusive
        with -RemoteId: the API declares remote_names and remote_ids as alternative ways to
        name the same remote dimension.
    .PARAMETER RemoteId
        One or more REMOTE ARRAY IDs, narrowing the removal to transfers targeting those
        remotes. A qualifier on -Name or -Id, not a replacement for them. Mutually exclusive
        with -RemoteName.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        Remove-PfbFileSystemSnapshotTransfer -Name "fs01.snap1"
        Removes the snapshot transfer for 'fs01.snap1'.
    .EXAMPLE
        Remove-PfbFileSystemSnapshotTransfer -Id "abc-123"
        Removes the snapshot transfer with the specified ID.
    .EXAMPLE
        Remove-PfbFileSystemSnapshotTransfer -Name "fs01.snap1" -Confirm:$false
        Removes the snapshot transfer without prompting for confirmation.
    .EXAMPLE
        Remove-PfbFileSystemSnapshotTransfer -Name "fs01.snap1" -RemoteId "10314f42-020d-7080-8013-000133810cd0"
        Removes the transfer of 'fs01.snap1' that targets the remote array with that ID.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(ParameterSetName = 'ById', Mandatory)]
        [string]$Id,

        # The remote-array dimension narrows an already-identified transfer, so it stays out of
        # the identity sets and remains usable with either. The spec forbids only the two remote
        # forms together, which is enforced at runtime rather than by doubling the set count.
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string[]]$RemoteName,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string[]]$RemoteId,

        [Parameter()]
        [PSCustomObject]$Array
    )

    begin {
        if ($PSBoundParameters.ContainsKey('RemoteName') -and $PSBoundParameters.ContainsKey('RemoteId')) {
            throw '-RemoteName and -RemoteId cannot be used together: remote_names and remote_ids are mutually exclusive.'
        }
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $queryParams = @{}
        if ($Name) { $queryParams['names'] = $Name }
        if ($Id)   { $queryParams['ids']   = $Id }
        # remote_names and remote_ids are assigned inline for the reason given in
        # Get-PfbArrayConnection.ps1: they are replication-family keys, not common ones.
        if ($RemoteName) { $queryParams['remote_names'] = $RemoteName -join ',' }
        if ($RemoteId)   { $queryParams['remote_ids']   = $RemoteId   -join ',' }

        $target = if ($Name) { $Name } else { $Id }
        if ($RemoteName)   { $target = "$target -> $($RemoteName -join ',')" }
        elseif ($RemoteId) { $target = "$target -> $($RemoteId -join ',')" }

        if ($PSCmdlet.ShouldProcess($target, 'Remove file system snapshot transfer')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'file-system-snapshots/transfer' -QueryParams $queryParams
        }
    }
}
