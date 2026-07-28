function Update-PfbSaml2Idp {
    <#
    .SYNOPSIS
        Updates an existing SAML2 identity provider configuration on the FlashBlade.
    .DESCRIPTION
        The Update-PfbSaml2Idp cmdlet modifies attributes of an existing SAML2 identity provider
        configuration on the connected Everpure FlashBlade. The target IdP can be identified
        by name or ID. Supports ShouldProcess for confirmation prompts.

        The individual typed parameters and the raw -Attributes hashtable are mutually
        exclusive: they live in separate parameter sets, so PowerShell rejects a mixed
        invocation at bind time rather than letting -Attributes silently override an
        explicitly supplied value.
    .PARAMETER Name
        The name of the SAML2 identity provider to update. Accepts pipeline input by property name.
    .PARAMETER Id
        The ID of the SAML2 identity provider to update.
    .PARAMETER ArrayUrl
        The URL of the array.
    .PARAMETER Binding
        SAML2 binding to use for the request from the FlashBlade to the Identity Provider.
    .PARAMETER Enabled
        If set to $true, the SAML2 SSO configuration is enabled.
    .PARAMETER Idp
        Properties specific to the identity provider, as a hashtable -- for example
        @{ entity_id = 'urn:idp'; metadata_url = 'https://idp.example.com/metadata' }. The
        schema models this as a multi-field configuration sub-object, not as a reference to
        another resource, so it is passed through rather than given a name-only parameter.
    .PARAMETER Management
        Properties specific to the management service, as a hashtable -- for example
        @{ trust_other_saml_sps_in_fleet = $false }.
    .PARAMETER NewName
        A new user-specified name for the provider. Named -NewName rather than -Name
        because -Name already identifies which IdP to update.
    .PARAMETER Services
        Services that the SAML2 SSO authentication is used for.
    .PARAMETER Sp
        Properties specific to the service provider, as a hashtable -- for example
        @{ entity_id = 'urn:sp'; signing_credential = @{ name = 'cert1' } }.
    .PARAMETER Attributes
        A hashtable of SAML2 IdP attributes to modify. Mutually exclusive with the individual
        typed parameters above.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbSaml2Idp -Name "adfs-prod" -Enabled $false

        Disables the SAML2 identity provider named "adfs-prod" using a typed parameter.
    .EXAMPLE
        Update-PfbSaml2Idp -Name "adfs-prod" -Idp @{ metadata_url = "https://new-adfs.corp.example.com/metadata" }

        Updates the metadata URL for the SAML2 identity provider named "adfs-prod".
    .EXAMPLE
        Update-PfbSaml2Idp -Id "abc12345-6789-0abc-def0-123456789abc" -Attributes @{ enabled = $false }

        Disables the SAML2 IdP identified by ID.
    .EXAMPLE
        Update-PfbSaml2Idp -Name "custom-saml" -ArrayUrl "https://fb.corp.example.com" -WhatIf

        Shows what would happen if the SAML2 IdP were updated without making changes.
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
        [string]$ArrayUrl,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$Binding,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [Nullable[bool]]$Enabled,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [hashtable]$Idp,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [hashtable]$Management,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$NewName,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string[]]$Services,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [hashtable]$Sp,

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
            # Every body parameter is guarded by ContainsKey, never by truthiness -- see the
            # canonical explanation in Update-PfbAdmin.ps1.
            $body = @{}
            if ($PSBoundParameters.ContainsKey('ArrayUrl')) { $body['array_url'] = $ArrayUrl }
            if ($PSBoundParameters.ContainsKey('Binding'))  { $body['binding']   = $Binding }
            if ($PSBoundParameters.ContainsKey('Enabled'))  { $body['enabled']   = $Enabled }
            if ($PSBoundParameters.ContainsKey('NewName'))  { $body['name']      = $NewName }
            if ($PSBoundParameters.ContainsKey('Services')) { $body['services']  = @($Services) }

            # Constraint 8(c): idp, management and sp are all COMPOSITE sub-objects
            # (_saml2SsoIdp, _saml2SsoManagement, _saml2SsoSp), not references -- none of them
            # has a `name` property, so projecting them into @{ name = ... } would write a
            # field the schema does not have. Pass them straight through.
            if ($PSBoundParameters.ContainsKey('Idp'))        { $body['idp']        = $Idp }
            if ($PSBoundParameters.ContainsKey('Management')) { $body['management'] = $Management }
            if ($PSBoundParameters.ContainsKey('Sp'))         { $body['sp']         = $Sp }
        }

        $target = if ($Name) { $Name } else { $Id }
        if ($PSCmdlet.ShouldProcess($target, 'Update SAML2 identity provider')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'sso/saml2/idps' -Body $body -QueryParams $queryParams
        }
    }
}
