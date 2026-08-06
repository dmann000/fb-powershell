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

function Get-PfbEndpointContextScope {
    <#
    .SYNOPSIS
        Reads the capability map's contextScope for a method and endpoint.
    .DESCRIPTION
        ONE home for this lookup, for the same reason Get-PfbEndpointKey exists: both scope gates
        must agree, and both must degrade identically on absent metadata. Every read of
        contextScope goes through here -- never by indexing the map's contextScope member at a
        call site.

        Returns 'unknown' for a missing map, a missing entry, or an entry with no contextScope,
        so a caller has exactly one sentinel to test rather than three shapes of absence.
    .OUTPUTS
        [string]
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][string]$Endpoint,
        [Parameter()][AllowNull()]$CapabilityMap
    )

    if (-not $CapabilityMap) { return 'unknown' }
    $entry = $CapabilityMap.endpoints.(Get-PfbEndpointKey -Method $Method -Endpoint $Endpoint)
    if (-not $entry -or -not $entry.contextScope) { return 'unknown' }
    $entry.contextScope.scope
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

function Assert-PfbContextKindMatchesScope {
    <#
    .SYNOPSIS
        Throws when the context's KIND cannot address the endpoint's scope.
    .DESCRIPTION
        Reads contextScope from the capability map through Get-PfbEndpointContextScope. One
        uniform message rather than relaying the server's grab-bag (code 13 here, code 42 there,
        and a silent 200 for a local context). scope 'unknown' -- 19 operations -- SUPPRESSES the
        check: the gate must degrade, not throw, on absent metadata.

        Wire truth this encodes:
          array-scoped: bare array name OK; fleet-dot-arrays and group-dot-arrays OK (fan-out);
                        bare fleet name rejected (code 42).
                        A bare GROUP name is invalid on the wire too (code 42) but never reaches
                        this gate: ConvertTo-PfbContextWireValue runs first on each entry and
                        Assert-PfbContextEntryComposition rejects TopologyGroup+Object outright,
                        for EVERY endpoint rather than only array-scoped ones. That is the correct
                        home for it -- the combination addresses nothing anywhere -- so the doc
                        claim, not the code, was what needed fixing. The array branch below stays
                        written as the general "Kind is not Array" predicate rather than being
                        narrowed to Fleet: only Fleet can reach it today, and a fourth Kind would
                        be handled without an edit.
          fleet-scoped: bare fleet name OK; everything else rejected (code 13), including
                        .arrays forms and any array name other than the local one -- and the
                        local one only because middleware short-circuits it before validating,
                        which is not a scope grant.

        Called only from inside Invoke-PfbApiRequest's
        "$null -ne $resolvedContext -and Count -gt 0" block, so a non-null / non-empty re-check
        here would be unreachable -- same contract as Assert-PfbContextCardinality.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][string]$Endpoint,
        [Parameter(Mandatory)]$Context,
        [Parameter()][AllowNull()]$CapabilityMap
    )

    $scope = Get-PfbEndpointContextScope -Method $Method -Endpoint $Endpoint -CapabilityMap $CapabilityMap
    # Belt and braces, and NOT redundant even though it is currently behaviour-neutral: the loop
    # below already no-ops for any scope that is neither 'array' nor 'fleet', so deleting this
    # line changes nothing today and no test can pin it. It exists so that the day a third scope
    # value gains a branch down there, 'unknown' does not silently acquire that branch's meaning.
    # Do not delete it on the grounds that it is untested.
    if ($scope -eq 'unknown') { return }

    $key = Get-PfbEndpointKey -Method $Method -Endpoint $Endpoint

    foreach ($entry in $Context.Entries) {
        $wire = ConvertTo-PfbContextWireValue -Entry $entry

        if ($scope -eq 'array') {
            # A membership form (.arrays) fans out ACROSS arrays, so it is valid here; a bare
            # fleet name addresses an object that is not an array, so it is not. (A bare group
            # name cannot reach this line -- see the .DESCRIPTION note.)
            if ($entry.Form -eq 'Object' -and $entry.Kind -ne 'Array') {
                throw "$key is array-scoped, so '$wire' is not a valid context for it: a $($entry.Kind.ToLowerInvariant()) name addresses a $($entry.Kind.ToLowerInvariant())-level object, not an array. Use a member array name, or '$($entry.Name).arrays' to target every array in it."
            }
        }
        elseif ($scope -eq 'fleet') {
            if ($entry.Kind -ne 'Fleet' -or $entry.Form -ne 'Object') {
                throw "$key targets a fleet-scoped resource, which requires a bare fleet context; '$wire' is not one. Set a fleet context with Set-PfbContext -Context <fleet> -Kind Fleet, or run this call in one with Invoke-PfbInContext -Context <fleet> -Kind Fleet { ... }. Get the fleet name from Get-PfbFleet."
            }
        }
    }
}

function Assert-PfbContextRequired {
    <#
    .SYNOPSIS
        Throws when a fleet-scoped endpoint needs a fleet context and none is set.
    .DESCRIPTION
        Open question 7. On a fleet-scoped endpoint, omitting context_names does not resolve to a
        usable local view -- it fails, and confusingly: POST returns code 13 "Creating a preset in
        the array context is not supported", PUT/DELETE return code 6 "Preset does not exist", and
        a NAME-SCOPED GET returns code 6 as well. Throwing here names the requirement and the
        cmdlet that satisfies it instead.

        THE ONE EXCEPTION, and it is not the verb: an UNFILTERED read with no context WORKS,
        returning the locally replicated copy. The local view is list-only -- sufficient to
        enumerate, insufficient to resolve a name against -- so any call targeting by names= or
        ids= is in the mutation case regardless of its verb, and an unfiltered list is not. Keying
        this on the verb alone would break Get-PfbPresetWorkload, the only preset operation that
        works today.

        Called from the ELSE branch in Invoke-PfbApiRequest, so unlike the three shape gates this
        one legitimately sees BOTH the unset and the explicitly-empty context. That is deliberate:
        on a fleet-scoped mutation or name-scoped read, an explicit @() is exactly as broken as
        omitting the context. Do NOT add an empty-context bypass.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][string]$Endpoint,
        [Parameter()][AllowNull()][hashtable]$QueryParams,
        [Parameter()][AllowNull()]$CapabilityMap
    )

    if ((Get-PfbEndpointContextScope -Method $Method -Endpoint $Endpoint -CapabilityMap $CapabilityMap) -ne 'fleet') {
        return
    }

    if ($Method -eq 'GET') {
        $isNameScoped = $false
        if ($QueryParams) {
            foreach ($selector in 'names', 'ids') {
                if ($QueryParams.ContainsKey($selector) -and $QueryParams[$selector]) { $isNameScoped = $true }
            }
        }
        if (-not $isNameScoped) { return }   # unfiltered list: works without a context
    }

    $key = Get-PfbEndpointKey -Method $Method -Endpoint $Endpoint
    throw "$key targets a fleet-scoped resource and requires a fleet context, but none is set. Set one with Set-PfbContext -Context <fleet> -Kind Fleet, or run this call in one with Invoke-PfbInContext -Context <fleet> -Kind Fleet { ... }. Get the fleet name from Get-PfbFleet."
}
