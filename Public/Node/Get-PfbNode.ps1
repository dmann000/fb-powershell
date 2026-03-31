function Get-PfbNode {
    <#
    .SYNOPSIS
        Retrieves FlashBlade node information.
    .DESCRIPTION
        The Get-PfbNode cmdlet returns details about nodes on the connected Pure Storage
        FlashBlade. Nodes represent the individual compute and storage units within the
        array. Results can be filtered by name, ID, or a server-side filter expression.

        Note: The /nodes endpoint is only available on certain FlashBlade models and API
        versions. If it is not supported, this cmdlet automatically falls back to the
        /blades endpoint which provides equivalent blade-level information.
    .PARAMETER Name
        One or more node names to retrieve.
    .PARAMETER Id
        One or more node IDs to retrieve.
    .PARAMETER Filter
        A server-side filter expression.
    .PARAMETER Sort
        Sort field and direction.
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbNode

        Retrieves all nodes in the FlashBlade array.
    .EXAMPLE
        Get-PfbNode -Name "CH1.FB1"

        Retrieves the specified node by name.
    .EXAMPLE
        Get-PfbNode -Filter "status='healthy'" -Sort "name" -Limit 10

        Retrieves up to 10 healthy nodes sorted by name.
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
            Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'nodes' -QueryParams $queryParams -AutoPaginate
        }
        catch {
            if ($_ -match 'Operation not permitted' -or $_ -match '400') {
                Write-Warning "The /nodes endpoint is not supported on this FlashBlade model or API version. Falling back to /blades."
                Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'blades' -QueryParams $queryParams -AutoPaginate
            }
            else {
                throw
            }
        }
    }
}
