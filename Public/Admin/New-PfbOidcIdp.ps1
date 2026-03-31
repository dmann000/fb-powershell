function New-PfbOidcIdp {
    <#
    .SYNOPSIS
        Creates a new OIDC identity provider configuration on the FlashBlade.
    .DESCRIPTION
        The New-PfbOidcIdp cmdlet creates a new OIDC (OpenID Connect) identity provider
        configuration on the connected Pure Storage FlashBlade. The IdP name is required and
        attributes define the OIDC configuration including issuer, client ID, and other settings.
        Supports ShouldProcess for confirmation prompts.
    .PARAMETER Name
        The name of the OIDC identity provider to create.
    .PARAMETER Attributes
        A hashtable of OIDC IdP attributes to set (e.g., issuer, client_id, client_credential,
        enabled, scopes).
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbOidcIdp -Name "okta-prod" -Attributes @{ issuer = "https://corp.okta.com"; client_id = "0oa1234567890abcdef"; enabled = $true }

        Creates a new OIDC identity provider pointing to Okta.
    .EXAMPLE
        $oidcConfig = @{
            issuer            = "https://login.microsoftonline.com/tenant-id/v2.0"
            client_id         = "app-client-id"
            client_credential = @{ client_secret = "app-secret" }
        }
        New-PfbOidcIdp -Name "azure-ad" -Attributes $oidcConfig

        Creates an OIDC identity provider for Azure AD with client credentials.
    .EXAMPLE
        New-PfbOidcIdp -Name "test-idp" -Attributes @{ issuer = "https://test.example.com" } -WhatIf

        Shows what would happen if the OIDC IdP were created without making changes.
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

    if ($PSCmdlet.ShouldProcess($Name, 'Create OIDC identity provider')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'sso/oidc/idps' -Body $body -QueryParams $queryParams
    }
}
