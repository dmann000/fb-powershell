function Get-PfbNodeGroup {
    <#
    .SYNOPSIS
        Retrieves FlashBlade node group information.
    .DESCRIPTION
        The Get-PfbNodeGroup cmdlet returns details about node groups on the connected
        Pure Storage FlashBlade. Node groups organize nodes for workload placement and
        resource management. Results can be filtered by name, ID, or a server-side filter.
    .PARAMETER Name
        One or more node group names to retrieve.
    .PARAMETER Id
        One or more node group IDs to retrieve.
    .PARAMETER Filter
        A server-side filter expression.
    .PARAMETER Sort
        Sort field and direction.
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbNodeGroup

        Retrieves all node groups.
    .EXAMPLE
        Get-PfbNodeGroup -Name "default-group"

        Retrieves the specified node group by name.
    .EXAMPLE
        Get-PfbNodeGroup -Filter "node_count>2" -Sort "name" -Limit 5

        Retrieves up to 5 node groups with more than 2 nodes sorted by name.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(ParameterSetName = 'ByName', ValueFromPipeline, ValueFromPipelineByPropertyName)] [string[]]$Name,
        [Parameter(ParameterSetName = 'ById')] [string[]]$Id,
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
        try {
            Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'node-groups' -QueryParams $queryParams -AutoPaginate
        }
        catch {
            if ($_ -match 'not supported' -or $_ -match 'Operation not permitted') {
                Write-Warning "Node groups are not supported on this FlashBlade model."
                return
            }
            throw
        }
    }
}
