function Update-PfbSubnet {
    <#
    .SYNOPSIS
        Updates a subnet on the FlashBlade.
    .PARAMETER Name
        The name of the subnet to update.
    .PARAMETER Id
        The ID of the subnet to update.
    .PARAMETER Prefix
        The new subnet prefix.
    .PARAMETER Gateway
        The new gateway IP address.
    .PARAMETER Mtu
        The new MTU size.
    .PARAMETER Attributes
        A hashtable of attributes to update.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        Update-PfbSubnet -Name "subnet1" -Gateway "10.0.0.254"
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(ParameterSetName = 'ById', Mandatory)]
        [string]$Id,

        [Parameter()] [string]$Prefix,
        [Parameter()] [string]$Gateway,
        [Parameter()] [int]$Mtu,
        [Parameter()] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        if ($Attributes) { $body = $Attributes }
        else {
            $body = @{}
            if ($Prefix)     { $body['prefix'] = $Prefix }
            if ($Gateway)    { $body['gateway'] = $Gateway }
            if ($Mtu -gt 0)  { $body['mtu'] = $Mtu }
        }

        $queryParams = @{}
        if ($Name) { $queryParams['names'] = $Name }
        if ($Id)   { $queryParams['ids']   = $Id }
        $target = if ($Name) { $Name } else { $Id }

        if ($PSCmdlet.ShouldProcess($target, 'Update subnet')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'subnets' -Body $body -QueryParams $queryParams
        }
    }
}
