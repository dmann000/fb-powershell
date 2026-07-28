function New-PfbApiToken {
    <#
    .SYNOPSIS
        Creates a new API token for a FlashBlade administrator.
    .DESCRIPTION
        The New-PfbApiToken cmdlet generates a new API token for an administrator account on the
        connected Everpure FlashBlade. The administrator is identified by name or ID. Supports
        ShouldProcess for confirmation prompts.

        Note that `POST /admins/api-tokens` takes no request body at all -- every field this
        endpoint accepts is a query parameter.
    .PARAMETER Name
        The name of the administrator account for which to create an API token. Sent as the
        `admin_names` query parameter. Also accepts the alias -AdminNames.
    .PARAMETER Id
        The ID of the administrator account for which to create an API token. Sent as the
        `admin_ids` query parameter. Also accepts the alias -AdminIds.
    .PARAMETER Timeout
        The duration of API token validity, in milliseconds.
    .PARAMETER Attributes
        A hashtable of additional token attributes.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbApiToken -Name "pureuser"

        Creates a new API token for the administrator named "pureuser".
    .EXAMPLE
        New-PfbApiToken -Name "ops-admin" -Timeout 86400000

        Creates a new API token for "ops-admin" that is valid for 24 hours.
    .EXAMPLE
        New-PfbApiToken -Id "10314f42-020d-7080-8013-000ddt400012"

        Creates a new API token for the administrator identified by ID.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(ParameterSetName = 'ByName', ValueFromPipelineByPropertyName)]
        [Alias('AdminNames')]
        [string]$Name,

        [Parameter(ParameterSetName = 'ById')]
        [Alias('AdminIds')]
        [string]$Id,

        [Parameter()] [long]$Timeout,
        [Parameter()] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        # POST /admins/api-tokens accepts admin_names/admin_ids, NOT names/ids. The cmdlet
        # previously sent names/ids, which the array silently ignored, so -Name and -Id had
        # no effect at all.
        $queryParams = @{}
        if ($Name) { $queryParams['admin_names'] = $Name }
        if ($Id)   { $queryParams['admin_ids']   = $Id }
        if ($PSBoundParameters.ContainsKey('Timeout')) { $queryParams['timeout'] = $Timeout }

        $target = if ($Name) { $Name } else { $Id }
        $body = if ($Attributes) { $Attributes } else { @{} }

        if ($PSCmdlet.ShouldProcess($target, 'Create API token')) {
            Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'admins/api-tokens' -Body $body -QueryParams $queryParams
        }
    }
}
