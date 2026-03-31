function Get-PfbLag {
    <#
    .SYNOPSIS
        Retrieves FlashBlade link aggregation groups (LAGs).
    .DESCRIPTION
        Returns link aggregation group configurations from the FlashBlade array.
        LAGs bond multiple physical network ports for increased bandwidth and redundancy.
    .PARAMETER Name
        One or more LAG names to retrieve.
    .PARAMETER Id
        One or more LAG IDs to retrieve.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction.
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        Get-PfbLag

        Retrieves all LAGs on the FlashBlade.
    .EXAMPLE
        Get-PfbLag -Name "lag1"

        Retrieves the LAG named 'lag1'.
    .EXAMPLE
        Get-PfbLag -Limit 5 -Sort "name"

        Retrieves up to 5 LAGs sorted by name.
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
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'link-aggregation-groups' -QueryParams $queryParams -AutoPaginate
    }
}
