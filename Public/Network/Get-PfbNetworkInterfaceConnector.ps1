function Get-PfbNetworkInterfaceConnector {
    <#
    .SYNOPSIS
        Retrieves FlashBlade network interface connector information.
    .DESCRIPTION
        The Get-PfbNetworkInterfaceConnector cmdlet returns details about network interface
        connectors on the connected Pure Storage FlashBlade. Connectors can be filtered by
        name, ID, or a server-side filter expression.
    .PARAMETER Name
        One or more connector names to retrieve.
    .PARAMETER Id
        One or more connector IDs to retrieve.
    .PARAMETER Filter
        A server-side filter expression.
    .PARAMETER Sort
        Sort field and direction.
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbNetworkInterfaceConnector

        Retrieves all network interface connectors.
    .EXAMPLE
        Get-PfbNetworkInterfaceConnector -Name "CH1.FM1.ETH1"

        Retrieves the specified network interface connector.
    .EXAMPLE
        Get-PfbNetworkInterfaceConnector -Filter "enabled='true'" -Sort "name" -Limit 10

        Retrieves up to 10 enabled connectors sorted by name.
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
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'network-interfaces/connectors' -QueryParams $queryParams -AutoPaginate
    }
}
