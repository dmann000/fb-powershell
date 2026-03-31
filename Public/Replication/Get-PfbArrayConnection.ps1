function Get-PfbArrayConnection {
    <#
    .SYNOPSIS
        Retrieves FlashBlade array connections (replication links between arrays).
    .DESCRIPTION
        The Get-PfbArrayConnection cmdlet returns array connection configurations from the
        connected Pure Storage FlashBlade. Array connections define replication links between
        FlashBlade arrays and are required for file system and bucket replication. Supports
        pipeline input, server-side filtering, and automatic pagination.
    .PARAMETER Name
        One or more array connection names to retrieve. Accepts pipeline input.
    .PARAMETER Id
        One or more array connection IDs to retrieve.
    .PARAMETER Filter
        A server-side filter expression to narrow results (e.g., "status='connected'").
    .PARAMETER Sort
        Sort field and direction (e.g., "name" or "name-").
    .PARAMETER Limit
        Maximum number of array connection entries to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbArrayConnection

        Retrieves all array connections from the connected FlashBlade.
    .EXAMPLE
        Get-PfbArrayConnection -Name "remote-fb-dc2"

        Retrieves the array connection named "remote-fb-dc2".
    .EXAMPLE
        Get-PfbArrayConnection -Filter "status='connected'" -Sort "name" -Limit 10

        Retrieves up to 10 connected array connections sorted by name.
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
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'array-connections' -QueryParams $queryParams -AutoPaginate
    }
}
