function New-PfbApiToken {
    <#
    .SYNOPSIS
        Creates a new API token for a FlashBlade administrator.
    .DESCRIPTION
        The New-PfbApiToken cmdlet generates a new API token for an administrator account on the
        connected Everpure FlashBlade. The administrator is identified by name or ID. Supports
        ShouldProcess for confirmation prompts.

        Note that `POST /admins/api-tokens` takes no request body at all -- every field this
        endpoint accepts is a query parameter, and this cmdlet sends none.

        A selector is mandatory. An unfiltered POST would arrive with no target, and what the
        array does then is not established -- most likely it falls back to the authenticated
        administrator, rotating the caller's own token and invalidating any stored copy of it.
        Rather than depend on that, -Name and -Id are Mandatory within their parameter sets, so
        the parameter binder rejects a call supplying neither (no parameter set resolves) or
        supplying an empty string, before the process block runs. The process block also
        refuses to issue a request whose query carries neither key, but that check is a
        defensive backstop that no input reaches today, not a second live layer. To create
        a token for the current session's own account, name that account explicitly. To rotate
        several administrators' tokens, pipe their names in.
    .PARAMETER Name
        The name of the administrator account for which to create an API token. Sent as the
        `admin_names` query parameter. Also accepts the alias -AdminNames. Accepts pipeline input.
    .PARAMETER Id
        The ID of the administrator account for which to create an API token. Sent as the
        `admin_ids` query parameter. Also accepts the alias -AdminIds.
    .PARAMETER Timeout
        The duration of API token validity, in milliseconds.
    .PARAMETER Attributes
        Retained for backward compatibility only. `POST /admins/api-tokens` accepts no request
        body, so nothing supplied here is sent to the array and a warning is emitted. Use
        -Timeout to set the token's validity period.
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
    .EXAMPLE
        'ops-admin', 'svc-admin' | New-PfbApiToken -Confirm:$false

        Rotates the API tokens of several administrators, issuing one POST per name.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('AdminNames')]
        [string]$Name,

        [Parameter(ParameterSetName = 'ById', Mandatory)]
        [Alias('AdminIds')]
        [string]$Id,

        [Parameter()] [long]$Timeout,
        [Parameter()] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)

        # -Attributes is not a pipeline parameter -- it binds once for the whole invocation,
        # so the warning belongs in begin. Emitting it from process would repeat it once per
        # piped name, in exactly the bulk-rotation flow ValueFromPipeline exists to enable.
        if ($PSBoundParameters.ContainsKey('Attributes')) {
            Write-Warning ('-Attributes is accepted for backward compatibility only. ' +
                           'POST /admins/api-tokens declares no request body, so nothing ' +
                           "supplied here is sent to the array. Use -Timeout to set the " +
                           "token's validity period.")
        }
    }

    process {
        if ($Name) { Assert-PfbAdminNameNotCoerced -Value $Name }

        # POST /admins/api-tokens accepts admin_names/admin_ids, NOT names/ids. The cmdlet
        # previously sent names/ids, which the array silently ignored, so -Name and -Id had
        # no effect at all.
        $queryParams = @{}
        if ($Name) { $queryParams['admin_names'] = $Name }
        if ($Id)   { $queryParams['admin_ids']   = $Id }
        if ($PSBoundParameters.ContainsKey('Timeout')) { $queryParams['timeout'] = $Timeout }

        # Unreachable today: Mandatory on both sets means a selectorless call fails with
        # AmbiguousParameterSet and an empty-string selector fails with EmptyStringNotAllowed,
        # both at binding time. Kept deliberately as a backstop -- adding a
        # DefaultParameterSetName or relaxing a Mandatory flag would silently re-open #99.
        # Do not "simplify" it away.
        if (-not $queryParams.ContainsKey('admin_names') -and -not $queryParams.ContainsKey('admin_ids')) {
            throw 'New-PfbApiToken requires -Name or -Id. An unfiltered POST ' +
                  '/admins/api-tokens has no explicit target and would act on the ' +
                  'authenticated administrator.'
        }

        $target = if ($Name) { $Name } else { $Id }

        if ($PSCmdlet.ShouldProcess($target, 'Create API token')) {
            Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'admins/api-tokens' -QueryParams $queryParams
        }
    }
}
