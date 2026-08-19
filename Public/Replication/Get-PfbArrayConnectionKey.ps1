function Get-PfbArrayConnectionKey {
    <#
    .SYNOPSIS
        Retrieves array connection keys from a FlashBlade array.
    .DESCRIPTION
        The Get-PfbArrayConnectionKey cmdlet returns array connection key information from
        the connected Pure Storage FlashBlade. Connection keys are used to authenticate
        array-to-array replication connections.
    .PARAMETER Name
        One or more connection names. Accepts pipeline input. The endpoint declares the
        generic names query parameter, so this cmdlet sends that key when the parameter is
        supplied, but the items the endpoint returns carry no name of their own, so the key
        does not narrow the result.
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

        Sends the declared names query key. The endpoint's items carry no name, so this does
        not narrow the result -- every array connection key is still returned.
    .EXAMPLE
        Get-PfbArrayConnectionKey -Limit 5

        Retrieves up to 5 array connection keys.
    #>
    [CmdletBinding()]
    param(
        # NAME-based piping stays impossible here, by decision rather than oversight.
        # GET /array-connections/connection-key items carry only connection_key, created and
        # expires -- no name field and no nested object -- so there is nothing to bind by property
        # name and nothing to lift, and an item of that shape reaches by-value coercion. Aliasing
        # a differently-meaning field onto -Name was considered and rejected as worse than the gap.
        # Do NOT add an alias or a lift here; only an API change adding a name to the endpoint's
        # items would move it.
        #
        # No IDENTITY-based selector can work here either, and that is a property of the endpoint
        # rather than of this cmdlet. components.schemas.ArrayConnectionKey -- the item type this
        # endpoint returns -- declares exactly connection_key, created and expires at every spec
        # version 2.0 through 2.28, and it is a flat object with no allOf, so it does not inherit
        # the base schema that supplies id and name to ordinary resources. The generic ids and
        # names query keys select resources of the endpoint they are given to, by the identifier
        # those resources carry; an item carrying neither has nothing for either key to match. An
        # -Id parameter was briefly added here and then removed for exactly that reason: it
        # reasoned from the response shape of GET /array-connections, a different endpoint whose
        # items do carry id, to this endpoint's query capability. Piping array-connection output
        # into this cmdlet therefore cannot filter, and the coercion guard in the process block is
        # the entire remedy -- it turns a silently unfiltered result into a loud error.
        # Reasoning: issue #90.
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$Name,

        [Parameter()] [string]$Filter, [Parameter()] [string]$Sort, [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )
    begin {
        Assert-PfbConnection -Array ([ref]$Array)
        $allNames = [System.Collections.Generic.List[string]]::new()
    }

    process {
        Assert-PfbSelectorNotCoerced -Value $Name -OriginalInput $PSItem -ParameterName 'Name' -Hint (
            'This endpoint cannot be filtered by connection identity at all: its items carry ' +
            'neither an id nor a name, so neither the ids nor the names query key has anything ' +
            'to select on. Call Get-PfbArrayConnectionKey with no selector and match the keys ' +
            'you want from the returned collection.')
        if ($Name) { foreach ($n in $Name) { $allNames.Add($n) } }
    }

    end {
        $queryParams = @{}
        # `names` is a generic key on this endpoint, so the common helper carries it: it emits
        # `names` for -Names. The key goes on the wire because the spec declares it, not because
        # it narrows anything -- see the note on -Name above.
        Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters -Names $allNames
        if (Test-PfbEmptyPipelineRead -Caller $PSCmdlet -QueryParams $queryParams) { return }
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'array-connections/connection-key' -QueryParams $queryParams -AutoPaginate
    }
}
