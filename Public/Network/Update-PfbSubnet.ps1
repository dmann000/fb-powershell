function Update-PfbSubnet {
    <#
    .SYNOPSIS
        Updates a subnet on the FlashBlade.
    .DESCRIPTION
        The Update-PfbSubnet cmdlet modifies attributes of a subnet on the connected Everpure
        FlashBlade. The target subnet can be identified by name or ID. Supports pipeline
        input and ShouldProcess for confirmation prompts.

        The individual typed parameters and the raw -Attributes hashtable are mutually
        exclusive: they live in separate parameter sets, so PowerShell rejects a mixed
        invocation at bind time rather than letting -Attributes silently override an
        explicitly supplied value.
    .PARAMETER Name
        The name of the subnet to update.
    .PARAMETER Id
        The ID of the subnet to update.
    .PARAMETER Prefix
        The IPv4 or IPv6 address to be associated with the subnet.
    .PARAMETER Gateway
        The IPv4 or IPv6 address of the gateway through which the subnet communicates with the
        network.
    .PARAMETER Mtu
        Maximum message transfer unit (packet) size for the subnet in bytes.
    .PARAMETER LinkAggregationGroup
        A reference to the associated LAG.
    .PARAMETER Vlan
        The VLAN ID.
    .PARAMETER Attributes
        A hashtable of attributes to update. Mutually exclusive with the individual typed
        parameters above.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        Update-PfbSubnet -Name "subnet1" -Gateway "10.0.0.254"

        Updates the gateway of "subnet1" using a typed parameter.
    .EXAMPLE
        Update-PfbSubnet -Name "subnet1" -Vlan 100 -LinkAggregationGroup "lag1"

        Sets the VLAN ID and link aggregation group of "subnet1".
    .EXAMPLE
        Update-PfbSubnet -Name "subnet1" -Attributes @{ mtu = 9000 }

        Updates the MTU of "subnet1" using the raw -Attributes hashtable.
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
        [string]$Prefix,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$Gateway,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [int]$Mtu,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$LinkAggregationGroup,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [int]$Vlan,

        [Parameter(ParameterSetName = 'ByNameAttributes', Mandatory)]
        [Parameter(ParameterSetName = 'ByIdAttributes',   Mandatory)]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        if ($PSCmdlet.ParameterSetName -like '*Attributes') {
            $body = $Attributes
        }
        else {
            # EVERY value-carrying parameter is guarded by $PSBoundParameters.ContainsKey,
            # never by truthiness -- see Update-PfbAdmin.ps1 for the full rationale. -Mtu
            # previously used `if ($Mtu -gt 0)`, which could never send an explicit 0 (and,
            # combined with living outside any parameter set, let -Attributes silently
            # override it -- the exact silent-override failure this issue exists to
            # eliminate).
            $body = @{}
            if ($PSBoundParameters.ContainsKey('Prefix'))  { $body['prefix']  = $Prefix }
            if ($PSBoundParameters.ContainsKey('Gateway')) { $body['gateway'] = $Gateway }
            if ($PSBoundParameters.ContainsKey('Mtu'))     { $body['mtu']     = $Mtu }

            # Constraint 8(a): link_aggregation_group is a SCALAR reference (item schema is
            # {id, name, resource_type}), so the parameter is [string] and the projection is
            # assigned INLINE as a name-reference hashtable.
            if ($PSBoundParameters.ContainsKey('LinkAggregationGroup')) {
                $body['link_aggregation_group'] = @{ name = $LinkAggregationGroup }
            }

            if ($PSBoundParameters.ContainsKey('Vlan')) { $body['vlan'] = $Vlan }
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
