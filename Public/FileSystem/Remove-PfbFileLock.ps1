function Remove-PfbFileLock {
    <#
    .SYNOPSIS
        Removes a file lock from the FlashBlade.
    .DESCRIPTION
        Forces the release of a file lock by name or ID. This is a disruptive operation
        that can cause data loss if the locked file is being actively modified.
    .PARAMETER Name
        The name of the file system whose lock should be removed.
    .PARAMETER Id
        The ID of the file lock to remove.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        Remove-PfbFileLock -Name "fs01"
        Removes file locks on file system 'fs01'.
    .EXAMPLE
        Remove-PfbFileLock -Id "abc-123"
        Removes the file lock with the specified ID.
    .EXAMPLE
        Remove-PfbFileLock -Name "fs01" -Confirm:$false
        Removes the lock without prompting for confirmation.
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

        if ($PSCmdlet.ShouldProcess($target, 'Remove file lock')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'file-systems/locks' -QueryParams $queryParams
        }
    }
}
