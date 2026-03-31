function Remove-PfbFileSystemSnapshotTransfer {
    <#
    .SYNOPSIS
        Removes a file system snapshot transfer from the FlashBlade.
    .DESCRIPTION
        Cancels or removes an in-progress or completed file system snapshot transfer.
        This is a disruptive operation that stops replication of the snapshot to
        the remote target.
    .PARAMETER Name
        The name of the snapshot transfer to remove.
    .PARAMETER Id
        The ID of the snapshot transfer to remove.
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
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(ParameterSetName = 'ById', Mandatory)]
        [string]$Id,

        [Parameter()]
        [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $queryParams = @{}
        if ($Name) { $queryParams['names'] = $Name }
        if ($Id)   { $queryParams['ids']   = $Id }

        $target = if ($Name) { $Name } else { $Id }

        if ($PSCmdlet.ShouldProcess($target, 'Remove file system snapshot transfer')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'file-system-snapshots/transfer' -QueryParams $queryParams
        }
    }
}
