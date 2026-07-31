function Update-PfbActiveDirectory {
    <#
    .SYNOPSIS
        Updates an existing Active Directory configuration on a FlashBlade array.
    .DESCRIPTION
        The Update-PfbActiveDirectory cmdlet modifies attributes of an existing Active Directory
        configuration on the connected Everpure FlashBlade. The target configuration can be
        identified by name or ID. Common updates include changing directory servers, encryption
        types, and service principal names. Supports pipeline input and ShouldProcess.

        The individual typed parameters and the raw -Attributes hashtable are mutually
        exclusive: they live in separate parameter sets, so PowerShell rejects a mixed
        invocation at bind time rather than letting -Attributes silently override an
        explicitly supplied value.
    .PARAMETER Name
        The name of the Active Directory configuration to update. Accepts pipeline input by property name.
    .PARAMETER Id
        The ID of the Active Directory configuration to update.
    .PARAMETER CaCertificate
        Name of the Certificate Authority (CA) certificate that signed the certificates of the
        configured servers, which is used to validate the authenticity of those servers.
    .PARAMETER CaCertificateGroup
        Name of a certificate group containing CA certificates that can be used to validate the
        authenticity of the configured servers.
    .PARAMETER DirectoryServers
        A list of directory servers that will be used for lookups related to user authorization.
    .PARAMETER EncryptionTypes
        The encryption types that will be supported for use by clients for Kerberos authentication.
    .PARAMETER Fqdns
        A list of fully qualified domain names to use to register service principal names for the
        machine account.
    .PARAMETER GlobalCatalogServers
        A list of global catalog servers that will be used for lookups related to user authorization.
    .PARAMETER JoinOu
        The relative distinguished name of the organizational unit in which the computer account
        should be created when joining the domain.
    .PARAMETER KerberosServers
        A list of key distribution servers to use for Kerberos protocol.
    .PARAMETER ServicePrincipalNames
        A list of service principal names to register for the machine account, which can be used
        for the creation of keys for Kerberos authentication.
    .PARAMETER Attributes
        A hashtable of Active Directory attributes to modify. Mutually exclusive with the
        individual typed parameters above.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbActiveDirectory -Name "ad1" -DirectoryServers "dc02.corp.example.com"

        Updates the directory servers for the Active Directory configuration named "ad1" using
        typed parameters.
    .EXAMPLE
        Update-PfbActiveDirectory -Id "10314f42-020d-7080-8013-000ddt400055" -EncryptionTypes "aes256-cts-hmac-sha1-96"

        Updates the encryption types for the Active Directory configuration identified by ID.
    .EXAMPLE
        Update-PfbActiveDirectory -Name "ad1" -Attributes @{ directory_servers = @("dc02.corp.example.com") }

        Updates the directory servers for the Active Directory configuration named "ad1" using
        the raw -Attributes hashtable.
    .EXAMPLE
        Update-PfbActiveDirectory -Id "10314f42-020d-7080-8013-000ddt400055" -Attributes @{ encryption_types = @("aes256-cts-hmac-sha1-96") }

        Updates the encryption types for the Active Directory configuration identified by ID.
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
        [string]$CaCertificate,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$CaCertificateGroup,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string[]]$DirectoryServers,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [ValidateSet('aes256-cts-hmac-sha1-96', 'aes128-cts-hmac-sha1-96', 'arcfour-hmac')]
        [string[]]$EncryptionTypes,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string[]]$Fqdns,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string[]]$GlobalCatalogServers,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$JoinOu,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string[]]$KerberosServers,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string[]]$ServicePrincipalNames,

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

        if ($PSCmdlet.ParameterSetName -like '*Attributes') {
            $body = $Attributes
        }
        else {
            # Constraint 8(a): ca_certificate/ca_certificate_group are SCALAR references (item
            # schema is {id, name, resource_type}), so the parameter is [string] and the
            # assignment is INLINE -- constraint 7 forbids a $caCertRef local.
            $body = @{}
            if ($PSBoundParameters.ContainsKey('CaCertificate'))          { $body['ca_certificate'] = @{ name = $CaCertificate } }
            if ($PSBoundParameters.ContainsKey('CaCertificateGroup'))     { $body['ca_certificate_group'] = @{ name = $CaCertificateGroup } }
            if ($PSBoundParameters.ContainsKey('DirectoryServers'))       { $body['directory_servers'] = $DirectoryServers }
            if ($PSBoundParameters.ContainsKey('EncryptionTypes'))        { $body['encryption_types'] = $EncryptionTypes }
            if ($PSBoundParameters.ContainsKey('Fqdns'))                  { $body['fqdns'] = $Fqdns }
            if ($PSBoundParameters.ContainsKey('GlobalCatalogServers'))   { $body['global_catalog_servers'] = $GlobalCatalogServers }
            if ($PSBoundParameters.ContainsKey('JoinOu'))                 { $body['join_ou'] = $JoinOu }
            if ($PSBoundParameters.ContainsKey('KerberosServers'))        { $body['kerberos_servers'] = $KerberosServers }
            if ($PSBoundParameters.ContainsKey('ServicePrincipalNames'))  { $body['service_principal_names'] = $ServicePrincipalNames }
        }

        $target = if ($Name) { $Name } else { $Id }
        if ($PSCmdlet.ShouldProcess($target, 'Update Active Directory')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'active-directory' -Body $body -QueryParams $queryParams
        }
    }
}
