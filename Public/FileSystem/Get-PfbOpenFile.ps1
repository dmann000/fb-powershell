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
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        Get-PfbOpenFile

        Returns open files on the FlashBlade. Note that this cmdlet does not send the
        protocols query parameter the specification marks required; that gap is tracked
        in Reports/PfbApiDriftReport.md rather than worked around here.
    .EXAMPLE
        Get-PfbOpenFile | Where-Object { $_.lock_count -gt 0 } | Remove-PfbOpenFile

        Closes the locked open files. -Id binds from the 'id' property of each piped
        object, which is why this cmdlet declares ValueFromPipelineByPropertyName rather
        than a bare ValueFromPipeline.
    #>
    # The spec-required protocols parameter and six optional gaps are tracked in Reports/PfbApiDriftReport.md.
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(ParameterSetName = 'ById', ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Id,

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
