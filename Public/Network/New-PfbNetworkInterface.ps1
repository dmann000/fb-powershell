function New-PfbNetworkInterface {
    <#
    .SYNOPSIS
        Creates a new network interface (VIP) on the FlashBlade.
    .DESCRIPTION
        Creates a virtual IP. The FlashBlade derives the associated subnet, gateway,
        netmask, MTU and VLAN from `-Address` -- those fields are read-only in the API
        and cannot be sent in the create body. A subnet covering `-Address` must already
        exist (create with New-PfbSubnet).
    .PARAMETER Name
        The name of the network interface to create. Required.
    .PARAMETER Address
        The IPv4 or IPv6 address for the VIP. The address must fall within an existing
        subnet's CIDR range.
    .PARAMETER Services
        Services and protocols enabled on the interface. Valid values: data, egress-only,
        management, replication, support. Pass one or more.
    .PARAMETER AttachedServers
        Names of servers that should use this interface for data ingress. If services
        includes 'data', defaults to the array's primary server when omitted.
    .PARAMETER Type
        Interface type. Only `vip` is valid.
    .PARAMETER Attributes
        Full request body as a hashtable. Use this only when the typed parameters above
        don't expose a field you need (e.g. a brand-new 2.x API field). Mutually
        exclusive with -Address / -Services / -AttachedServers / -Type -- if you pass
        -Attributes, those typed params will not be accepted.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        New-PfbNetworkInterface -Name "vir0" -Address "10.0.0.100" -Services data

        Create a data VIP. The subnet, gateway, netmask, MTU, and VLAN are derived
        automatically from a pre-existing subnet whose CIDR covers 10.0.0.100.
    .EXAMPLE
        New-PfbNetworkInterface -Name "repl0" -Address "10.0.0.200" -Services replication
    .EXAMPLE
        New-PfbNetworkInterface -Name "vir1" -Attributes @{
            address = "10.0.0.101"; services = @("data"); type = "vip"
        }
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'Individual')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(ParameterSetName = 'Individual')]
        [string]$Address,

        [Parameter(ParameterSetName = 'Individual')]
        [ValidateSet('data', 'egress-only', 'management', 'replication', 'support')]
        [string[]]$Services,

        [Parameter(ParameterSetName = 'Individual')]
        [string[]]$AttachedServers,

        [Parameter(ParameterSetName = 'Individual')]
        [ValidateSet('vip')]
        [string]$Type = 'vip',

        [Parameter(Mandatory, ParameterSetName = 'Attributes')]
        [hashtable]$Attributes,

        [Parameter()]
        [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    if ($PSCmdlet.ParameterSetName -eq 'Attributes') {
        if ($Attributes.ContainsKey('subnet')) {
            Write-Warning "The 'subnet' field is read-only on FlashBlade and is derived from the IP address. Dropping it from the request body."
            $body = @{}
            foreach ($k in $Attributes.Keys) { if ($k -ne 'subnet') { $body[$k] = $Attributes[$k] } }
        } else {
            $body = $Attributes
        }
    }
    else {
        $body = @{}
        if ($Address)         { $body['address']  = $Address }
        if ($Services)        { $body['services'] = @($Services) }
        if ($Type)            { $body['type']     = $Type }
        if ($AttachedServers) {
            $body['attached_servers'] = @($AttachedServers | ForEach-Object { @{ name = $_ } })
        }
    }

    $queryParams = @{ 'names' = $Name }

    if ($PSCmdlet.ShouldProcess($Name, 'Create network interface (VIP)')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'network-interfaces' -Body $body -QueryParams $queryParams
    }
}
