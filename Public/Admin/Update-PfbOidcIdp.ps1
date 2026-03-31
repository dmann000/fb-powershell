function Update-PfbOidcIdp {
    <#
    .SYNOPSIS
        Updates an existing OIDC identity provider configuration on the FlashBlade.
    .DESCRIPTION
        The Update-PfbOidcIdp cmdlet modifies attributes of an existing OIDC (OpenID Connect)
        identity provider configuration on the connected Pure Storage FlashBlade. The target
        IdP can be identified by name or ID. Supports ShouldProcess for confirmation prompts.
    .PARAMETER Name
        The name of the OIDC identity provider to update. Accepts pipeline input by property name.
    .PARAMETER Id
        The ID of the OIDC identity provider to update.
    .PARAMETER Attributes
        A hashtable of OIDC IdP attributes to modify (e.g., issuer, client_id, enabled).
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbOidcIdp -Name "okta-prod" -Attributes @{ enabled = $false }

        Disables the OIDC identity provider named "okta-prod".
    .EXAMPLE
        Update-PfbOidcIdp -Id "abc12345-6789-0abc-def0-123456789abc" -Attributes @{ issuer = "https://new-issuer.example.com" }

        Updates the issuer URL for the OIDC IdP identified by ID.
    .EXAMPLE
        Update-PfbOidcIdp -Name "azure-ad" -Attributes @{ client_id = "new-client-id" } -WhatIf

        Shows what would happen if the OIDC IdP were updated without making changes.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, ValueFromPipelineByPropertyName)]
        [string]$Name,
        [Parameter(ParameterSetName = 'ById', Mandatory)] [string]$Id,
        [Parameter(Mandatory)] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $queryParams = @{}
        if ($Name) { $queryParams['names'] = $Name }
        if ($Id)   { $queryParams['ids']   = $Id }
        $target = if ($Name) { $Name } else { $Id }

        if ($PSCmdlet.ShouldProcess($target, 'Update OIDC identity provider')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'sso/oidc/idps' -Body $Attributes -QueryParams $queryParams
        }
    }
}
