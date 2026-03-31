function Get-PfbRemoteArray {
    <#
    .SYNOPSIS
        Retrieves remote array configurations from a FlashBlade array.
    .DESCRIPTION
        The Get-PfbRemoteArray cmdlet returns remote array information from the connected
        Pure Storage FlashBlade. Remote arrays represent other FlashBlade or FlashArray systems
        that are visible for replication or fleet operations.
    .PARAMETER Name
        One or more remote array names to retrieve. Accepts pipeline input.
    .PARAMETER Id
        One or more remote array IDs to retrieve.
    .PARAMETER Filter
        A server-side filter expression to narrow results (e.g., "status='connected'").
    .PARAMETER Sort
        Sort field and direction (e.g., "name" or "name-").
    .PARAMETER Limit
        Maximum number of entries to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbRemoteArray

        Retrieves all remote arrays from the connected FlashBlade.
    .EXAMPLE
        Get-PfbRemoteArray -Name "remote-dc2"

        Retrieves the remote array named "remote-dc2".
    .EXAMPLE
        Get-PfbRemoteArray -Filter "status='connected'" -Limit 20

        Retrieves up to 20 connected remote arrays.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(ParameterSetName = 'ByName', ValueFromPipeline, ValueFromPipelineByPropertyName)] [string[]]$Name,
        [Parameter(ParameterSetName = 'ById')] [string[]]$Id,
        [Parameter()] [string]$Filter, [Parameter()] [string]$Sort, [Parameter()] [int]$Limit,
        [Parameter()] [switch]$CurrentFleetOnly = $true,
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
        if ($CurrentFleetOnly) { $queryParams['current_fleet_only'] = 'true' } else { $queryParams['current_fleet_only'] = 'false' }
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'remote-arrays' -QueryParams $queryParams -AutoPaginate
    }
}
