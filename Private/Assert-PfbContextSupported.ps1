function Get-PfbEndpointKey {
    <#
    .SYNOPSIS
        Builds the capability-map endpoints key for a method and endpoint.
    .DESCRIPTION
        ONE home for this normalization. Assert-PfbApiCapability and the context gates must
        agree byte-for-byte: a second copy that differed by a leading slash would miss every
        entry in the map. That failure is silent, which makes it worse than a throw --
        Assert-PfbApiCapability treats a missing entry as a deliberate pass
        ("if (-not $entry) { return }"), so a drifted key blocks nothing. It quietly
        disables the version gate for every endpoint in the module.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][string]$Endpoint
    )

    "$Method /" + $Endpoint.TrimStart('/')
}

function Assert-PfbContextCapability {
    <#
    .SYNOPSIS
        Throws when a context is set for an endpoint the map says cannot take one.
    .DESCRIPTION
        Rows 3 and 4 of the design's injection/gating table, and they MIRROR each other: the
        two "absent" cases (no entry at all, entry without context_names) get identical
        treatment, because the likeliest real staleness is an endpoint that exists today and
        GAINS context_names later -- entry present, parameter absent.

        Keyed on the map's generatedFrom via Test-PfbCapabilityMapCoverage, so absence WITHIN
        the scanned range is confirmed absence and absence beyond it is no evidence at all.

        Why client-side rather than "send it and let the array error": in the case that
        matters there is no error to surface. An endpoint that never supported context_names
        (/alert-watchers) silently accepts it -- HTTP 200, real mutations applied, no mention
        of the parameter. The array performs no query-parameter validation on reads at all.
        Accepting a parameter is not evidence an endpoint supports it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][PSCustomObject]$Array,
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][string]$Endpoint,
        [Parameter(Mandatory)]$Context,
        [Parameter()][AllowNull()]$CapabilityMap
    )

    if (-not $CapabilityMap) { return }

    $key = Get-PfbEndpointKey -Method $Method -Endpoint $Endpoint
    $entry = $CapabilityMap.endpoints.$key

    $supportsContext = $false
    if ($entry -and $entry.parameters) {
        $supportsContext = @($entry.parameters.PSObject.Properties.Name) -contains $script:PfbContextParameterName
    }
    if ($supportsContext) { return }   # Assert-PfbApiCapability owns "recorded but array too old"

    # Beyond the scanned range the map has no evidence, so proceed permissively rather than
    # punish a packaging lag the caller cannot see.
    if (Test-PfbCapabilityMapCoverage -NegotiatedVersion $Array.ApiVersion -CapabilityMap $CapabilityMap) {
        return
    }

    $names = @($Context.Entries | ForEach-Object { ConvertTo-PfbContextWireValue -Entry $_ }) -join ', '
    throw "$key does not support the context_names parameter, so the context '$names' cannot be applied to it. Run this call against the local array with Invoke-PfbInContext -Context @() { ... }, or remove the session context with Clear-PfbContext."
}
