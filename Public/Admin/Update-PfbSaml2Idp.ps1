function Update-PfbSaml2Idp {
    <#
    .SYNOPSIS
        Updates an existing SAML2 identity provider configuration on the FlashBlade.
    .DESCRIPTION
        The Update-PfbSaml2Idp cmdlet modifies attributes of an existing SAML2 identity provider
        configuration on the connected Pure Storage FlashBlade. The target IdP can be identified
        by name or ID. Supports ShouldProcess for confirmation prompts.
    .PARAMETER Name
        The name of the SAML2 identity provider to update. Accepts pipeline input by property name.
    .PARAMETER Id
        The ID of the SAML2 identity provider to update.
    .PARAMETER Attributes
        A hashtable of SAML2 IdP attributes to modify (e.g., metadata_url, enabled).
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbSaml2Idp -Name "adfs-prod" -Attributes @{ enabled = $false }

        Disables the SAML2 identity provider named "adfs-prod".
    .EXAMPLE
        Update-PfbSaml2Idp -Id "abc12345-6789-0abc-def0-123456789abc" -Attributes @{ metadata_url = "https://new-adfs.corp.example.com/metadata" }

        Updates the metadata URL for the SAML2 IdP identified by ID.
    .EXAMPLE
        Update-PfbSaml2Idp -Name "custom-saml" -Attributes @{ sign_in_url = "https://new-idp.example.com/sso" } -WhatIf

        Shows what would happen if the SAML2 IdP were updated without making changes.
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

        if ($PSCmdlet.ShouldProcess($target, 'Update SAML2 identity provider')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'sso/saml2/idps' -Body $Attributes -QueryParams $queryParams
        }
    }
}
