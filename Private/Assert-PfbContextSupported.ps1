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

        READS ARE NARROWER THAN THE VERB, TWICE OVER, and both narrowings are measured rather
        than derived.

        First: an UNFILTERED read with no context WORKS, returning the locally replicated copy.
        Verified on one preset that provably existed (created, probed, deleted): ?names=<it> with
        no context returned code 6 while the unfiltered list returned 200 with that same object
        in it, and ?names=<it> with a fleet context returned 200. The local view is list-only --
        sufficient to enumerate, insufficient to resolve a name against. Keying this on the verb
        alone would break Get-PfbPresetWorkload, the only preset operation that works today.

        Second: even a NAME-SCOPED read only needs a context on the endpoints where that was
        measured, listed in $script:PfbNameScopedContextRequiredEndpoints. "scope: fleet" is not
        sufficient evidence -- three of the eight fleet-scoped endpoints contradict the
        derivation. Measured with no context: GET /topology-groups?names=<group> returns 200 with
        1 item, and /topology-groups/members and /topology-groups/arrays each return 200 with 2
        items. Throwing on those rejected calls the array answers happily. Non-GET verbs stay
        unconditional: the five preset write verbs fail without a context, and the topology-group
        write verbs are scope: array, so the early return above already covers them (confirmed
        live -- those writes succeed with no context).

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

    # Hoisted above the GET branch so the allowlist is matched against the SAME key the throw
    # names, built the one sanctioned way. Never build this key a second way -- see
    # Get-PfbEndpointKey on why a one-character drift fails silently.
    $key = Get-PfbEndpointKey -Method $Method -Endpoint $Endpoint

    if ($Method -eq 'GET') {
        $isNameScoped = $false
        if ($QueryParams) {
            foreach ($selector in 'names', 'ids') {
                if ($QueryParams.ContainsKey($selector) -and $QueryParams[$selector]) { $isNameScoped = $true }
            }
        }
        if (-not $isNameScoped) { return }   # unfiltered list: works without a context

        # And a name-scoped read only needs a context where that was MEASURED. scope: fleet is not
        # sufficient evidence: three of the eight fleet-scoped endpoints -- GET /topology-groups,
        # /topology-groups/members, /topology-groups/arrays -- answer a name-scoped context-free
        # read with 200, so deriving the rule from scope alone rejected working calls.
        if ($key -notin $script:PfbNameScopedContextRequiredEndpoints) { return }
    }

    throw "$key targets a fleet-scoped resource and requires a fleet context, but none is set. Set one with Set-PfbContext -Context <fleet> -Kind Fleet, or run this call in one with Invoke-PfbInContext -Context <fleet> -Kind Fleet { ... }. Get the fleet name from Get-PfbFleet."
}

function Resolve-PfbAuthorizationModel {
    <#
    .SYNOPSIS
        Best-effort read of the connected admin's authorization_model.
    .DESCRIPTION
        Only LDAP/SAML remote admins are 'dynamic'. Since 4.5.0 an admin can create additional
        named LOCAL users with the same privileges, and the 4.8.1 service-account admin type
        is also local -- so pureuser, custom local users and service accounts are ALL 'static'.
        This is not "pureuser vs everyone".

        Returns $null rather than throwing on any failure. An indeterminate model must never fail
        a Connect-PfbArray, because this data drives a diagnostic and not a correctness gate.
        THREE distinct routes reach indeterminate, and the third is the common one:
          1. GET /admins 403s under a restrictive management-access policy.
          2. An OAuth2 client has no username to match.
          3. -ApiToken -- the DEFAULT parameter set -- never populates Username at all, so the
             early return below fires and the gate is permanently inert for it. Only the
             Credential, PSCredential and Certificate sets normalize Username
             (Connect-PfbArray.ps1:206-212). This is a correct application of the fail-open
             ruling (no username, no evidence), not a bug: do NOT "fix" it by inferring a model
             from the token or by defaulting to 'static'.

        NO .items UNWRAP. Invoke-PfbApiRequest already unwraps the envelope itself -- it collects
        $response.items into $allItems and returns $allItems.ToArray(), an object[] of admin
        objects (Invoke-PfbApiRequest.ps1:287-291, :328). Reading .items off that value yields
        nothing on every real array, which silently returned $null forever and left the gate
        inert. Measured on both editions. -Raw would give the raw envelope but bypasses the
        pagination and error handling below its early return, and no other list read in the
        module uses it. Never reintroduce an .items read here.

        Matches on name rather than taking row 0: reading the WRONG admin's model is worse than
        reading none, because a 'static' read off a peer's row would hard-throw a legitimate LDAP
        session out of Set-PfbContext.

        Cost on a 403: more than one round trip. Invoke-PfbApiRequest's auto-reconnect gate fires
        on 403 as well as 401 by design (:223-232 -- real arrays answer 403, not 401, for a bad
        token), so a legitimate management-access-policy 403 is indistinguishable from an expired
        token and costs ~3 round trips plus a spurious re-login per connect. Non-fatal -- the
        catch below contains it -- and deliberately NOT worked around here: the only real fix
        touches reconnect logic shared by every cmdlet in the module. Parked for live measurement
        in Task 15. Do not change the shared reconnect logic on this note alone.

        THE PROBE IS ALWAYS CONTEXT-FREE, enforced HERE rather than at the call sites so it holds
        for both of them and for any future third one. This asks who the CONNECTED admin is -- an
        identity question about the local session -- so routing it through a context would answer
        it from a different array.

        An earlier revision relied on a positional precondition instead: "this only runs at connect,
        when DefaultContext and ContextOverride are both still $null". That was true of the single
        original call site and became FALSE the moment Set-PfbContext became the second one, because
        its $copy inherits the connection's EXISTING context. GET /admins declares context_names
        (scope: array), so none of the three shape gates stops it, and the probe went out as
        ?names=<user>&context_names=<previous context>. Three outcomes, all wrong: an Array/.arrays
        context routed the identity probe to a REMOTE array's admin table; a bare Fleet context made
        the kind/scope gate throw INSIDE this function, so the catch below silently downgraded a
        known 'dynamic' to $null and the gate failed open for the rest of that connection's life;
        an unreachable member did the same. Stripping the context makes the invariant a property of
        this function rather than a property of where it is called from.

        Do NOT "fix" this by passing -QueryParams @{ context_names = @() }: with $hasContext false
        the injection block is skipped, so that key survives into ConvertTo-PfbQueryString and puts
        a bare context_names= on the wire.

        No recursion risk: because the probe carries no context, Invoke-PfbApiRequest's $hasContext
        is false for it, so none of the four shape gates -- including
        Assert-PfbContextAuthorizationModel, the only one that would read back into this state --
        can fire. That now FOLLOWS FROM the stripping below rather than from when we happen to be
        called, which is the whole point of moving the guarantee in here.
    .OUTPUTS
        [string]
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][PSCustomObject]$Array)

    if (-not $Array.Username) { return $null }
    try {
        # Shallow clone, then null BOTH context slots -- Resolve-PfbRequestContext reads
        # ContextOverride first, then DefaultContext, so leaving either populated re-opens the
        # defect. A copy rather than mutate-and-restore: the caller's object must not be touched
        # even transiently, since Invoke-PfbInContext may be holding it mid-block.
        #
        # KNOWN AND RULED BENIGN, with the reasoning recorded rather than just the conclusion,
        # because the conclusion depends on facts that could change. Invoke-PfbApiRequest's
        # proactive-refresh (:142-152) and 401/403-reconnect (:260-271) paths write the new token
        # onto whatever $Array they were handed AND install that same object into
        # $script:PfbDefaultArray / $script:PfbArrays. Handed this probe copy, that means (i) a
        # refreshed token lands on the copy and is discarded, so the caller keeps a stale token,
        # and (ii) the object installed in the caches is this context-stripped probe rather than
        # the real connection.
        #
        # Why neither harms today:
        #   - The cache substitution only PERSISTS if the gate then throws. Otherwise
        #     Update-PfbConnectionCache (Set-PfbContext) or the tail-end cache assignment
        #     (Connect-PfbArray) runs afterwards and overwrites the slot with the right object.
        #   - A gate throw requires a STATIC admin, and a static admin can never have had a context
        #     cached in the first place: Connect-PfbArray gates before its cache write, and
        #     Set-PfbContext gates before Update-PfbConnectionCache. So a stripped copy left in the
        #     cache is never a LOSS of context relative to what was cached -- it is a valid
        #     equivalent connection.
        #   - The stale token self-heals on the next request via the reactive 401 path.
        #
        # THE DEPENDENCY, stated so it can be checked rather than re-derived: this stops being
        # benign if a future change ever (a) lets a static-model admin hold a context, or (b) moves
        # either gate to AFTER its cache write. Either one makes a stripped probe copy able to
        # persist in the caches in place of a connection that legitimately had a context.
        $probe = $Array.PSObject.Copy()
        $probe.DefaultContext = $null
        $probe.ContextOverride = $null

        $admins = @(Invoke-PfbApiRequest -Array $probe -Method 'GET' -Endpoint 'admins' -QueryParams @{ names = $Array.Username })
        $model = ($admins | Where-Object { $_.name -eq $Array.Username } | Select-Object -First 1).authorization_model
        if ($model) { return [string]$model }
        return $null
    }
    catch {
        Write-Verbose "Could not determine the authorization model for '$($Array.Username)' on $($Array.Endpoint): $($_.Exception.Message). Cross-array context checks will not be pre-validated."
        return $null
    }
}

function Assert-PfbContextAuthorizationModel {
    <#
    .SYNOPSIS
        Throws when a static-authorization-model admin sets any Fusion context.
    .DESCRIPTION
        Diagnostic, never a security boundary. A static-model admin's cross-array call fails
        loudly on the wire with 'Operation not permitted' (code 20), so this gate can never turn
        a would-be wrong-target success into a failure -- it only replaces an opaque server error
        with the actionable reason.

        Fails OPEN on an indeterminate model and CLOSED on a known-static one. Those are not in
        tension: $null means no evidence (an OAuth2 client with no username, or GET /admins 403
        under a restrictive management-access policy), while 'static' is positive evidence the
        call cannot work. Failing closed on the unknown case would block legitimate OAuth2 and
        restricted-policy sessions while protecting nothing.

        Takes -Array, unlike the two pure shape gates, because the model is a property of the
        SESSION rather than of the endpoint -- and takes no -Endpoint or -CapabilityMap for the
        same reason. -Context does not affect WHETHER this throws (there is no local-array
        exemption, so every context is rejected once the model is static) but it is named in the
        message, which is what earns it its mandatory slot: the caller sees which values were
        rejected rather than a generic complaint.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][PSCustomObject]$Array,
        [Parameter(Mandatory)]$Context
    )

    # Fail OPEN on an indeterminate model. See Resolve-PfbAuthorizationModel.
    if ($Array.AuthorizationModel -ne 'static') { return }

    # NO local-array exemption. An earlier draft let a static admin through when the context
    # named only the connected array, but (a) the connection object carries no array NAME to
    # compare against -- it has Endpoint, an IP or hostname -- so the check could only ever have
    # worked against an invented test fixture, and (b) maintainer ruling 2026-08-05: a static
    # user has no business setting a context at all. Naming your own array buys nothing anyway,
    # since the server short-circuits it. Do not reintroduce the exemption or an ArrayName field.
    $names = @($Context.Entries | ForEach-Object { ConvertTo-PfbContextWireValue -Entry $_ }) -join ', '
    throw "Setting a Fusion context requires a dynamic-authorization-model (LDAP/SAML) admin; static-model admins, including pureuser and other local accounts such as custom local users and service accounts, are not permitted. The connected admin '$($Array.Username)' is static-model, so the context '$names' would return 'Operation not permitted' (code 20) on any cross-array call regardless of its value."
}

function Add-PfbContextErrorAnnotation {
    <#
    .SYNOPSIS
        Annotates a context-targeting API failure with the active context and how to change it.
    .DESCRIPTION
        The array answers an unresolvable context with code 42 "Cannot find array in fleet",
        which reaches the caller as a bare message naming neither the offending value nor the
        fact that a session default set several calls earlier is responsible. With contextScope
        in hand the annotation can also name the required KIND, not merely the value that
        failed.

        THE code 20 CASE IS THE REACTIVE HALF OF Assert-PfbContextAuthorizationModel, not a
        duplicate of it. That gate can only throw proactively when the authorization model is
        known, and it is NOT known for an -ApiToken session (no Username to look up, so
        Resolve-PfbAuthorizationModel returns $null and the gate fails open) nor for a session
        that only ever supplies a context through Invoke-PfbInContext. In both cases the wire's
        bare code 20 "Operation not permitted" is the only signal the user ever gets. Do not
        remove this branch on the grounds that Task 11's gate "already covers it".

        Keying on a bare 'Operation not permitted' is safe HERE specifically because the function
        has already returned unless a context is active: a permission failure with a context set
        is overwhelmingly this cause. The annotation is advisory and hedged with "may be" -- a
        wrong hint costs nothing, a missing one costs a support case -- so do not try to narrow
        it further.
    .OUTPUTS
        [string]
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Message,
        [Parameter()][AllowNull()]$Context,
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][string]$Endpoint,
        [Parameter()][AllowNull()]$CapabilityMap
    )

    # Tri-state, same predicate as Invoke-PfbApiRequest's $hasContext: $null is unset and an
    # existing context with no entries is an explicit "run locally". Neither has a context value
    # to name, so both leave the message untouched. Never truthiness on the context OBJECT.
    if ($null -eq $Context -or @($Context.Entries).Count -eq 0) { return $Message }

    # A permission failure gets a DIFFERENT explanation from a targeting failure, so it is
    # matched separately rather than folded into the alternation below.
    $isPermissionFailure = $Message -match 'Operation not permitted'

    # Only the server's context-targeting failures. Matching more broadly would append
    # context noise to unrelated errors.
    if (-not $isPermissionFailure -and
        $Message -notmatch 'Cannot find array in fleet|Executor not found|Invalid context|Cannot specify (parameter|context)') {
        return $Message
    }

    $names = @($Context.Entries | ForEach-Object { ConvertTo-PfbContextWireValue -Entry $_ }) -join ', '
    $key   = Get-PfbEndpointKey -Method $Method -Endpoint $Endpoint
    $scope = Get-PfbEndpointContextScope -Method $Method -Endpoint $Endpoint -CapabilityMap $CapabilityMap

    $requirement = if ($isPermissionFailure) {
        " The connected admin may be a static-authorization-model account -- Fusion contexts require a dynamic-model (LDAP/SAML) admin, and local users and service accounts are all static."
    }
    else {
        switch ($scope) {
            'fleet' { " $key targets a fleet-scoped resource, which requires a bare fleet context." }
            'array' { " $key is array-scoped: use a member array name, or '<fleet>.arrays' to target every array in a fleet." }
            default { '' }
        }
    }

    "$Message (active context: $names.$requirement Change it with Set-PfbContext, remove it with Clear-PfbContext, or override it for one call with Invoke-PfbInContext.)"
}
