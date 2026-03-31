function Get-PfbFileSystemSnapshot {
    <#
    .SYNOPSIS
        Retrieves FlashBlade file system snapshots.
    .PARAMETER Name
        One or more snapshot names to retrieve.
    .PARAMETER Id
        One or more snapshot IDs to retrieve.
    .PARAMETER SourceName
        Filter by source file system name.
    .PARAMETER Filter
        A server-side filter expression.
    .PARAMETER Sort
        Sort field and direction.
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER TotalOnly
        Return only the total count.
    .PARAMETER Destroyed
        Include destroyed snapshots.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        Get-PfbFileSystemSnapshot
    .EXAMPLE
        Get-PfbFileSystemSnapshot -SourceName "fs1"
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(ParameterSetName = 'ByName', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$Name,

        [Parameter(ParameterSetName = 'ById')]
        [string[]]$Id,

        [Parameter()]
        [string]$SourceName,

        [Parameter()]
        [string]$Filter,

        [Parameter()]
        [string]$Sort,

        [Parameter()]
        [int]$Limit,

        [Parameter()]
        [switch]$TotalOnly,

        [Parameter()]
        [switch]$Destroyed,

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
        if ($allNames.Count -gt 0) { $queryParams['names']         = $allNames -join ',' }
        if ($allIds.Count -gt 0)   { $queryParams['ids']           = $allIds -join ',' }
        if ($SourceName)           { $queryParams['source_names']  = $SourceName }
        if ($Filter)               { $queryParams['filter']        = $Filter }
        if ($Sort)                 { $queryParams['sort']          = $Sort }
        if ($Limit -gt 0)         { $queryParams['limit']         = $Limit }
        if ($TotalOnly)            { $queryParams['total_only']    = 'true' }
        if ($Destroyed)            { $queryParams['destroyed']     = 'true' }

        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'file-system-snapshots' -QueryParams $queryParams -AutoPaginate
    }
}
