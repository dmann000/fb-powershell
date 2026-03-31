function Update-PfbNetworkInterfaceConnector {
    <#
    .SYNOPSIS
        Updates a network interface connector on a FlashBlade array.
    .DESCRIPTION
        The Update-PfbNetworkInterfaceConnector cmdlet modifies attributes of an existing
        network interface connector on the connected Pure Storage FlashBlade. The connector
        can be identified by name or ID. Supports ShouldProcess for -WhatIf and -Confirm.
    .PARAMETER Name
        The name of the network interface connector to update.
    .PARAMETER Id
        The ID of the network interface connector to update.
    .PARAMETER Attributes
        A hashtable of connector attributes to modify, such as enabled state or port speed.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbNetworkInterfaceConnector -Name "CH1.FM1.ETH1" -Attributes @{ enabled = $true }

        Enables the specified network interface connector.
    .EXAMPLE
        Update-PfbNetworkInterfaceConnector -Id "10314f42-020d-7080-8013-000ddt400012" -Attributes @{ enabled = $false }

        Disables the network interface connector identified by the specified ID.
    .EXAMPLE
        Update-PfbNetworkInterfaceConnector -Name "CH1.FM1.ETH2" -Attributes @{ enabled = $true } -WhatIf

        Shows what would happen without applying the change.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, ValueFromPipelineByPropertyName)] [string]$Name,
        [Parameter(ParameterSetName = 'ById', Mandatory)] [string]$Id,
        [Parameter(Mandatory)] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )
    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }
    process {
        $queryParams = @{}
        if ($Name) { $queryParams['names'] = $Name }
        if ($Id)   { $queryParams['ids']   = $Id }
        $target = if ($Name) { $Name } else { $Id }
        if ($PSCmdlet.ShouldProcess($target, 'Update network interface connector')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'network-interfaces/connectors' -Body $Attributes -QueryParams $queryParams
        }
    }
}
