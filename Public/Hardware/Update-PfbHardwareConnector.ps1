function Update-PfbHardwareConnector {
    <#
    .SYNOPSIS
        Updates a hardware connector on a FlashBlade array.
    .DESCRIPTION
        The Update-PfbHardwareConnector cmdlet modifies attributes of a hardware connector on
        the connected Everpure FlashBlade. The connector can be identified by name or ID.
        Supports ShouldProcess for -WhatIf and -Confirm.

        The individual typed parameters and the raw -Attributes hashtable are mutually
        exclusive: they live in separate parameter sets, so PowerShell rejects a mixed
        invocation at bind time rather than letting -Attributes silently override an
        explicitly supplied value.
    .PARAMETER Name
        The name of the hardware connector to update. Accepts pipeline input by property name.
    .PARAMETER Id
        The ID of the hardware connector to update.
    .PARAMETER LaneSpeed
        Configured speed of each lane in the connector in bits-per-second.
    .PARAMETER LanesPerPort
        Configured number of lanes comprising each port in the connector.
    .PARAMETER PortCount
        Configured number of ports in the connector (1/2/4 for QSFP).
    .PARAMETER PortSpeed
        Configured speed of each port in the connector in bits-per-second.
    .PARAMETER Attributes
        A hashtable of connector attributes to modify. Mutually exclusive with the individual
        typed parameters above.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbHardwareConnector -Name "CH1.FM1.ETH1" -PortSpeed 40000000000

        Updates the port speed on the specified hardware connector using a typed parameter.
    .EXAMPLE
        Update-PfbHardwareConnector -Id "10314f42-020d-7080-8013-000ddt400088" -Attributes @{ enabled = $true }

        Enables the hardware connector identified by the specified ID.
    .EXAMPLE
        Update-PfbHardwareConnector -Name "CH1.FM2.ETH1" -Attributes @{ enabled = $false } -WhatIf

        Shows what would happen without applying the change.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium',
                   DefaultParameterSetName = 'ByNameIndividual')]
    param(
        [Parameter(ParameterSetName = 'ByNameIndividual', Mandatory, ValueFromPipelineByPropertyName)]
        [Parameter(ParameterSetName = 'ByNameAttributes',  Mandatory, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(ParameterSetName = 'ByIdIndividual', Mandatory)]
        [Parameter(ParameterSetName = 'ByIdAttributes',  Mandatory)]
        [string]$Id,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [long]$LaneSpeed,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [long]$LanesPerPort,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [long]$PortCount,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [long]$PortSpeed,

        [Parameter(ParameterSetName = 'ByNameAttributes', Mandatory)]
        [Parameter(ParameterSetName = 'ByIdAttributes',   Mandatory)]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )
    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }
    process {
        $queryParams = @{}
        if ($Name) { $queryParams['names'] = $Name }
        if ($Id)   { $queryParams['ids']   = $Id }

        if ($PSCmdlet.ParameterSetName -like '*Attributes') {
            $body = $Attributes
        }
        else {
            # Every value-carrying parameter is guarded by ContainsKey, never by truthiness --
            # see the canonical explanation in Update-PfbAdmin.ps1. All four fields here are
            # integers, so each needs an explicit-0 test (constraint 2).
            $body = @{}
            if ($PSBoundParameters.ContainsKey('LaneSpeed'))    { $body['lane_speed']     = $LaneSpeed }
            if ($PSBoundParameters.ContainsKey('LanesPerPort')) { $body['lanes_per_port']  = $LanesPerPort }
            if ($PSBoundParameters.ContainsKey('PortCount'))    { $body['port_count']      = $PortCount }
            if ($PSBoundParameters.ContainsKey('PortSpeed'))    { $body['port_speed']      = $PortSpeed }
        }

        $target = if ($Name) { $Name } else { $Id }
        if ($PSCmdlet.ShouldProcess($target, 'Update hardware connector')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'hardware-connectors' -Body $body -QueryParams $queryParams
        }
    }
}
