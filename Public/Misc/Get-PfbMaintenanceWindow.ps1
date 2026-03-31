function Get-PfbMaintenanceWindow {
    <#
    .SYNOPSIS
        Retrieves maintenance windows from a FlashBlade array.
    .DESCRIPTION
        The Get-PfbMaintenanceWindow cmdlet returns maintenance window configurations from
        the connected Pure Storage FlashBlade. Maintenance windows suppress alerts during
        planned maintenance activities.
    .PARAMETER Name
        One or more maintenance window names to retrieve. Accepts pipeline input.
    .PARAMETER Id
        One or more maintenance window IDs to retrieve.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction (e.g., "name" or "name-").
    .PARAMETER Limit
        Maximum number of entries to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbMaintenanceWindow

        Retrieves all maintenance windows from the connected FlashBlade.
    .EXAMPLE
        Get-PfbMaintenanceWindow -Name "maint-weekly"

        Retrieves the maintenance window named "maint-weekly".
    .EXAMPLE
        Get-PfbMaintenanceWindow -Filter "active='true'" -Limit 5

        Retrieves up to 5 active maintenance windows.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(ParameterSetName = 'ByName', ValueFromPipeline, ValueFromPipelineByPropertyName)] [string[]]$Name,
        [Parameter(ParameterSetName = 'ById')] [string[]]$Id,
        [Parameter()] [string]$Filter, [Parameter()] [string]$Sort, [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )
    begin {
        Assert-PfbConnection -Array ([ref]$Array)
        $allNames = [System.Collections.Generic.List[string]]::new()
        $allIds = [System.Collections.Generic.List[string]]::new()
    }

    process {
        if ($Name) { foreach ($n in $Name) { $allNames.Add($n) } }
        if ($Id) { foreach ($i in $Id) { $allIds.Add($i) } }
    }

    end {
        $queryParams = @{}
        if ($allNames.Count -gt 0) { $queryParams['names'] = $allNames -join ',' }
        if ($allIds.Count -gt 0) { $queryParams['ids'] = $allIds -join ',' }
        if ($Filter) { $queryParams['filter'] = $Filter }
        if ($Sort) { $queryParams['sort'] = $Sort }
        if ($Limit -gt 0) { $queryParams['limit'] = $Limit }
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'maintenance-windows' -QueryParams $queryParams -AutoPaginate
    }
}
