function Update-PfbArrayConnection {
    <#
    .SYNOPSIS
        Updates an existing array connection on a FlashBlade array.
    .DESCRIPTION
        The Update-PfbArrayConnection cmdlet modifies attributes of an existing replication
        connection on the connected Everpure FlashBlade. Common updates include changing
        replication addresses and connection throttling settings. Supports pipeline input and
        ShouldProcess.

        An array connection has no name of its own -- the API resource carries only an id. Its
        human-readable identifier is the REMOTE array's name, so -RemoteName (aliased to -Name
        for compatibility) is how you select one by name.

        The individual typed parameters and the raw -Attributes hashtable are mutually
        exclusive: they live in separate parameter sets, so PowerShell rejects a mixed
        invocation at bind time rather than letting -Attributes silently override an
        explicitly supplied value.
    .PARAMETER RemoteName
        The name of the REMOTE array whose connection to update. Aliased to -Name. Accepts
        pipeline input by property name.
    .PARAMETER Id
        The ID of the array connection to update. Accepts pipeline input by property name, so
        connection objects from Get-PfbArrayConnection can be piped in directly. Legal on its own
        and alongside -RemoteId.
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
        The ID of the REMOTE array whose connection to update. A selector in its own right, and
        combinable with -Id. Mutually exclusive with -RemoteName: the API declares remote_names
        and remote_ids as alternative ways to name the same remote dimension.
    .PARAMETER Attributes
        A hashtable of array connection attributes to modify. Mutually exclusive with the
        individual typed parameters above.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbArrayConnection -RemoteName "FB-B" -Attributes @{ management_address = "10.0.2.101" }

        Updates the management address for the connection to the remote array named "FB-B".
    .EXAMPLE
        Update-PfbArrayConnection -Id "10314f42-020d-7080-8013-000ddt400077" -ReplicationAddresses @("10.0.3.101")

        Updates the replication address for the array connection identified by the specified ID.
    .EXAMPLE
        Update-PfbArrayConnection -RemoteName "FB-B" -ManagementAddress "10.0.2.101" -Encrypted $true

        Updates the management address and encryption setting using typed parameters.
    .EXAMPLE
        Get-PfbArrayConnection | Where-Object type -eq 'async-replication' |
            Update-PfbArrayConnection -Throttle @{ default_limit = 1073741824 }

        Throttles every asynchronous replication connection. The type filter is required, not
        optional: fleet-management connections are managed by the system and reject writes.
    .EXAMPLE
        Update-PfbArrayConnection -RemoteId '10314f42-020d-7080-8013-000133810cd0' `
            -Throttle @{ default_limit = 1073741824 }

        Selects the connection by the remote array's id. PATCH /array-connections documents
        remote_ids as a selector, so no other selector is needed.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium',
                   DefaultParameterSetName = 'ByRemoteNameIndividual')]
    param(
        [Parameter(ParameterSetName = 'ByRemoteNameIndividual', Mandatory, ValueFromPipelineByPropertyName)]
        [Parameter(ParameterSetName = 'ByRemoteNameAttributes',  Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [string]$RemoteName,

        [Parameter(ParameterSetName = 'ByIdIndividual', Mandatory, ValueFromPipelineByPropertyName)]
        [Parameter(ParameterSetName = 'ByIdAttributes',  Mandatory, ValueFromPipelineByPropertyName)]
        [string]$Id,

        [Parameter(ParameterSetName = 'ByRemoteNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [Parameter(ParameterSetName = 'ByRemoteIdIndividual')]
        [string]$ManagementAddress,

        [Parameter(ParameterSetName = 'ByRemoteNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [Parameter(ParameterSetName = 'ByRemoteIdIndividual')]
        [string[]]$ReplicationAddresses,

        [Parameter(ParameterSetName = 'ByRemoteNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [Parameter(ParameterSetName = 'ByRemoteIdIndividual')]
        [string]$CaCertificateGroup,

        [Parameter(ParameterSetName = 'ByRemoteNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [Parameter(ParameterSetName = 'ByRemoteIdIndividual')]
        [Nullable[bool]]$Encrypted,

        [Parameter(ParameterSetName = 'ByRemoteNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [Parameter(ParameterSetName = 'ByRemoteIdIndividual')]
        [string]$Remote,

        [Parameter(ParameterSetName = 'ByRemoteNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [Parameter(ParameterSetName = 'ByRemoteIdIndividual')]
        [hashtable]$Throttle,

        [Parameter(ParameterSetName = 'ByRemoteNameAttributes', Mandatory)]
        [Parameter(ParameterSetName = 'ByIdAttributes',   Mandatory)]
        [Parameter(ParameterSetName = 'ByRemoteIdAttributes', Mandatory)]
        [hashtable]$Attributes,

        # remote_ids is a selector and cannot be combined with remote_names. It is mandatory in
        # its own two sets so it can select alone, and optional in the ById sets so ids +
        # remote_ids stays legal. -Id is deliberately not mirrored into the ByRemoteId sets --
        # see Remove-PfbArrayConnection.ps1 for the binding-pass reason.
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [Parameter(ParameterSetName = 'ByIdAttributes')]
        [Parameter(ParameterSetName = 'ByRemoteIdIndividual', Mandatory)]
        [Parameter(ParameterSetName = 'ByRemoteIdAttributes',  Mandatory)]
        [string]$RemoteId,

        [Parameter()] [PSCustomObject]$Array
    )
    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $queryParams = @{}
        if ($RemoteName) { $queryParams['remote_names'] = $RemoteName }
        if ($Id) { $queryParams['ids'] = $Id }
        if ($PSBoundParameters.ContainsKey('RemoteId')) { $queryParams['remote_ids'] = $RemoteId }

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

        $target = if ($RemoteName) { $RemoteName } elseif ($RemoteId) { $RemoteId } else { $Id }
        if ($PSCmdlet.ShouldProcess($target, 'Update array connection')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'array-connections' -Body $body -QueryParams $queryParams
        }
    }
}
