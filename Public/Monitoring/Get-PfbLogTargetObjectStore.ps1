function Get-PfbLogTargetObjectStore {
    <#
    .SYNOPSIS
        Retrieves log-target object-store configurations from a FlashBlade array.
    .DESCRIPTION
        The Get-PfbLogTargetObjectStore cmdlet returns one or more log-target object-store
        configurations from the connected Pure Storage FlashBlade. Results can be filtered
        by name, ID, or a server-side filter expression.
    .PARAMETER Name
        One or more log-target object-store names to retrieve. Accepts pipeline input.
    .PARAMETER Id
        One or more log-target object-store IDs to retrieve.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction (e.g., "name" or "name-").
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbLogTargetObjectStore

        Retrieves all log-target object-store configurations.
    .EXAMPLE
        Get-PfbLogTargetObjectStore -Name "log-obj-target1"

        Retrieves the log-target object-store configuration named "log-obj-target1".
    .EXAMPLE
        Get-PfbLogTargetObjectStore -Filter "enabled='true'" -Sort "name" -Limit 10

        Retrieves up to 10 enabled log-target object stores sorted by name.
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

        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'log-targets/object-store' -QueryParams $queryParams -AutoPaginate
    }
}
