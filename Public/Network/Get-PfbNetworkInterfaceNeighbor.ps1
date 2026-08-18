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
        # Within this family, the cross-endpoint chain from Get-PfbNetworkInterface into Get-PfbNetworkInterfaceNeighbor
        # cannot filter correctly: a producer's bare `name` bound to -LocalPortName / `local_port_names`
        # is the defect because `name` means different things by endpoint and metadata cannot identify
        # its producer, so no correct generic binding exists. An undeclared or non-matching query key
        # returns HTTP 200 with the unfiltered collection, so the guard's loud failure is best. Do NOT
        # remove it or add an alias: that flips WrongScalar to Bound while sending the wrong name;
        # revisit only if the consumer can establish its producer, which metadata alone cannot. Issue #90.
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
        Assert-PfbSelectorNotCoerced -Value $LocalPortName -OriginalInput $PSItem -ParameterName 'LocalPortName' -Hint (
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
