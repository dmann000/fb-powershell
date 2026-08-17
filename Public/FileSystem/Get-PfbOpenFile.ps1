function Get-PfbOpenFile {
    <#
    .SYNOPSIS
        Retrieves open files from the FlashBlade.
    .DESCRIPTION
        Returns information about currently open files on file systems. Supports
        filtering by open-file ID. Auto-paginates by default.
    .PARAMETER Id
        One or more open file IDs to retrieve. Binds from the pipeline by property
        name, so open-file objects (which carry 'id') can be piped in directly.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction.
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        Get-PfbOpenFile
        Returns all open files on the FlashBlade.
    .EXAMPLE
        Get-PfbOpenFile -Id "abc-123"
        Returns the open file with the specified ID.
    .EXAMPLE
        Get-PfbOpenFile -Filter "protocol='SMB'" -Limit 100
        Returns up to 100 open files using the SMB protocol.
    .EXAMPLE
        Get-PfbOpenFile | Where-Object { $_.lock_count -gt 0 } | Remove-PfbOpenFile
        Closes the locked open files; -Id binds from the 'id' property of each
        piped object.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(ParameterSetName = 'ById', ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Id,

        [Parameter()]
        [string]$Filter,

        [Parameter()]
        [string]$Sort,

        [Parameter()]
        [ValidateRange(1, 10000)]
        [int]$Limit,

        [Parameter()]
        [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
        $allIds = [System.Collections.Generic.List[string]]::new()
    }

    process {
        if ($Id) { foreach ($i in $Id) { $allIds.Add($i) } }
    }

    end {
        $queryParams = @{}
        Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters -Ids $allIds

        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'file-systems/open-files' -QueryParams $queryParams -AutoPaginate
    }
}
