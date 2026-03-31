function New-PfbSaml2Idp {
    <#
    .SYNOPSIS
        Creates a new SAML2 identity provider configuration on the FlashBlade.
    .DESCRIPTION
        The New-PfbSaml2Idp cmdlet creates a new SAML2 identity provider configuration on the
        connected Pure Storage FlashBlade. The IdP name is required and attributes define the
        SAML2 configuration including metadata URL, sign-in URL, and certificate settings.
        Supports ShouldProcess for confirmation prompts.
    .PARAMETER Name
        The name of the SAML2 identity provider to create.
    .PARAMETER Attributes
        A hashtable of SAML2 IdP attributes to set (e.g., metadata_url, sign_in_url,
        signing_certificate, enabled).
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbSaml2Idp -Name "adfs-prod" -Attributes @{ metadata_url = "https://adfs.corp.example.com/FederationMetadata/2007-06/FederationMetadata.xml"; enabled = $true }

        Creates a new SAML2 identity provider pointing to ADFS using metadata URL.
    .EXAMPLE
        $samlConfig = @{
            sign_in_url         = "https://idp.example.com/sso/saml"
            signing_certificate = "-----BEGIN CERTIFICATE-----`nMIIC...`n-----END CERTIFICATE-----"
            enabled             = $true
        }
        New-PfbSaml2Idp -Name "custom-saml" -Attributes $samlConfig

        Creates a SAML2 identity provider with explicit sign-in URL and certificate.
    .EXAMPLE
        New-PfbSaml2Idp -Name "test-saml" -Attributes @{ metadata_url = "https://test.example.com/metadata" } -WhatIf

        Shows what would happen if the SAML2 IdP were created without making changes.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)] [string]$Name,
        [Parameter()] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $body = if ($Attributes) { $Attributes } else { @{} }
    $queryParams = @{ 'names' = $Name }

    if ($PSCmdlet.ShouldProcess($Name, 'Create SAML2 identity provider')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'sso/saml2/idps' -Body $body -QueryParams $queryParams
    }
}
