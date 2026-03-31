function Update-PfbHardwareConnector {
    <#
    .SYNOPSIS
        Updates a hardware connector on a FlashBlade array.
    .DESCRIPTION
        The Update-PfbHardwareConnector cmdlet modifies attributes of a hardware connector on
        the connected Pure Storage FlashBlade. The connector can be identified by name or ID.
        Supports ShouldProcess for -WhatIf and -Confirm.
    .PARAMETER Name
        The name of the hardware connector to update.
    .PARAMETER Id
        The ID of the hardware connector to update.
    .PARAMETER Attributes
        A hashtable of connector attributes to modify.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbHardwareConnector -Name "CH1.FM1.ETH1" -Attributes @{ port_speed = 40000000000 }

        Updates the port speed on the specified hardware connector.
    .EXAMPLE
        Update-PfbHardwareConnector -Id "10314f42-020d-7080-8013-000ddt400088" -Attributes @{ enabled = $true }

        Enables the hardware connector identified by the specified ID.
    .EXAMPLE
        Update-PfbHardwareConnector -Name "CH1.FM2.ETH1" -Attributes @{ enabled = $false } -WhatIf

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
        if ($PSCmdlet.ShouldProcess($target, 'Update hardware connector')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'hardware-connectors' -Body $Attributes -QueryParams $queryParams
        }
    }
}
