function New-PfbApiToken {
    <#
    .SYNOPSIS
        Creates a new API token for a FlashBlade administrator.
    .DESCRIPTION
        The New-PfbApiToken cmdlet generates a new API token for an administrator account on the
        connected Pure Storage FlashBlade. The administrator is identified by name or ID. Optional
        attributes can be provided to configure token properties. Supports ShouldProcess for
        confirmation prompts.
    .PARAMETER Name
        The name of the administrator account for which to create an API token.
    .PARAMETER Id
        The ID of the administrator account for which to create an API token.
    .PARAMETER Attributes
        A hashtable of token attributes to set (e.g., timeout duration).
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbApiToken -Name "pureuser"

        Creates a new API token for the administrator named "pureuser".
    .EXAMPLE
        New-PfbApiToken -Name "ops-admin" -Attributes @{ timeout = 86400000 }

        Creates a new API token with a custom timeout for the specified administrator.
    .EXAMPLE
        New-PfbApiToken -Id "10314f42-020d-7080-8013-000ddt400012"

        Creates a new API token for the administrator identified by ID.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(ParameterSetName = 'ByName', ValueFromPipelineByPropertyName)]
        [string]$Name,
        [Parameter(ParameterSetName = 'ById')] [string]$Id,
        [Parameter()] [hashtable]$Attributes,
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
        $body = if ($Attributes) { $Attributes } else { @{} }

        if ($PSCmdlet.ShouldProcess($target, 'Create API token')) {
            Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'admins/api-tokens' -Body $body -QueryParams $queryParams
        }
    }
}
