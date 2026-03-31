function Get-PfbNodeGroupUse {
    <#
    .SYNOPSIS
        Retrieves usage information for FlashBlade node groups.
    .DESCRIPTION
        The Get-PfbNodeGroupUse cmdlet returns resource usage data for node groups on the
        connected Pure Storage FlashBlade. This includes information about which resources
        (file systems, object store accounts, etc.) are assigned to each node group.
    .PARAMETER Name
        One or more node group names to retrieve usage for.
    .PARAMETER Filter
        A server-side filter expression.
    .PARAMETER Sort
        Sort field and direction.
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbNodeGroupUse

        Retrieves usage information for all node groups.
    .EXAMPLE
        Get-PfbNodeGroupUse -Name "analytics-group"

        Retrieves usage information for the specified node group.
    .EXAMPLE
        Get-PfbNodeGroupUse -Filter "resource_type='file-system'" -Limit 20

        Retrieves up to 20 node group uses filtered by file system resource type.
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)] [string[]]$Name,
        [Parameter()] [string]$Filter,
        [Parameter()] [string]$Sort,
        [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )
    begin {
        Assert-PfbConnection -Array ([ref]$Array)
        $allNames = [System.Collections.Generic.List[string]]::new()
    }
    process {
        if ($Name) { foreach ($n in $Name) { $allNames.Add($n) } }
    }
    end {
        $queryParams = @{}
        if ($allNames.Count -gt 0) { $queryParams['names']  = $allNames -join ',' }
        if ($Filter)               { $queryParams['filter'] = $Filter }
        if ($Sort)                 { $queryParams['sort']   = $Sort }
        if ($Limit -gt 0)         { $queryParams['limit']  = $Limit }
        try {
            Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'node-groups/uses' -QueryParams $queryParams -AutoPaginate
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
