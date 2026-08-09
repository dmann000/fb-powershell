function Get-PfbApiToken {
    <#
    .SYNOPSIS
        Retrieves FlashBlade administrator API tokens.
    .DESCRIPTION
        The Get-PfbApiToken cmdlet returns one or more administrator API tokens from the connected
        Everpure FlashBlade. Results can be filtered by name, ID, or a server-side filter
        expression. Supports pipeline input for batch lookups and automatic pagination.

        GET /admins/api-tokens selects with admin_names / admin_ids and accepts no generic
        names / ids key in any spec version. Because FlashBlade silently drops an undeclared
        query parameter, this cmdlet's pre-#99 -Name returned EVERY administrator's row rather
        than the one asked for, with no error to indicate it.

        The selector cannot go through Add-PfbCommonQueryParams, which hardcodes the generic
        names / ids keys for the endpoints that do accept them. The helper is still used for
        -Filter, -Sort and -Limit; the endpoint-specific keys are set inline afterwards.
    .PARAMETER Name
        One or more administrator account names whose API tokens to retrieve. Sent as the
        `admin_names` query parameter. Also accepts the alias -AdminNames. Accepts pipeline input.

        -Name is optional, so an EMPTY array is a legal "no filter" value: -Name @() (or a
        variable that happens to be empty, or a pipeline that produced nothing) emits no
        `admin_names` key and therefore returns EVERY administrator's row, exactly as a bare
        Get-PfbApiToken does. If a caller builds the name list dynamically and an empty list
        should mean "nothing", test for that before calling.

        A piped Get-PfbApiToken row is rejected rather than silently misbound: the object has
        no top-level name property (the administrator name is nested at .admin.name), so it
        would otherwise be ToString()-ed whole into -Name. Pipe $_.admin.name instead.
    .PARAMETER Id
        One or more administrator account IDs whose API tokens to retrieve. Sent as the
        `admin_ids` query parameter. Also accepts the alias -AdminIds.
    .PARAMETER Filter
        A server-side filter expression to narrow results (e.g., "name='pureuser'").
    .PARAMETER Sort
        Sort field and direction (e.g., "name" or "name-").
    .PARAMETER Limit
        Maximum number of entries to return.
    .PARAMETER ExposeApiToken
        Return the calling administrator's API token value in full instead of masked.

        Token values are masked by default. This switch un-masks ONLY the token belonging to
        the administrator the current session is authenticated as; every other administrator's
        token stays masked whether it is set or not. Verified against REST 2.26.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbApiToken

        Retrieves all administrator API tokens from the connected FlashBlade, with token
        values masked.
    .EXAMPLE
        Get-PfbApiToken -Name "pureuser"

        Retrieves the API token for the administrator account named "pureuser".
    .EXAMPLE
        Get-PfbApiToken -Name "pureuser" -ExposeApiToken

        Retrieves "pureuser"'s API token with its value un-masked. This returns a real
        credential only when the session is authenticated as that same administrator.
    .EXAMPLE
        Get-PfbApiToken -Filter "name='ops-admin'" -Limit 5

        Retrieves up to 5 API tokens matching the specified filter.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(ParameterSetName = 'ByName', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('AdminNames')]
        [string[]]$Name,

        [Parameter(ParameterSetName = 'ById')]
        [Alias('AdminIds')]
        [string[]]$Id,

        [Parameter()] [string]$Filter,
        [Parameter()] [string]$Sort,
        [Parameter()] [int]$Limit,
        [Parameter()] [switch]$ExposeApiToken,
        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
        $allNames = [System.Collections.Generic.List[string]]::new()
        $allIds = [System.Collections.Generic.List[string]]::new()
    }
    process {
        if ($Name) { foreach ($n in $Name) { Assert-PfbAdminNameNotCoerced -Value $n; $allNames.Add($n) } }
        if ($Id)   { foreach ($i in $Id)   { $allIds.Add($i) } }
    }
    end {
        $queryParams = @{}

        # -Names/-Ids are deliberately NOT passed: the helper would emit names=/ids=, which
        # this endpoint does not accept and silently ignores. See .DESCRIPTION.
        Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters

        if ($allNames) { $queryParams['admin_names'] = $allNames -join ',' }
        if ($allIds)   { $queryParams['admin_ids']   = $allIds   -join ',' }
        if ($ExposeApiToken) { $queryParams['expose_api_token'] = 'true' }

        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'admins/api-tokens' -QueryParams $queryParams -AutoPaginate
    }
}
