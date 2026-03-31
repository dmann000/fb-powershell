function Get-PfbNetworkInterfaceNeighbor {
    <#
    .SYNOPSIS
        Retrieves LLDP neighbor data for FlashBlade network interfaces.
    .DESCRIPTION
        The Get-PfbNetworkInterfaceNeighbor cmdlet returns Link Layer Discovery Protocol (LLDP)
        neighbor information for network interfaces on the connected Pure Storage FlashBlade.
        This data includes the remote switch name, port description, and chassis ID of
        directly connected network devices.
    .PARAMETER Name
        One or more interface names to retrieve neighbor data for.
    .PARAMETER Filter
        A server-side filter expression.
    .PARAMETER Sort
        Sort field and direction.
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbNetworkInterfaceNeighbor

        Retrieves LLDP neighbor data for all network interfaces.
    .EXAMPLE
        Get-PfbNetworkInterfaceNeighbor -Name "CH1.FM1.ETH1"

        Retrieves LLDP neighbor data for the specified interface.
    .EXAMPLE
        Get-PfbNetworkInterfaceNeighbor -Filter "port_description='Ethernet1/1'" -Limit 20

        Retrieves neighbor records matching the specified port description.
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
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'network-interfaces/neighbors' -QueryParams $queryParams -AutoPaginate
    }
}
