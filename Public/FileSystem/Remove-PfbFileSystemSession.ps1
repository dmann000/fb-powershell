function Remove-PfbFileSystemSession {
    <#
    .SYNOPSIS
        Terminates a file system session on the FlashBlade.
    .DESCRIPTION
        Forces the termination of an active client session connected to a file system.
        This is a disruptive operation that disconnects the client and may cause
        in-progress operations to fail.
    .PARAMETER Name
        The name of the file system whose session should be terminated.
    .PARAMETER Id
        The ID of the session to terminate.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        Remove-PfbFileSystemSession -Name "fs01"
        Terminates sessions on file system 'fs01'.
    .EXAMPLE
        Remove-PfbFileSystemSession -Id "abc-123"
        Terminates the session with the specified ID.
    .EXAMPLE
        Remove-PfbFileSystemSession -Name "fs01" -Confirm:$false
        Terminates the session without prompting for confirmation.
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

        if ($PSCmdlet.ShouldProcess($target, 'Terminate file system session')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'file-systems/sessions' -QueryParams $queryParams
        }
    }
}
