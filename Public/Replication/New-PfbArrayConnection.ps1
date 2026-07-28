function New-PfbArrayConnection {
    <#
    .SYNOPSIS
        Creates a new array connection for replication.
    .DESCRIPTION
        The New-PfbArrayConnection cmdlet establishes a new replication connection between the
        local Pure Storage FlashBlade and a remote array. A valid management address and
        connection key from the remote array are required. The connection can be created using
        individual parameters or a single Attributes hashtable. Supports ShouldProcess.

        The individual typed parameters and the raw -Attributes hashtable are mutually
        exclusive: they live in separate parameter sets, so PowerShell rejects a mixed
        invocation at bind time rather than letting -Attributes silently override an
        explicitly supplied value.
    .PARAMETER ManagementAddress
        The management IP address or FQDN of the remote FlashBlade array.
    .PARAMETER ReplicationAddress
        The replication IP address or FQDN of the remote FlashBlade array.
    .PARAMETER ConnectionKey
        The connection key obtained from the remote FlashBlade array.
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
    .PARAMETER Attributes
        A hashtable of connection attributes. Mutually exclusive with the individual typed
        parameters above.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbArrayConnection -ManagementAddress "remote-fb.example.com" -ConnectionKey "1fc6297a-5183-4b7a-8d58-0182af1a2b64"

        Creates an array connection to the remote FlashBlade using its management address and connection key.
    .EXAMPLE
        New-PfbArrayConnection -Attributes @{ management_address = "10.0.2.100"; replication_addresses = @("10.0.3.100"); connection_key = "abc-123-def" }

        Creates an array connection using an Attributes hashtable with explicit replication address.
    .EXAMPLE
        New-PfbArrayConnection -ManagementAddress "fb-dr.example.com" -ReplicationAddress "10.0.4.100" -ConnectionKey "key-456" -WhatIf

        Shows what would happen if the array connection were created without actually creating it.
    .EXAMPLE
        New-PfbArrayConnection -ManagementAddress "remote-fb.example.com" -ConnectionKey "key-456" -Encrypted $true -Remote "remote-fb"

        Creates an encrypted array connection using typed parameters, including a reference to the remote array.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium',
                   DefaultParameterSetName = 'Individual')]
    param(
        [Parameter(ParameterSetName = 'Individual')] [string]$ManagementAddress,
        [Parameter(ParameterSetName = 'Individual')] [string]$ReplicationAddress,
        [Parameter(ParameterSetName = 'Individual')] [string]$ConnectionKey,
        [Parameter(ParameterSetName = 'Individual')] [string]$CaCertificateGroup,
        [Parameter(ParameterSetName = 'Individual')] [Nullable[bool]]$Encrypted,
        [Parameter(ParameterSetName = 'Individual')] [string]$Remote,
        [Parameter(ParameterSetName = 'Individual')] [hashtable]$Throttle,

        [Parameter(ParameterSetName = 'Attributes', Mandatory)]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )
    Assert-PfbConnection -Array ([ref]$Array)

    if ($PSCmdlet.ParameterSetName -eq 'Attributes') {
        $body = $Attributes
    }
    else {
        # Constraint 16: these three were previously bare parameters guarded by truthiness
        # with no parameter set at all, which let -Attributes silently override an explicitly
        # supplied -ManagementAddress/-ReplicationAddress/-ConnectionKey. They now live in the
        # 'Individual' set and are guarded by ContainsKey like every other typed parameter.
        $body = @{}
        if ($PSBoundParameters.ContainsKey('ManagementAddress'))  { $body['management_address'] = $ManagementAddress }
        if ($PSBoundParameters.ContainsKey('ReplicationAddress')) { $body['replication_addresses'] = @($ReplicationAddress) }
        if ($PSBoundParameters.ContainsKey('ConnectionKey'))      { $body['connection_key'] = $ConnectionKey }

        # Constraint 8(a): ca_certificate_group and remote are SCALAR references (item schema
        # is {id, name, resource_type}), so the parameter is [string] and the projection is
        # assigned inline as a name-reference hashtable.
        if ($PSBoundParameters.ContainsKey('CaCertificateGroup')) { $body['ca_certificate_group'] = @{ name = $CaCertificateGroup } }
        if ($PSBoundParameters.ContainsKey('Encrypted'))          { $body['encrypted'] = $Encrypted }
        if ($PSBoundParameters.ContainsKey('Remote'))             { $body['remote'] = @{ name = $Remote } }

        # Constraint 8(c): throttle is a COMPOSITE sub-object (_throttle: default_limit, window,
        # window_limit), not a reference -- it has no `name` property, so it is passed straight
        # through rather than projected into @{ name = ... }.
        if ($PSBoundParameters.ContainsKey('Throttle'))           { $body['throttle'] = $Throttle }
    }

    $target = if ($ManagementAddress) { $ManagementAddress } else { 'array connection' }
    if ($PSCmdlet.ShouldProcess($target, 'Create array connection')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'array-connections' -Body $body
    }
}
