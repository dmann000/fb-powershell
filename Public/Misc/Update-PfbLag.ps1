function Update-PfbLag {
    <#
    .SYNOPSIS
        Updates a link aggregation group (LAG) on the FlashBlade.
    .DESCRIPTION
        Modifies the configuration of an existing LAG on the FlashBlade, such as
        adding or removing ports or changing LACP settings.
    .PARAMETER Name
        The name of the LAG to update.
    .PARAMETER Id
        The ID of the LAG to update.
    .PARAMETER AddPorts
        Names of the ports to add to the LAG.
    .PARAMETER Ports
        Names of the ports that make up the LAG, replacing the existing port list.
    .PARAMETER RemovePorts
        Names of the ports to remove from the LAG.
    .PARAMETER Attributes
        A hashtable of LAG attributes to update, such as ports or LACP mode. Mutually
        exclusive with the individual typed parameters above.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        Update-PfbLag -Name "lag1" -Ports "CH1.FM1.ETH1", "CH1.FM1.ETH3"

        Updates the ports assigned to the LAG named 'lag1' using typed parameters.
    .EXAMPLE
        Update-PfbLag -Name "lag1" -Attributes @{ lacp_mode = "passive" }

        Changes the LACP mode of 'lag1' to passive.
    .EXAMPLE
        Update-PfbLag -Id "10314f42-020d-7080-8013-000ddt400012" -AddPorts "CH1.FM1.ETH5"

        Adds a port to the LAG with the specified ID.
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
        [string[]]$AddPorts,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string[]]$Ports,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string[]]$RemovePorts,

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
        if ($Id) { $queryParams['ids'] = $Id }
        $target = if ($Name) { $Name } else { $Id }

        if ($PSCmdlet.ParameterSetName -like '*Attributes') {
            $body = $Attributes
        }
        else {
            # Constraint 8(b): add_ports/ports/remove_ports are ARRAYS OF REFERENCES (item
            # schema is {id, name, resource_type}), so each parameter is [string[]] and the
            # projection is assigned INLINE -- constraint 7 forbids an intermediate local.
            $body = @{}
            if ($PSBoundParameters.ContainsKey('AddPorts'))    { $body['add_ports']    = @($AddPorts | ForEach-Object { @{ name = $_ } }) }
            if ($PSBoundParameters.ContainsKey('Ports'))       { $body['ports']        = @($Ports | ForEach-Object { @{ name = $_ } }) }
            if ($PSBoundParameters.ContainsKey('RemovePorts')) { $body['remove_ports'] = @($RemovePorts | ForEach-Object { @{ name = $_ } }) }
        }

        if ($PSCmdlet.ShouldProcess($target, 'Update LAG')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'link-aggregation-groups' -Body $body -QueryParams $queryParams
        }
    }
}
