function Update-PfbKmip {
    <#
    .SYNOPSIS
        Updates KMIP server configuration on the FlashBlade.
    .DESCRIPTION
        The Update-PfbKmip cmdlet modifies the Key Management Interoperability Protocol (KMIP)
        server configuration on the connected Pure Storage FlashBlade. Properties that can be
        updated include the KMIP server URI, certificate group, and connection settings.
    .PARAMETER Name
        The name of the KMIP server configuration to update.
    .PARAMETER Id
        The ID of the KMIP server configuration to update.
    .PARAMETER CaCertificate
        The name of the CA certificate used to validate the authenticity of the configured
        KMIP servers.
    .PARAMETER CaCertificateGroup
        The name of the certificate group containing CA certificates that can be used to
        validate the authenticity of the configured KMIP servers.
    .PARAMETER Uris
        The list of URIs for the configured KMIP servers, in the format
        [protocol://]hostname:port.
    .PARAMETER Attributes
        A hashtable of properties to update on the KMIP configuration. Mutually exclusive
        with the individual typed parameters above.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbKmip -Name 'kmip-server-1' -Uris 'kmip.example.com:5696'

        Updates the KMIP server URI using a typed parameter.
    .EXAMPLE
        Update-PfbKmip -Name 'kmip-server-1' -CaCertificateGroup 'kmip-certs'

        Updates the CA certificate group used by the KMIP server.
    .EXAMPLE
        Update-PfbKmip -Name 'kmip-server-1' -Attributes @{ uris = @('kmip.example.com:5696') } -Confirm:$false

        Updates the KMIP configuration without prompting for confirmation.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium',
                   DefaultParameterSetName = 'ByNameIndividual')]
    param(
        [Parameter(ParameterSetName = 'ByNameIndividual', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Parameter(ParameterSetName = 'ByNameAttributes',  Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(ParameterSetName = 'ByIdIndividual', Mandatory)]
        [Parameter(ParameterSetName = 'ByIdAttributes',  Mandatory)]
        [string]$Id,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$CaCertificate,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$CaCertificateGroup,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string[]]$Uris,

        [Parameter(ParameterSetName = 'ByNameAttributes', Mandatory)]
        [Parameter(ParameterSetName = 'ByIdAttributes',   Mandatory)]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $target = if ($Name) { $Name } else { $Id }
        $queryParams = @{}
        if ($Name) { $queryParams['names'] = $Name }
        if ($Id)   { $queryParams['ids']   = $Id }

        if ($PSCmdlet.ParameterSetName -like '*Attributes') {
            $body = $Attributes
        }
        else {
            # Every value-carrying parameter is guarded by ContainsKey, never truthiness -- see
            # the canonical explanation in Update-PfbAdmin.ps1.
            $body = @{}

            # Constraint 8(a): ca_certificate/ca_certificate_group are SCALAR REFERENCES (item
            # schema is {id, name, resource_type}), so the parameter is [string] taking the
            # name and the projection is assigned INLINE -- constraint 7 forbids a local.
            if ($PSBoundParameters.ContainsKey('CaCertificate'))      { $body['ca_certificate']       = @{ name = $CaCertificate } }
            if ($PSBoundParameters.ContainsKey('CaCertificateGroup')) { $body['ca_certificate_group'] = @{ name = $CaCertificateGroup } }

            # uris is a plain string array, not a reference -- no name-projection needed.
            if ($PSBoundParameters.ContainsKey('Uris')) { $body['uris'] = @($Uris) }
        }

        if ($PSCmdlet.ShouldProcess($target, 'Update KMIP configuration')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'kmip' -Body $body -QueryParams $queryParams
        }
    }
}
