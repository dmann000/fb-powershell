function Remove-PfbOpenFile {
    <#
    .SYNOPSIS
        Closes an open file on the FlashBlade.
    .DESCRIPTION
        Forces the closure of an open file by file system name or ID. This is a
        disruptive operation that can cause data loss if the file is being actively
        written to by a client.
    .PARAMETER Name
        The name of the file system whose open file should be closed.
    .PARAMETER Id
        The ID of the open file to close.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        Remove-PfbOpenFile -Name "fs01"
        Closes open files on file system 'fs01'.
    .EXAMPLE
        Remove-PfbOpenFile -Id "abc-123"
        Closes the open file with the specified ID.
    .EXAMPLE
        Remove-PfbOpenFile -Name "fs01" -Confirm:$false
        Closes the open file without prompting for confirmation.
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

        if ($PSCmdlet.ShouldProcess($target, 'Close open file')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'file-systems/open-files' -QueryParams $queryParams
        }
    }
}
