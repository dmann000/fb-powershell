function Update-PfbNetworkInterface {
    <#
    .SYNOPSIS
        Updates a network interface on the FlashBlade.
    .PARAMETER Name
        The name of the network interface to update.
    .PARAMETER Id
        The ID of the network interface to update.
    .PARAMETER Address
        The new IP address.
    .PARAMETER Attributes
        A hashtable of attributes to update.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        Update-PfbNetworkInterface -Name "vir0" -Address "10.0.0.101"
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(ParameterSetName = 'ById', Mandatory)]
        [string]$Id,

        [Parameter()]
        [string]$Address,

        [Parameter()]
        [hashtable]$Attributes,

        [Parameter()]
        [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        if ($Attributes) {
            $body = $Attributes
        }
        else {
            $body = @{}
            if ($Address) { $body['address'] = $Address }
        }

        $queryParams = @{}
        if ($Name) { $queryParams['names'] = $Name }
        if ($Id)   { $queryParams['ids']   = $Id }

        $target = if ($Name) { $Name } else { $Id }

        if ($PSCmdlet.ShouldProcess($target, 'Update network interface')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'network-interfaces' -Body $body -QueryParams $queryParams
        }
    }
}
