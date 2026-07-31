function Update-PfbTlsPolicy {
    <#
    .SYNOPSIS
        Updates an existing TLS policy on a FlashBlade array.
    .DESCRIPTION
        The Update-PfbTlsPolicy cmdlet modifies attributes of an existing TLS policy on the
        connected Everpure FlashBlade. The policy can be identified by name or ID.

        The individual typed parameters and the raw -Attributes hashtable are mutually
        exclusive: they live in separate parameter sets, so PowerShell rejects a mixed
        invocation at bind time rather than letting -Attributes silently override an
        explicitly supplied value.
    .PARAMETER Name
        The name of the TLS policy to update. Accepts pipeline input by property name.
    .PARAMETER Id
        The ID of the TLS policy to update.
    .PARAMETER ApplianceCertificate
        A reference to a certificate that will be presented as the server certificate in
        TLS negotiations with any clients that connect to appliance network addresses.
    .PARAMETER ClientCertificatesRequired
        If true, then all clients negotiating TLS connections with network interfaces to
        which this policy applies will be required to provide their client certificate.
    .PARAMETER DisabledTlsCiphers
        If specified, disables the specific TLS ciphers.
    .PARAMETER Enabled
        If true, the policy is enabled.
    .PARAMETER EnabledTlsCiphers
        If specified, enables only the specified TLS ciphers.
    .PARAMETER Location
        Reference to the array where the policy is defined.
    .PARAMETER MinTlsVersion
        The minimum TLS version that will be allowed for inbound connections on IPs to
        which this policy applies.
    .PARAMETER NewName
        A new name for the TLS policy.
    .PARAMETER TrustedClientCertificateAuthority
        A reference to a certificate or certificate group.
    .PARAMETER VerifyClientCertificateTrust
        If true, then any certificate presented by a client in TLS negotiation will undergo
        strict trust verification using the certificate(s) referenced by
        -TrustedClientCertificateAuthority.
    .PARAMETER Attributes
        A hashtable of TLS policy attributes to modify. Mutually exclusive with the
        individual typed parameters above.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbTlsPolicy -Name "tls-strict" -MinTlsVersion "1.3"

        Updates the minimum TLS version for the specified policy using a typed parameter.
    .EXAMPLE
        Update-PfbTlsPolicy -Id "10314f42-020d-7080-8013-000ddt400012" -Attributes @{ min_tls_version = "1.2" }

        Updates the TLS policy by ID.
    .EXAMPLE
        Update-PfbTlsPolicy -Name "tls-strict" -Attributes @{ min_tls_version = "1.3" } -WhatIf

        Shows what would happen without actually updating the policy.
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
        [string]$ApplianceCertificate,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [Nullable[bool]]$ClientCertificatesRequired,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string[]]$DisabledTlsCiphers,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [Nullable[bool]]$Enabled,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string[]]$EnabledTlsCiphers,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$Location,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$MinTlsVersion,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$NewName,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$TrustedClientCertificateAuthority,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [Nullable[bool]]$VerifyClientCertificateTrust,

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

        if ($PSCmdlet.ParameterSetName -like '*Attributes') {
            $body = $Attributes
        }
        else {
            $body = @{}
            if ($PSBoundParameters.ContainsKey('ApplianceCertificate')) { $body['appliance_certificate']  = @{ name = $ApplianceCertificate } }
            if ($PSBoundParameters.ContainsKey('ClientCertificatesRequired')) { $body['client_certificates_required'] = $ClientCertificatesRequired }
            if ($PSBoundParameters.ContainsKey('DisabledTlsCiphers')) { $body['disabled_tls_ciphers'] = @($DisabledTlsCiphers) }
            if ($PSBoundParameters.ContainsKey('Enabled'))             { $body['enabled']              = $Enabled }
            if ($PSBoundParameters.ContainsKey('EnabledTlsCiphers'))   { $body['enabled_tls_ciphers']   = @($EnabledTlsCiphers) }
            if ($PSBoundParameters.ContainsKey('Location'))            { $body['location']              = @{ name = $Location } }
            if ($PSBoundParameters.ContainsKey('MinTlsVersion'))       { $body['min_tls_version']        = $MinTlsVersion }
            if ($PSBoundParameters.ContainsKey('NewName'))             { $body['name']                    = $NewName }
            if ($PSBoundParameters.ContainsKey('TrustedClientCertificateAuthority')) {
                $body['trusted_client_certificate_authority'] = @{ name = $TrustedClientCertificateAuthority }
            }
            if ($PSBoundParameters.ContainsKey('VerifyClientCertificateTrust')) { $body['verify_client_certificate_trust'] = $VerifyClientCertificateTrust }
        }

        $target = if ($Name) { $Name } else { $Id }
        if ($PSCmdlet.ShouldProcess($target, 'Update TLS policy')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'tls-policies' -Body $body -QueryParams $queryParams
        }
    }
}
