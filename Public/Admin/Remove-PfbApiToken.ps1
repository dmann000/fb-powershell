function Remove-PfbApiToken {
    <#
    .SYNOPSIS
        Removes an API token from a FlashBlade administrator account.
    .DESCRIPTION
        The Remove-PfbApiToken cmdlet deletes the API token for a specified administrator account
        on the connected Everpure FlashBlade. The administrator can be identified by name or
        ID. This is a destructive operation and requires confirmation by default.

        DELETE /admins/api-tokens selects its target with admin_names / admin_ids. It accepts
        no generic names / ids key in any spec version, and FlashBlade silently drops an
        undeclared query parameter -- so a DELETE sent with names= arrives with no target at
        all, and the endpoint then falls back to the AUTHENTICATED administrator. Before
        issue #99 this cmdlet sent names/ids, so -Name pointed at another admin destroyed the
        CALLING session's own token and left the named admin's token untouched.

        A selector is therefore mandatory. It is enforced by the parameter binder: -Name and
        -Id are Mandatory within their parameter sets, so a call supplying neither fails to
        resolve a parameter set and a call supplying an empty string is rejected as an empty
        argument -- in both cases before the process block runs. The process block also
        refuses to issue a request whose query carries neither key, but that check is a
        defensive backstop that no input reaches today, not a second live layer.
    .PARAMETER Name
        The name of the administrator account whose API token to remove. Sent as the
        `admin_names` query parameter. Also accepts the alias -AdminNames. Accepts pipeline input.
    .PARAMETER Id
        The ID of the administrator account whose API token to remove. Sent as the
        `admin_ids` query parameter. Also accepts the alias -AdminIds.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbApiToken -Name "pureuser"

        Removes the API token for the administrator named "pureuser".
    .EXAMPLE
        Remove-PfbApiToken -Id "10314f42-020d-7080-8013-000ddt400012" -Confirm:$false

        Removes the API token for the specified administrator without confirmation.
    .EXAMPLE
        "ops-admin" | Remove-PfbApiToken

        Removes the API token for the administrator named "ops-admin" via pipeline input.
    .EXAMPLE
        Get-PfbApiToken | ForEach-Object { $_.admin.name } | Remove-PfbApiToken

        Removes every administrator's API token. Note the ForEach-Object: an API-token object
        exposes the administrator name at .admin.name, not as a top-level property, so piping
        Get-PfbApiToken output directly is rejected rather than silently misbound.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('AdminNames')]
        [string]$Name,

        [Parameter(ParameterSetName = 'ById', Mandatory)]
        [Alias('AdminIds')]
        [string]$Id,

        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        if ($Name) { Assert-PfbAdminNameNotCoerced -Value $Name }

        $target = if ($Name) { $Name } else { $Id }

        # admin_names/admin_ids, NOT names/ids -- see the .DESCRIPTION note above.
        $queryParams = @{}
        if ($Name) { $queryParams['admin_names'] = $Name }
        if ($Id)   { $queryParams['admin_ids']   = $Id }

        # Unreachable today: Mandatory on both sets means a selectorless call fails with
        # AmbiguousParameterSet and an empty-string selector fails with EmptyStringNotAllowed,
        # both at binding time. Kept deliberately as a backstop -- adding a
        # DefaultParameterSetName or relaxing a Mandatory flag would silently re-open #99.
        # Do not "simplify" it away.
        if (-not $queryParams.ContainsKey('admin_names') -and -not $queryParams.ContainsKey('admin_ids')) {
            throw 'Remove-PfbApiToken requires -Name or -Id. An unfiltered DELETE ' +
                  "/admins/api-tokens destroys the CALLING session's own API token."
        }

        if ($PSCmdlet.ShouldProcess($target, 'Remove API token')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'admins/api-tokens' -QueryParams $queryParams
        }
    }
}
