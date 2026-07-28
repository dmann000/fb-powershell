function Update-PfbCertificate {
    <#
    .SYNOPSIS
        Updates an existing SSL/TLS certificate on an Everpure FlashBlade.
    .DESCRIPTION
        The Update-PfbCertificate cmdlet modifies an existing certificate on the FlashBlade.
        The certificate can be identified by name or by ID. Use the individual typed
        parameters for a specific certificate field, or the Attributes hashtable to supply
        several updated certificate properties at once, such as a renewed certificate body
        or a new private key. This cmdlet supports pipeline input by property name and the
        ShouldProcess pattern.

        The individual typed parameters and the raw -Attributes hashtable are mutually
        exclusive: they live in separate parameter sets, so PowerShell rejects a mixed
        invocation at bind time rather than letting -Attributes silently override an
        explicitly supplied value. -GenerateNewKey is a query parameter and is orthogonal
        to the body, so it can be combined freely with either.
    .PARAMETER Name
        The name of the certificate to update. Accepts pipeline input by property name.
    .PARAMETER Id
        The ID of the certificate to update.
    .PARAMETER GenerateNewKey
        If set to $true, a new private key is generated when generating a new certificate
        with the specified attributes. This may not be set to $true when importing a
        certificate and private key, and may not be set to $false when generating a new
        self-signed certificate to replace a certificate that was imported. Default is
        $false. Sent as the 'generate_new_key' query parameter.
    .PARAMETER Certificate
        The text of the certificate.
    .PARAMETER CertificateType
        The type of certificate. Certificates of type 'appliance' are used by the array to
        verify its identity to clients. Certificates of type 'external' are used by the
        array to identify external servers to which it is configured to communicate. This
        field may only be specified at certificate creation time.
    .PARAMETER CommonName
        The common name field listed in the certificate.
    .PARAMETER Country
        The country field listed in the certificate.
    .PARAMETER Days
        The number of days that the self-signed certificate is valid.
    .PARAMETER Email
        The email field listed in the certificate.
    .PARAMETER IntermediateCertificate
        Intermediate certificate chains.
    .PARAMETER KeyAlgorithm
        The key algorithm used to generate the certificate.
    .PARAMETER KeySize
        The size (in bits) of the private key for the certificate.
    .PARAMETER Locality
        The locality field listed in the certificate.
    .PARAMETER Organization
        The organization field listed in the certificate.
    .PARAMETER OrganizationalUnit
        The organizational unit field listed in the certificate.
    .PARAMETER Passphrase
        The passphrase used to encrypt -PrivateKey.
    .PARAMETER PrivateKey
        The text of the private key.
    .PARAMETER State
        The state/province field listed in the certificate.
    .PARAMETER SubjectAlternativeNames
        The alternative names that are secured by this certificate.
    .PARAMETER Attributes
        A hashtable containing the updated certificate data. Mutually exclusive with the
        individual typed parameters above.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbCertificate -Name 'web-cert' -Certificate $newCertPem -PrivateKey $newKeyPem

        Updates the certificate named 'web-cert' with a renewed certificate and private key
        using typed parameters.
    .EXAMPLE
        Update-PfbCertificate -Id '10314f42-020d-7080-8013-000ddt400090' -Attributes @{ certificate = $certPem }

        Updates a certificate identified by its ID with a new certificate body.
    .EXAMPLE
        Get-PfbCertificate -Name 'web-cert' | Update-PfbCertificate -Attributes @{ intermediate_certificate = $chainPem }

        Pipes a certificate object to update its intermediate certificate chain.
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

        # Constraint 17: generate_new_key is a QUERY parameter, orthogonal to the request
        # body, so it is declared bare rather than scoped to the *Individual sets. Placing
        # it there would make `-Attributes ... -GenerateNewKey` fail with
        # AmbiguousParameterSet for no reason -- it has nothing to do with the body.
        [Parameter()]
        [Nullable[bool]]$GenerateNewKey,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$Certificate,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [ValidateSet('appliance', 'external')]
        [string]$CertificateType,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$CommonName,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$Country,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [int]$Days,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$Email,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$IntermediateCertificate,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$KeyAlgorithm,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [int]$KeySize,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$Locality,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$Organization,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$OrganizationalUnit,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$Passphrase,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$PrivateKey,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$State,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string[]]$SubjectAlternativeNames,

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
        if ($PSBoundParameters.ContainsKey('GenerateNewKey')) { $queryParams['generate_new_key'] = $GenerateNewKey }

        if ($PSCmdlet.ParameterSetName -like '*Attributes') {
            $body = $Attributes
        }
        else {
            # EVERY value-carrying parameter is guarded with $PSBoundParameters.ContainsKey,
            # never truthiness -- an integer field (Days/KeySize) must be able to reach the
            # wire as an explicit 0, and -SubjectAlternativeNames @() must be able to clear
            # the list.
            $body = @{}
            if ($PSBoundParameters.ContainsKey('Certificate'))              { $body['certificate']               = $Certificate }
            if ($PSBoundParameters.ContainsKey('CertificateType'))          { $body['certificate_type']          = $CertificateType }
            if ($PSBoundParameters.ContainsKey('CommonName'))               { $body['common_name']               = $CommonName }
            if ($PSBoundParameters.ContainsKey('Country'))                  { $body['country']                   = $Country }
            if ($PSBoundParameters.ContainsKey('Days'))                     { $body['days']                      = $Days }
            if ($PSBoundParameters.ContainsKey('Email'))                    { $body['email']                     = $Email }
            if ($PSBoundParameters.ContainsKey('IntermediateCertificate'))  { $body['intermediate_certificate']  = $IntermediateCertificate }
            if ($PSBoundParameters.ContainsKey('KeyAlgorithm'))             { $body['key_algorithm']             = $KeyAlgorithm }
            if ($PSBoundParameters.ContainsKey('KeySize'))                  { $body['key_size']                  = $KeySize }
            if ($PSBoundParameters.ContainsKey('Locality'))                 { $body['locality']                  = $Locality }
            if ($PSBoundParameters.ContainsKey('Organization'))             { $body['organization']              = $Organization }
            if ($PSBoundParameters.ContainsKey('OrganizationalUnit'))       { $body['organizational_unit']       = $OrganizationalUnit }
            if ($PSBoundParameters.ContainsKey('Passphrase'))               { $body['passphrase']                = $Passphrase }
            if ($PSBoundParameters.ContainsKey('PrivateKey'))               { $body['private_key']               = $PrivateKey }
            if ($PSBoundParameters.ContainsKey('State'))                    { $body['state']                     = $State }
            if ($PSBoundParameters.ContainsKey('SubjectAlternativeNames'))  { $body['subject_alternative_names'] = @($SubjectAlternativeNames) }
        }

        $target = if ($Name) { $Name } else { $Id }
        if ($PSCmdlet.ShouldProcess($target, 'Update certificate')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'certificates' -Body $body -QueryParams $queryParams
        }
    }
}
