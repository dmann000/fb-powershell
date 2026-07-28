function Update-PfbNetworkInterfaceConnector {
    <#
    .SYNOPSIS
        Updates a network interface connector on a FlashBlade array.
    .DESCRIPTION
        The Update-PfbNetworkInterfaceConnector cmdlet modifies attributes of an existing
        network interface connector on the connected Everpure FlashBlade. The connector
        can be identified by name or ID. Supports ShouldProcess for -WhatIf and -Confirm.

        The individual typed parameters and the raw -Attributes hashtable are mutually
        exclusive: they live in separate parameter sets, so PowerShell rejects a mixed
        invocation at bind time rather than letting -Attributes silently override an
        explicitly supplied value.
    .PARAMETER Name
        The name of the network interface connector to update.
    .PARAMETER Id
        The ID of the network interface connector to update.
    .PARAMETER LaneSpeed
        Configured speed of each lane in the connector in bits-per-second.
    .PARAMETER LanesPerPort
        Configured number of lanes comprising each port in the connector.
    .PARAMETER PortCount
        Configured number of ports in the connector (1/2/4 for QSFP).
    .PARAMETER PortSpeed
        Configured speed of each port in the connector in bits-per-second.
    .PARAMETER Attributes
        A hashtable of connector attributes to modify, such as enabled state or port speed.
        Mutually exclusive with the individual typed parameters above.
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
    .EXAMPLE
        Update-PfbNetworkInterfaceConnector -Name "CH1.FM1.ETH1" -LaneSpeed 10000000000 -LanesPerPort 4

        Sets the lane speed and lanes-per-port using typed parameters.
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
        $target = if ($Name) { $Name } else { $Id }

        if ($PSCmdlet.ParameterSetName -like '*Attributes') {
            $body = $Attributes
        }
        else {
            # EVERY value-carrying parameter is guarded by $PSBoundParameters.ContainsKey,
            # never by truthiness -- see Update-PfbAdmin.ps1 for the full rationale. All four
            # fields here are integers, so an explicit 0 must reach the wire (constraint 2).
            $body = @{}
            if ($PSBoundParameters.ContainsKey('LaneSpeed'))     { $body['lane_speed']     = $LaneSpeed }
            if ($PSBoundParameters.ContainsKey('LanesPerPort'))  { $body['lanes_per_port']  = $LanesPerPort }
            if ($PSBoundParameters.ContainsKey('PortCount'))     { $body['port_count']     = $PortCount }
            if ($PSBoundParameters.ContainsKey('PortSpeed'))     { $body['port_speed']     = $PortSpeed }
        }

        if ($PSCmdlet.ShouldProcess($target, 'Update network interface connector')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'network-interfaces/connectors' -Body $body -QueryParams $queryParams
        }
    }
}
