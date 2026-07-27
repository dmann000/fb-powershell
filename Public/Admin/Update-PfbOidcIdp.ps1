function Update-PfbOidcIdp {
    <#
    .SYNOPSIS
        Updates an existing OIDC identity provider configuration on the FlashBlade.
    .DESCRIPTION
        The Update-PfbOidcIdp cmdlet modifies attributes of an existing OIDC (OpenID Connect)
        identity provider configuration on the connected Everpure FlashBlade. The target
        IdP can be identified by name or ID. Supports ShouldProcess for confirmation prompts.

        The individual typed parameters and the raw -Attributes hashtable are mutually
        exclusive: they live in separate parameter sets, so PowerShell rejects a mixed
        invocation at bind time rather than letting -Attributes silently override an
        explicitly supplied value.
    .PARAMETER Name
        The name of the OIDC identity provider to update. Accepts pipeline input by property name.
    .PARAMETER Id
        The ID of the OIDC identity provider to update.
    .PARAMETER Enabled
        If set to $true, the OIDC SSO configuration is enabled.
    .PARAMETER Idp
        Properties specific to the identity provider, as a hashtable -- for example
        @{ provider_url = 'https://idp.example.com' }. The schema models this as a multi-field
        configuration sub-object (`provider_url`, `provider_url_ca_certificate`,
        `provider_url_ca_certificate_group`), not as a reference to another resource, so it is
        passed through rather than given a name-only parameter.
    .PARAMETER OidcIdpName
        A new name for the provider. Named -OidcIdpName rather than -Name because -Name
        already identifies which IdP to update.
    .PARAMETER Services
        Services that the OIDC SSO authentication is used for.
    .PARAMETER Attributes
        A hashtable of OIDC IdP attributes to modify. Mutually exclusive with the individual
        typed parameters above.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbOidcIdp -Name "okta-prod" -Enabled $false

        Disables the OIDC identity provider named "okta-prod" using a typed parameter.
    .EXAMPLE
        Update-PfbOidcIdp -Name "okta-prod" -Idp @{ provider_url = "https://new-idp.example.com" }

        Repoints the OIDC identity provider at a new provider URL.
    .EXAMPLE
        Update-PfbOidcIdp -Id "abc12345-6789-0abc-def0-123456789abc" -Attributes @{ enabled = $false }

        Disables the OIDC IdP identified by ID.
    .EXAMPLE
        Update-PfbOidcIdp -Name "azure-ad" -OidcIdpName "azure-ad-renamed" -WhatIf

        Shows what would happen if the OIDC IdP were renamed without making changes.
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
        [Nullable[bool]]$Enabled,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [hashtable]$Idp,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$OidcIdpName,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string[]]$Services,

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
            $body = @{}
            if ($OidcIdpName) { $body['name']     = $OidcIdpName }
            if ($Services)    { $body['services'] = @($Services) }

            # Constraint 2: explicit $false must still be sent. The [Nullable[bool]] type plus
            # this ContainsKey guard is what achieves that -- constraint 7 forbids a [bool]
            # cast here, which would break the wire-name trace and buys nothing.
            if ($PSBoundParameters.ContainsKey('Enabled')) { $body['enabled'] = $Enabled }

            # Constraint 8(c): idp is a COMPOSITE sub-object (_oidcSsoPostIdp carries
            # provider_url and its CA-certificate references), not a reference -- it has no
            # `name` property at all, so projecting it into @{ name = ... } would write a
            # field the schema does not have. Pass it straight through.
            if ($Idp) { $body['idp'] = $Idp }
        }

        $target = if ($Name) { $Name } else { $Id }
        if ($PSCmdlet.ShouldProcess($target, 'Update OIDC identity provider')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'sso/oidc/idps' -Body $body -QueryParams $queryParams
        }
    }
}
