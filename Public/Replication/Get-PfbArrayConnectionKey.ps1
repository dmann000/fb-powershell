function Get-PfbArrayConnectionKey {
    <#
    .SYNOPSIS
        Retrieves array connection keys from a FlashBlade array.
    .DESCRIPTION
        The Get-PfbArrayConnectionKey cmdlet returns array connection key information from
        the connected Pure Storage FlashBlade. Connection keys are used to authenticate
        array-to-array replication connections.
    .PARAMETER Name
        One or more connection names to retrieve keys for. Accepts pipeline input.
        Mutually exclusive with -Id.
    .PARAMETER Id
        One or more array connection IDs to retrieve keys for. Accepts pipeline input by
        property name, so an array connection object can be piped straight in. Mutually
        exclusive with -Name: the API declares that ids cannot be provided together with
        the name or names query parameters.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction (e.g., "name" or "name-").
    .PARAMETER Limit
        Maximum number of entries to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbArrayConnectionKey

        Retrieves all array connection keys from the connected FlashBlade.
    .EXAMPLE
        Get-PfbArrayConnectionKey -Name "remote-fb-dc2"

        Retrieves the connection key for the specified array connection.
    .EXAMPLE
        Get-PfbArrayConnectionKey -Limit 5

        Retrieves up to 5 array connection keys.
    .EXAMPLE
        Get-PfbArrayConnection | Get-PfbArrayConnectionKey

        Retrieves the connection key for every array connection. Each connection object binds
        -Id by property name, so the keys come back filtered to those connections.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        # NAME-based piping stays impossible here, by decision rather than oversight.
        # GET /array-connections/connection-key items carry only connection_key, created and
        # expires -- no name field and no nested object -- so there is nothing to bind by property
        # name and nothing to lift, and an item of that shape reaches by-value coercion. Aliasing
        # a differently-meaning field onto -Name was considered and rejected as worse than the gap.
        # Do NOT add an alias or a lift here; only an API change adding a name to the endpoint's
        # items moves it, so -Name keeps its selector waiver.
        #
        # IDENTITY-based piping IS supported, which the waiver above does not cover: this endpoint
        # declares the generic `ids` query key from REST 2.0, and the items GET /array-connections
        # returns carry `id`. -Id below therefore binds by property name at binding pass 2, so
        # piping array-connection output into this cmdlet filters correctly and never reaches
        # coercion. Use -Id, not -Name, for that chain. The residual the guard in the process block
        # closes is the self-chain: this endpoint's own items carry neither key, so they still fall
        # through to coercion, and the guard turns that silent unfiltered result into a loud error.
        # Reasoning: issue #90.
        [Parameter(ParameterSetName = 'ByName', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$Name,

        # A separate set rather than a free combination: the spec states that `ids` "cannot be
        # provided together with the `name` or `names` query parameters", and an illegal key
        # combination is exactly the kind of request that can come back HTTP 200 and unfiltered.
        # Excluding the pair at bind time makes it a loud error instead. Declared without
        # ValueFromPipeline so that only an object actually carrying `id` can reach it.
        [Parameter(ParameterSetName = 'ById', ValueFromPipelineByPropertyName)]
        [string[]]$Id,

        [Parameter()] [string]$Filter, [Parameter()] [string]$Sort, [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )
    begin {
        Assert-PfbConnection -Array ([ref]$Array)
        $allNames = [System.Collections.Generic.List[string]]::new()
        $allIds = [System.Collections.Generic.List[string]]::new()
    }

    process {
        Assert-PfbSelectorNotCoerced -Value $Name -ParameterName 'Name' -Hint (
            'Array connection keys have no name of their own. Pipe an array connection object ' +
            'from Get-PfbArrayConnection instead -- its `id` binds -Id directly -- or pass -Id ' +
            'or -Name explicitly.')
        if ($Name) { foreach ($n in $Name) { $allNames.Add($n) } }
        if ($Id) { foreach ($i in $Id) { $allIds.Add($i) } }
    }

    end {
        $queryParams = @{}
        # Both keys are the generic ones on this endpoint, so the common helper carries them:
        # it emits `names` for -Names and `ids` for -Ids. The parameter sets guarantee at most
        # one of the two accumulators is non-empty, so the illegal combination never reaches here.
        Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters -Names $allNames -Ids $allIds
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'array-connections/connection-key' -QueryParams $queryParams -AutoPaginate
    }
}
