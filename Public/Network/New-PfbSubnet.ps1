function New-PfbSubnet {
    <#
    .SYNOPSIS
        Creates a new subnet on the FlashBlade.
    .PARAMETER Name
        The name of the subnet to create.
    .PARAMETER Prefix
        The subnet prefix (e.g., "10.0.0.0/24").
    .PARAMETER Gateway
        The gateway IP address.
    .PARAMETER Mtu
        The MTU size (default 1500).
    .PARAMETER Vlan
        The VLAN ID.
    .PARAMETER LinkAggregationGroupName
        The LAG to associate with.
    .PARAMETER Attributes
        A hashtable of additional attributes.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        New-PfbSubnet -Name "subnet1" -Prefix "10.0.0.0/24" -Gateway "10.0.0.1"
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter()]
        [string]$Prefix,

        [Parameter()]
        [string]$Gateway,

        [Parameter()]
        [int]$Mtu,

        [Parameter()]
        [int]$Vlan,

        [Parameter()]
        [string]$LinkAggregationGroupName,

        [Parameter()]
        [hashtable]$Attributes,

        [Parameter()]
        [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    if ($Attributes) {
        $body = $Attributes
    }
    else {
        $body = @{}
        if ($Prefix)  { $body['prefix'] = $Prefix }
        if ($Gateway) { $body['gateway'] = $Gateway }
        if ($Mtu -gt 0) { $body['mtu'] = $Mtu }
        if ($Vlan -gt 0) { $body['vlan'] = $Vlan }
        if ($LinkAggregationGroupName) { $body['link_aggregation_group'] = @{ name = $LinkAggregationGroupName } }
    }

    $queryParams = @{ 'names' = $Name }

    if ($PSCmdlet.ShouldProcess($Name, 'Create subnet')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'subnets' -Body $body -QueryParams $queryParams
    }
}
