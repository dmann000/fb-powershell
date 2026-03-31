function Get-PfbAsyncLog {
    <#
    .SYNOPSIS
        Retrieves asynchronous log collection jobs from a FlashBlade array.
    .DESCRIPTION
        The Get-PfbAsyncLog cmdlet returns one or more asynchronous log collection jobs from
        the connected Pure Storage FlashBlade. Results can be filtered by name, ID, or a
        server-side filter expression. Supports pipeline input for batch lookups.
    .PARAMETER Name
        One or more async log job names to retrieve. Accepts pipeline input.
    .PARAMETER Id
        One or more async log job IDs to retrieve.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction (e.g., "name" or "name-").
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbAsyncLog

        Retrieves all asynchronous log jobs from the connected FlashBlade.
    .EXAMPLE
        Get-PfbAsyncLog -Name "log-job-1"

        Retrieves the asynchronous log job named "log-job-1".
    .EXAMPLE
        Get-PfbAsyncLog -Filter "status='completed'" -Sort "name" -Limit 10

        Retrieves up to 10 completed async log jobs sorted by name.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(ParameterSetName = 'ByName', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$Name,

        [Parameter(ParameterSetName = 'ById')]
        [string[]]$Id,

        [Parameter()] [string]$Filter,
        [Parameter()] [string]$Sort,
        [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
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
        if ($allNames.Count -gt 0) { $queryParams['names']  = $allNames -join ',' }
        if ($allIds.Count -gt 0)   { $queryParams['ids']    = $allIds -join ',' }
        if ($Filter)               { $queryParams['filter'] = $Filter }
        if ($Sort)                 { $queryParams['sort']   = $Sort }
        if ($Limit -gt 0)         { $queryParams['limit']  = $Limit }

        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'logs-async' -QueryParams $queryParams -AutoPaginate
    }
}
