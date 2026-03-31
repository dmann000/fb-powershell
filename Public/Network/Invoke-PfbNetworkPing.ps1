function Invoke-PfbNetworkPing {
    <#
    .SYNOPSIS
        Sends ICMP ping requests from a FlashBlade network interface.
    .DESCRIPTION
        The Invoke-PfbNetworkPing cmdlet sends ICMP echo requests from the connected
        Pure Storage FlashBlade to a specified destination. Optionally specify a source
        interface, packet count, and packet size to customize the ping behavior.
    .PARAMETER Destination
        The hostname or IP address to ping. This parameter is mandatory.
    .PARAMETER SourceName
        The name of the network interface to use as the source of the ping.
    .PARAMETER Count
        The number of ICMP echo requests to send.
    .PARAMETER PacketSize
        The size of the ICMP packet payload in bytes.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Invoke-PfbNetworkPing -Destination "10.0.0.1"

        Pings the specified IP address from the FlashBlade using default settings.
    .EXAMPLE
        Invoke-PfbNetworkPing -Destination "nfs-client.example.com" -SourceName "vip1" -Count 5

        Sends 5 ICMP echo requests to the specified host from the vip1 interface.
    .EXAMPLE
        Invoke-PfbNetworkPing -Destination "192.168.1.100" -PacketSize 1400 -Count 10

        Pings the destination with 10 packets of 1400 bytes each.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)] [string]$Destination,
        [Parameter()] [string]$SourceName,
        [Parameter()] [int]$Count,
        [Parameter()] [int]$PacketSize,
        [Parameter()] [PSCustomObject]$Array
    )
    begin { Assert-PfbConnection -Array ([ref]$Array) }
    process {
        $queryParams = @{ 'destination' = $Destination }
        if ($SourceName)    { $queryParams['source.name']  = $SourceName }
        if ($Count -gt 0)   { $queryParams['count']        = $Count }
        if ($PacketSize -gt 0) { $queryParams['packet_size'] = $PacketSize }
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'network-interfaces/ping' -QueryParams $queryParams
    }
}
