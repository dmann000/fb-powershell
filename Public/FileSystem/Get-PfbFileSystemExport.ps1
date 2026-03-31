function Get-PfbFileSystemExport {
    <#
    .SYNOPSIS
        Retrieves file system exports from the FlashBlade.
    .DESCRIPTION
        Returns one or more file system export rules from the FlashBlade array.
        Supports filtering by name, ID, or advanced filter expressions. Auto-paginates
        by default.
    .PARAMETER Name
        One or more export names to retrieve. Accepts pipeline input.
    .PARAMETER Id
        One or more export IDs to retrieve.
    .PARAMETER Filter
        A server-side filter expression (e.g., "enabled and rules='*(rw)'").
    .PARAMETER Sort
        Sort field and direction (e.g., "name", "name-" for descending).
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER TotalOnly
        Return only the total count, not the items.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        Get-PfbFileSystemExport
        Returns all file system exports.
    .EXAMPLE
        Get-PfbFileSystemExport -Name "export1", "export2"
        Returns the specified file system exports.
    .EXAMPLE
        Get-PfbFileSystemExport -Filter "enabled" -Sort "name" -Limit 50
        Returns up to 50 enabled exports sorted by name.
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

        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'file-system-exports' -QueryParams $queryParams -AutoPaginate
    }
}
