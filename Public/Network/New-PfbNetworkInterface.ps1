function New-PfbNetworkInterface {
    <#
    .SYNOPSIS
        Creates a new network interface on the FlashBlade.
    .PARAMETER Name
        The name of the network interface to create.
    .PARAMETER Address
        The IP address for the interface.
    .PARAMETER Services
        The services this interface supports (e.g., 'data', 'management').
    .PARAMETER SubnetName
        The subnet to associate with.
    .PARAMETER Attributes
        A hashtable of additional attributes.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        New-PfbNetworkInterface -Name "vir0" -Address "10.0.0.100" -Services "data" -SubnetName "subnet1"
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter()]
        [string]$Address,

        [Parameter()]
        [string]$Services,

        [Parameter()]
        [string]$SubnetName,

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
        if ($Address)    { $body['address'] = $Address }
        if ($Services)   { $body['services'] = @($Services) }
        if ($SubnetName) { $body['subnet'] = @{ name = $SubnetName } }
    }

    $queryParams = @{ 'names' = $Name }

    if ($PSCmdlet.ShouldProcess($Name, 'Create network interface')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'network-interfaces' -Body $body -QueryParams $queryParams
    }
}
