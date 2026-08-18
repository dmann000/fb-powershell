function Remove-PfbOpenFile {
    <#
    .SYNOPSIS
        Closes an open file on the FlashBlade.
    .DESCRIPTION
        Forces the closure of an open file by its open-file ID. This is a
        disruptive operation that can cause data loss if the file is being actively
        written to by a client.
    .PARAMETER Id
        The ID of the open file to close. Binds from the pipeline by property name,
        so open-file objects (which carry 'id') can be piped in directly.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        Remove-PfbOpenFile -Id "abc-123"
        Closes the open file with the specified ID.
    .EXAMPLE
        Remove-PfbOpenFile -Id "abc-123" -Confirm:$false
        Closes the open file without prompting for confirmation.
    .EXAMPLE
        Get-PfbOpenFile | Where-Object { $_.path -like '*\temp\*' } | Remove-PfbOpenFile -Confirm:$false
        Closes the matching open files, one DELETE per piped object; -Id binds from
        each object's 'id' property.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string]$Id,

        [Parameter()]
        [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $queryParams = @{}
        if ($Id) { $queryParams['ids'] = $Id }

        if ($PSCmdlet.ShouldProcess($Id, 'Close open file')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'file-systems/open-files' -QueryParams $queryParams
        }
    }
}
