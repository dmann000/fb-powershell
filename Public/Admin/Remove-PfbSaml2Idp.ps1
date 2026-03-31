function Remove-PfbSaml2Idp {
    <#
    .SYNOPSIS
        Removes a SAML2 identity provider configuration from the FlashBlade.
    .DESCRIPTION
        The Remove-PfbSaml2Idp cmdlet deletes a SAML2 identity provider configuration from
        the connected Pure Storage FlashBlade. The target IdP can be identified by name or ID.
        This is a destructive operation and requires confirmation by default.
    .PARAMETER Name
        The name of the SAML2 identity provider to remove. Accepts pipeline input.
    .PARAMETER Id
        The ID of the SAML2 identity provider to remove.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbSaml2Idp -Name "adfs-prod"

        Removes the SAML2 identity provider named "adfs-prod".
    .EXAMPLE
        Remove-PfbSaml2Idp -Id "abc12345-6789-0abc-def0-123456789abc" -Confirm:$false

        Removes the SAML2 identity provider without confirmation.
    .EXAMPLE
        "test-saml" | Remove-PfbSaml2Idp

        Removes the SAML2 identity provider via pipeline input.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(ParameterSetName = 'ById', Mandatory)]
        [string]$Id,

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

        if ($PSCmdlet.ShouldProcess($target, 'Remove SAML2 identity provider')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'sso/saml2/idps' -QueryParams $queryParams
        }
    }
}
