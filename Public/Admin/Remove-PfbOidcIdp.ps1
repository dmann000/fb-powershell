function Remove-PfbOidcIdp {
    <#
    .SYNOPSIS
        Removes an OIDC identity provider configuration from the FlashBlade.
    .DESCRIPTION
        The Remove-PfbOidcIdp cmdlet deletes an OIDC (OpenID Connect) identity provider
        configuration from the connected Pure Storage FlashBlade. The target IdP can be
        identified by name or ID. This is a destructive operation and requires confirmation
        by default.
    .PARAMETER Name
        The name of the OIDC identity provider to remove. Accepts pipeline input.
    .PARAMETER Id
        The ID of the OIDC identity provider to remove.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbOidcIdp -Name "okta-prod"

        Removes the OIDC identity provider named "okta-prod".
    .EXAMPLE
        Remove-PfbOidcIdp -Id "abc12345-6789-0abc-def0-123456789abc" -Confirm:$false

        Removes the OIDC identity provider without confirmation.
    .EXAMPLE
        "test-idp" | Remove-PfbOidcIdp

        Removes the OIDC identity provider via pipeline input.
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

        if ($PSCmdlet.ShouldProcess($target, 'Remove OIDC identity provider')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'sso/oidc/idps' -QueryParams $queryParams
        }
    }
}
