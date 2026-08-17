function Get-PfbNetworkInterfaceNeighbor {
    <#
    .SYNOPSIS
        Retrieves LLDP neighbor data for FlashBlade network interfaces.
    .DESCRIPTION
        The Get-PfbNetworkInterfaceNeighbor cmdlet returns Link Layer Discovery Protocol (LLDP)
        neighbor information for network interfaces on the connected FlashBlade.
        This data includes the remote switch name, port description, and chassis ID of
        directly connected network devices.

        The selector on this endpoint is resource-specific: use -LocalPortName to select by
        local port name (wire key 'local_port_names'). The endpoint does not accept the generic
        'names' query key.
    .PARAMETER LocalPortName
        One or more local port names to retrieve neighbor data for. Accepts pipeline input.
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
        Get-PfbNetworkInterfaceNeighbor -LocalPortName "CH1.FM1.ETH1"

        Retrieves LLDP neighbor data for the specified local port.
    .EXAMPLE
        Get-PfbNetworkInterfaceNeighbor -Filter "port_description='Ethernet1/1'" -Limit 20

        Retrieves neighbor records matching the specified port description.
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)] [string[]]$LocalPortName,
        [Parameter()] [string]$Filter,
        [Parameter()] [string]$Sort,
        [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )
    begin {
        Assert-PfbConnection -Array ([ref]$Array)
        $allLocalPortNames = [System.Collections.Generic.List[string]]::new()
    }
    process {
        Assert-PfbSelectorNotCoerced -Value $LocalPortName -ParameterName 'LocalPortName' -Hint (
            'Pipe the interface name instead, e.g. Get-PfbNetworkInterface | ' +
            'Select-Object -ExpandProperty name | Get-PfbNetworkInterfaceNeighbor, ' +
            'or pass -LocalPortName explicitly.')
        if ($LocalPortName) { foreach ($n in $LocalPortName) { $allLocalPortNames.Add($n) } }
    }
    end {
        $queryParams = @{}
        Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters
        if ($allLocalPortNames.Count -gt 0) {
            $queryParams['local_port_names'] = $allLocalPortNames -join ','
        }
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'network-interfaces/neighbors' -QueryParams $queryParams -AutoPaginate
    }
}
