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

function Test-PfbEndpointDeclaresContextNames {
    <#
    .SYNOPSIS
        Does this capability-map endpoint entry declare the context_names parameter?
    .DESCRIPTION
        ONE home for this question, for the same reason Get-PfbEndpointKey exists: both context
        gates need it and they must agree. Assert-PfbContextCapability uses it to decide whether
        to throw; Assert-PfbContextCardinality uses it as a precondition, so an endpoint that
        takes no context at all is left entirely to the capability gate rather than being told to
        "narrow the context" -- advice that cannot possibly work there.

        This is NOT the same question as "did Resolve-PfbParameterComponent return a component".
        That helper falls back to the map's DEFAULT component for the 256 entries that do not
        declare the parameter, so a non-null component is no evidence the endpoint supports a
        context. Only the parameters collection is evidence.
    .OUTPUTS
        [bool]
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][AllowNull()]$EndpointEntry
    )

    if (-not $EndpointEntry -or -not $EndpointEntry.parameters) { return $false }
    return (@($EndpointEntry.parameters.PSObject.Properties.Name) -contains $script:PfbContextParameterName)
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

    # Shared with Assert-PfbContextCardinality -- one home for "does this entry declare it".
    if (Test-PfbEndpointDeclaresContextNames -EndpointEntry $entry) {
        return   # Assert-PfbApiCapability owns "recorded but array too old"
    }

    # Beyond the scanned range the map has no evidence, so proceed permissively rather than
    # punish a packaging lag the caller cannot see.
    if (Test-PfbCapabilityMapCoverage -NegotiatedVersion $Array.ApiVersion -CapabilityMap $CapabilityMap) {
        return
    }

    $names = @($Context.Entries | ForEach-Object { ConvertTo-PfbContextWireValue -Entry $_ }) -join ', '
    throw "$key does not support the context_names parameter, so the context '$names' cannot be applied to it. Run this call against the local array with Invoke-PfbInContext -Context @() { ... }, or remove the session context with Clear-PfbContext."
}

function Assert-PfbContextCardinality {
    <#
    .SYNOPSIS
        Throws when a multi-value context targets an endpoint that accepts only one.
    .DESCRIPTION
        Converts 400 code 15 "Multiple location contexts are not allowed." into an actionable
        message. The rule itself lives in Test-PfbContextMultiValueCapable (#73) and the
        component resolution in Resolve-PfbParameterComponent (#74) -- this function only
        feeds them, deliberately, so the multi-value component literal is compared in exactly
        one place in Private/ -- inside the predicate, never here.

        Called only from inside Invoke-PfbApiRequest's
        "$null -ne $resolvedContext -and Count -gt 0" block, so a non-null / non-empty
        re-check here would be unreachable. The Count -le 1 early return below is about
        CARDINALITY, not emptiness.

        SCOPE. This gate rules only on endpoints that actually DECLARE context_names. An entry
        that does not declare it (or is absent from the map) is out of scope and returns
        silently: Resolve-PfbParameterComponent would hand back the map's default component for
        such an entry, the cardinality rule would then read $false, and this gate would advise
        narrowing a context the endpoint cannot take at all. Worse, that would fire precisely
        where Assert-PfbContextCapability deliberately abstains -- an array beyond the map's
        scanned range, where absence is no evidence -- reversing its permissiveness. The
        precondition makes this gate independent of which gate runs first.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][string]$Endpoint,
        [Parameter(Mandatory)]$Context,
        [Parameter()][AllowNull()]$CapabilityMap
    )

    if (@($Context.Entries).Count -le 1) { return }
    if (-not $CapabilityMap) { return }

    $key = Get-PfbEndpointKey -Method $Method -Endpoint $Endpoint
    $entry = $CapabilityMap.endpoints.$key
    # Out of scope unless the endpoint declares context_names -- see SCOPE above. This also
    # covers an entry absent from the map entirely, so the gate is order-independent: whether
    # Assert-PfbContextCapability runs before or after, this returns silently either way.
    if (-not (Test-PfbEndpointDeclaresContextNames -EndpointEntry $entry)) { return }

    $component = Resolve-PfbParameterComponent -EndpointEntry $entry `
        -ParameterName $script:PfbContextParameterName `
        -ParameterComponentDefaults $CapabilityMap.parameterComponentDefaults
    $declaresAllowErrors = @($entry.parameters.PSObject.Properties.Name) -contains $script:PfbAllowErrorsParameterName

    if (Test-PfbContextMultiValueCapable -Method $Method -ContextComponent $component -DeclaresAllowErrors $declaresAllowErrors) {
        return
    }

    $names = @($Context.Entries | ForEach-Object { ConvertTo-PfbContextWireValue -Entry $_ }) -join ', '
    throw "$key accepts only one context, but $(@($Context.Entries).Count) were given ($names). Narrow the context to a single name. To target every array in a fleet or topology group with one context, use -AllArrays instead of listing members."
}
