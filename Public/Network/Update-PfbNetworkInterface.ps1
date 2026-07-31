function Update-PfbNetworkInterface {
    <#
    .SYNOPSIS
        Updates a network interface on the FlashBlade.
    .DESCRIPTION
        The Update-PfbNetworkInterface cmdlet modifies attributes of a network interface on
        the connected Everpure FlashBlade. The target interface can be identified by name or
        ID. Supports pipeline input and ShouldProcess for confirmation prompts.

        The individual typed parameters and the raw -Attributes hashtable are mutually
        exclusive: they live in separate parameter sets, so PowerShell rejects a mixed
        invocation at bind time rather than letting -Attributes silently override an
        explicitly supplied value.
    .PARAMETER Name
        The name of the network interface to update.
    .PARAMETER Id
        The ID of the network interface to update.
    .PARAMETER Address
        The new IPv4 or IPv6 address to associate with the network interface.
    .PARAMETER AttachedServers
        Servers to be associated with the network interface for data ingress. Pass an empty
        array to detach the interface from all servers.
    .PARAMETER RdmaEnabled
        If `$true`, RDMA is enabled on the network interface. Only supported on interfaces
        whose services include `data`.
    .PARAMETER Services
        Services and protocols that are enabled on the interface.
    .PARAMETER Attributes
        A hashtable of attributes to update. Mutually exclusive with the individual typed
        parameters above.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        Update-PfbNetworkInterface -Name "vir0" -Address "10.0.0.101"

        Updates the address of "vir0" using a typed parameter.
    .EXAMPLE
        Update-PfbNetworkInterface -Name "vir0" -AttachedServers "CH1.FM1", "CH1.FM2"

        Attaches "vir0" to two servers for data ingress.
    .EXAMPLE
        Update-PfbNetworkInterface -Name "vir0" -Attributes @{ address = "10.0.0.101" }

        Updates the address of "vir0" using the raw -Attributes hashtable.
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
        [string]$Address,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string[]]$AttachedServers,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [Nullable[bool]]$RdmaEnabled,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string[]]$Services,

        [Parameter(ParameterSetName = 'ByNameAttributes', Mandatory)]
        [Parameter(ParameterSetName = 'ByIdAttributes',   Mandatory)]
        [hashtable]$Attributes,

        [Parameter()]
        [PSCustomObject]$Array
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
            # never by truthiness -- see Update-PfbAdmin.ps1 for the full rationale. -Address
            # previously used `if ($Address)`, which silently dropped an explicit
            # -Address '' and (combined with living outside any parameter set) let
            # -Attributes silently override it -- the exact silent-override failure this
            # issue exists to eliminate.
            $body = @{}
            if ($PSBoundParameters.ContainsKey('Address')) { $body['address'] = $Address }

            # Constraint 8(b): attached_servers is an ARRAY OF REFERENCES (item schema is
            # {id, name}), so the parameter is [string[]] and the projection is assigned
            # INLINE -- constraint 7 forbids an intermediate local.
            if ($PSBoundParameters.ContainsKey('AttachedServers')) {
                $body['attached_servers'] = @($AttachedServers | ForEach-Object { @{ name = $_ } })
            }

            if ($PSBoundParameters.ContainsKey('RdmaEnabled')) { $body['rdma_enabled'] = $RdmaEnabled }
            if ($PSBoundParameters.ContainsKey('Services'))    { $body['services']     = @($Services) }
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
