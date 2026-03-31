function Get-PfbFleet {
    <#
    .SYNOPSIS
        Retrieves fleet configurations from a FlashBlade array.
    .DESCRIPTION
        The Get-PfbFleet cmdlet returns fleet configurations from the connected Pure Storage
        FlashBlade. Fleets group multiple FlashBlade arrays for coordinated management and
        replication. Results can be filtered by name, ID, or a server-side filter expression.
        Supports pipeline input and automatic pagination.
    .PARAMETER Name
        One or more fleet names to retrieve. Accepts pipeline input.
    .PARAMETER Id
        One or more fleet IDs to retrieve.
    .PARAMETER Filter
        A server-side filter expression to narrow results (e.g., "name='fleet1'").
    .PARAMETER Sort
        Sort field and direction (e.g., "name" or "name-").
    .PARAMETER Limit
        Maximum number of fleet entries to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbFleet

        Retrieves all fleets from the connected FlashBlade.
    .EXAMPLE
        Get-PfbFleet -Name "fleet-prod"

        Retrieves the fleet named "fleet-prod".
    .EXAMPLE
        Get-PfbFleet -Filter "name='fleet*'" -Sort "name" -Limit 10

        Retrieves up to 10 fleets matching the filter, sorted by name.
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
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'fleets' -QueryParams $queryParams -AutoPaginate
    }
}
