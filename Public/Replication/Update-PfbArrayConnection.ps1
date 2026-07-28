function Update-PfbArrayConnection {
    <#
    .SYNOPSIS
        Updates an existing array connection on a FlashBlade array.
    .DESCRIPTION
        The Update-PfbArrayConnection cmdlet modifies attributes of an existing replication
        connection on the connected Pure Storage FlashBlade. The target connection can be
        identified by name or ID. Common updates include changing replication addresses and
        connection throttling settings. Supports pipeline input and ShouldProcess.

        The individual typed parameters and the raw -Attributes hashtable are mutually
        exclusive: they live in separate parameter sets, so PowerShell rejects a mixed
        invocation at bind time rather than letting -Attributes silently override an
        explicitly supplied value.
    .PARAMETER Name
        The name of the array connection to update. Accepts pipeline input by property name.
    .PARAMETER Id
        The ID of the array connection to update.
    .PARAMETER ManagementAddress
        Management address of the target array.
    .PARAMETER ReplicationAddresses
        IP addresses and/or FQDNs of the target arrays.
    .PARAMETER CaCertificateGroup
        The group of CA certificates that can be used, in addition to well-known Certificate
        Authority certificates, in order to establish a secure connection to the target array.
    .PARAMETER Encrypted
        If this is set to $true, then all customer data replicated over the connection will be
        sent over an encrypted connection using TLS, or will not be sent if a secure connection
        cannot be established.
    .PARAMETER Remote
        The remote array.
    .PARAMETER Throttle
        The bandwidth throttling for the array connection, as a hashtable -- for example
        @{ default_limit = 1073741824 }.
    .PARAMETER RemoteId
        Performs the operation on the array connection with the specified remote array ID.
    .PARAMETER RemoteName
        Performs the operation on the array connection with the specified remote array name.
    .PARAMETER Attributes
        A hashtable of array connection attributes to modify. Mutually exclusive with the
        individual typed parameters above.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbArrayConnection -Name "remote-fb-dc2" -Attributes @{ management_address = "10.0.2.101" }

        Updates the management address for the array connection named "remote-fb-dc2".
    .EXAMPLE
        Update-PfbArrayConnection -Name "remote-fb-dr" -Attributes @{ replication_addresses = @("10.0.3.101") }

        Updates the replication address for the "remote-fb-dr" array connection.
    .EXAMPLE
        Update-PfbArrayConnection -Id "10314f42-020d-7080-8013-000ddt400077" -Attributes @{ status = "connected" }

        Updates the status of the array connection identified by the specified ID.
    .EXAMPLE
        Update-PfbArrayConnection -Name "remote-fb-dc2" -ManagementAddress "10.0.2.101" -Encrypted $true -RemoteId "remote-1"

        Updates the management address and encryption setting for "remote-fb-dc2" using typed
        parameters, filtered to the connection whose remote array ID is "remote-1".
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
        [string]$ManagementAddress,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string[]]$ReplicationAddresses,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$CaCertificateGroup,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [Nullable[bool]]$Encrypted,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$Remote,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [hashtable]$Throttle,

        [Parameter(ParameterSetName = 'ByNameAttributes', Mandatory)]
        [Parameter(ParameterSetName = 'ByIdAttributes',   Mandatory)]
        [hashtable]$Attributes,

        # Constraint 17: remote_ids/remote_names are orthogonal query filters, not body fields,
        # so they are declared bare rather than added to the Individual parameter sets -- they
        # must stay usable alongside -Attributes.
        [Parameter()] [string]$RemoteId,
        [Parameter()] [string]$RemoteName,

        [Parameter()] [PSCustomObject]$Array
    )
    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $queryParams = @{}
        if ($Name) { $queryParams['names'] = $Name }
        if ($Id) { $queryParams['ids'] = $Id }
        if ($PSBoundParameters.ContainsKey('RemoteId'))   { $queryParams['remote_ids']   = $RemoteId }
        if ($PSBoundParameters.ContainsKey('RemoteName')) { $queryParams['remote_names'] = $RemoteName }

        if ($PSCmdlet.ParameterSetName -like '*Attributes') {
            $body = $Attributes
        }
        else {
            $body = @{}
            if ($PSBoundParameters.ContainsKey('ManagementAddress')) { $body['management_address'] = $ManagementAddress }
            if ($PSBoundParameters.ContainsKey('ReplicationAddresses')) { $body['replication_addresses'] = @($ReplicationAddresses) }

            # Constraint 8(a): ca_certificate_group and remote are SCALAR references (item
            # schema is {id, name, resource_type}), so the parameter is [string] and the
            # projection is assigned inline as a name-reference hashtable.
            if ($PSBoundParameters.ContainsKey('CaCertificateGroup')) { $body['ca_certificate_group'] = @{ name = $CaCertificateGroup } }
            if ($PSBoundParameters.ContainsKey('Encrypted'))          { $body['encrypted'] = $Encrypted }
            if ($PSBoundParameters.ContainsKey('Remote'))             { $body['remote'] = @{ name = $Remote } }

            # Constraint 8(c): throttle is a COMPOSITE sub-object (_throttle: default_limit,
            # window, window_limit), not a reference -- it has no `name` property, so it is
            # passed straight through rather than projected into @{ name = ... }.
            if ($PSBoundParameters.ContainsKey('Throttle'))           { $body['throttle'] = $Throttle }
        }

        $target = if ($Name) { $Name } else { $Id }
        if ($PSCmdlet.ShouldProcess($target, 'Update array connection')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'array-connections' -Body $body -QueryParams $queryParams
        }
    }
}
