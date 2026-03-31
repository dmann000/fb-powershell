function Invoke-PfbNetworkTrace {
    <#
    .SYNOPSIS
        Performs a traceroute from a FlashBlade network interface.
    .DESCRIPTION
        The Invoke-PfbNetworkTrace cmdlet runs a traceroute from the connected Pure Storage
        FlashBlade to a specified destination. This is useful for diagnosing network path
        issues between the FlashBlade and remote hosts. Optionally specify a source interface.
    .PARAMETER Destination
        The hostname or IP address to trace the route to. This parameter is mandatory.
    .PARAMETER SourceName
        The name of the network interface to use as the source of the trace.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Invoke-PfbNetworkTrace -Destination "10.0.0.1"

        Traces the network path from the FlashBlade to the specified IP address.
    .EXAMPLE
        Invoke-PfbNetworkTrace -Destination "nfs-client.example.com" -SourceName "vip1"

        Traces the network path from the vip1 interface to the specified host.
    .EXAMPLE
        Invoke-PfbNetworkTrace -Destination "192.168.1.100"

        Traces the route to the destination using the default source interface.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)] [string]$Destination,
        [Parameter()] [string]$SourceName,
        [Parameter()] [PSCustomObject]$Array
    )
    begin { Assert-PfbConnection -Array ([ref]$Array) }
    process {
        $queryParams = @{ 'destination' = $Destination }
        if ($SourceName) { $queryParams['source.name'] = $SourceName }
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'network-interfaces/trace' -QueryParams $queryParams
    }
}
