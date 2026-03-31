function Remove-PfbFileSystemExport {
    <#
    .SYNOPSIS
        Removes a file system export from the FlashBlade.
    .DESCRIPTION
        Deletes a file system export rule by name or ID. This action removes the
        export configuration and any clients using it will lose access.
    .PARAMETER Name
        The name of the file system export to remove.
    .PARAMETER Id
        The ID of the file system export to remove.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        Remove-PfbFileSystemExport -Name "export1"
        Removes the file system export named 'export1'.
    .EXAMPLE
        Remove-PfbFileSystemExport -Id "abc-123"
        Removes the file system export with the specified ID.
    .EXAMPLE
        Remove-PfbFileSystemExport -Name "export1" -Confirm:$false
        Removes the export without prompting for confirmation.
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

        if ($PSCmdlet.ShouldProcess($target, 'Remove file system export')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'file-system-exports' -QueryParams $queryParams
        }
    }
}
