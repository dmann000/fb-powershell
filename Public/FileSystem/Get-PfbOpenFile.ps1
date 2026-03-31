function Get-PfbOpenFile {
    <#
    .SYNOPSIS
        Retrieves open files from the FlashBlade.
    .DESCRIPTION
        Returns information about currently open files on file systems. Supports
        filtering by file system name, ID, or advanced filter expressions.
        Auto-paginates by default.
    .PARAMETER Name
        One or more file system names to retrieve open files for. Accepts pipeline input.
    .PARAMETER Id
        One or more open file IDs to retrieve.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction.
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER TotalOnly
        Return only the total count, not the items.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        Get-PfbOpenFile
        Returns all open files on the FlashBlade.
    .EXAMPLE
        Get-PfbOpenFile -Name "fs01"
        Returns all open files on file system 'fs01'.
    .EXAMPLE
        Get-PfbOpenFile -Filter "protocol='SMB'" -Limit 100
        Returns up to 100 open files using the SMB protocol.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(ParameterSetName = 'ByName', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Name,

        [Parameter(ParameterSetName = 'ById')]
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
        [switch]$TotalOnly,

        [Parameter()]
        [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
        $allNames = [System.Collections.Generic.List[string]]::new()
        $allIds = [System.Collections.Generic.List[string]]::new()
    }

    process {
        if ($Name) { foreach ($n in $Name) { $allNames.Add($n) } }
        if ($Id)   { foreach ($i in $Id)   { $allIds.Add($i) } }
    }

    end {
        $queryParams = @{}
        if ($allNames.Count -gt 0) { $queryParams['names']      = $allNames -join ',' }
        if ($allIds.Count -gt 0)   { $queryParams['ids']        = $allIds -join ',' }
        if ($Filter)               { $queryParams['filter']     = $Filter }
        if ($Sort)                 { $queryParams['sort']       = $Sort }
        if ($Limit -gt 0)         { $queryParams['limit']      = $Limit }
        if ($TotalOnly)            { $queryParams['total_only'] = 'true' }

        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'file-systems/open-files' -QueryParams $queryParams -AutoPaginate
    }
}
