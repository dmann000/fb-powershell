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

        Deliberately returns the scope ALONE and drops contextScope.provenance. Adjudicated
        2026-08-06, not an oversight -- the gates are meant to rule on the scope regardless of
        which of the three provenances produced it, because 'default' is a real answer and not
        absent metadata:

        - 'declared'    -- upstream carries an x-pure-remote-execution-context-domains-override
                           for this operation, so the scope is upstream's own statement.
        - 'live-tested' -- no override, but upstream flagged the operation x-pure-incomplete-gre
                           (its machine-readable marker for "my remote-execution annotation is
                           unfinished here"), and we hold a curated live-tested reading.
        - 'default'     -- no override AND not flagged x-pure-incomplete-gre. Upstream considers
                           its annotation COMPLETE at this operation, and a complete annotation on
                           a fleet-scoped operation would have to carry an override. So the
                           absence of an override is itself evidence of 'array'.

        'unknown' is therefore the sentinel reserved for upstream-flagged-incomplete (and for the
        structural absences above) -- which is exactly why 'unknown' alone suppresses the
        kind-vs-scope gate while 'default' does not. Do not "degrade" the gate on 'default': that
        would discard the only signal 604 endpoints have.
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

function Resolve-PfbAdminLocality {
    <#
    .SYNOPSIS
        Best-effort read of whether the connected admin authenticates locally or remotely.
    .DESCRIPTION
        Reads `is_local` from the admin's own row and returns 'local' or 'remote'. MEASURED RULE
        (controlled experiment on FB-A, REST 2.26, 2026-08-06): remote => cross-array contexts are
        PERMITTED; local => cross-array is denied with 'Operation not permitted' (code 20).
        Since 4.5.0 an admin can create additional named LOCAL users with the same privileges, and
        the 4.8.1 service-account admin type is also local -- so pureuser, custom local users and
        service accounts are ALL local. This is not "pureuser vs everyone".

        DO NOT switch this back to `authorization_model`. That was the original design and it was
        falsified: a STATIC-REMOTE admin is is_local=$false with authorization_model='static', and
        the array SERVES its context calls. Flipping the model on a remote admin changed nothing in
        either direction. `authorization_model` only says where POLICIES are read from, which is
        orthogonal to whether the fleet recognizes the identity, so reading it here produced false
        positives that blocked working sessions.

        `is_local` is on Admin from REST 2.17 -- the same floor as context_names -- so no version
        guard is needed or wanted here. Do not use `admin_type` (same signal, but 2.24+, which
        would reintroduce the version-era problem for nothing); `user_source` does not exist in the
        REST spec at any version (verified 2.17/2.24/2.26/2.28).

        Returns $null rather than throwing on any failure. An indeterminate locality must never fail
        a Connect-PfbArray, because this data drives a diagnostic and not a correctness gate.
        Two routes reach indeterminate, both narrow:
          1. GET /admins 403s under a restrictive management-access policy.
          2. There is no Username to match, so the early return below fires. Since Task 12b that
             means only a Certificate/OAuth2 session whose -Username somehow never bound, or a
             login whose 200 body carried no `username` at all -- malformed, not any supported
             version. Every parameter set now populates Username: ApiToken, Credential and
             PSCredential take it from the /api/login response body (which returns it in every
             REST version 2.0-2.28), and Certificate has -Username as Mandatory.
             This is a correct application of the fail-open ruling (no username, no evidence), not
             a bug: do NOT "fix" it by inferring a locality from the token or by defaulting to
             'local'.

        The DEFAULT -ApiToken set used to be a third, and by far the commonest, route here: Username
        was only the caller's typed value and that set has no -Username parameter, so this function
        early-returned and the gate was permanently inert for it. That is fixed (Task 12b). Do not
        reintroduce a note claiming ApiToken cannot reach the lookup.

        NO .items UNWRAP. Invoke-PfbApiRequest already unwraps the envelope itself -- it collects
        $response.items into $allItems and returns $allItems.ToArray(), an object[] of admin
        objects (Invoke-PfbApiRequest.ps1:287-291, :328). Reading .items off that value yields
        nothing on every real array, which silently returned $null forever and left the gate
        inert. Measured on both editions. -Raw would give the raw envelope but bypasses the
        pagination and error handling below its early return, and no other list read in the
        module uses it. Never reintroduce an .items read here.

        Matches on name rather than taking row 0: reading the WRONG admin's locality is worse
        than reading none, because an is_local=$true read off a peer's row would hard-throw a
        legitimate LDAP session out of Set-PfbContext.

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
        known 'remote' to $null and the gate failed open for the rest of that connection's life;
        an unreachable member did the same. Stripping the context makes the invariant a property of
        this function rather than a property of where it is called from.

        Do NOT "fix" this by passing -QueryParams @{ context_names = @() }: with $hasContext false
        the injection block is skipped, so that key survives into ConvertTo-PfbQueryString and puts
        a bare context_names= on the wire.

        No recursion risk: because the probe carries no context, Invoke-PfbApiRequest's $hasContext
        is false for it, so none of the four shape gates -- including
        Assert-PfbContextAdminLocality, the only one that would read back into this state --
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
        #   - A gate throw requires a LOCAL admin, and a local admin can never have had a context
        #     cached in the first place: Connect-PfbArray gates before its cache write, and
        #     Set-PfbContext gates before Update-PfbConnectionCache. So a stripped copy left in the
        #     cache is never a LOSS of context relative to what was cached -- it is a valid
        #     equivalent connection.
        #   - The stale token self-heals on the next request via the reactive 401 path.
        #
        # THE DEPENDENCY, stated so it can be checked rather than re-derived: this stops being
        # benign if a future change ever (a) lets a local admin hold a context, or (b) moves
        # either gate to AFTER its cache write. Either one makes a stripped probe copy able to
        # persist in the caches in place of a connection that legitimately had a context.
        $probe = $Array.PSObject.Copy()
        $probe.DefaultContext = $null
        $probe.ContextOverride = $null

        $admins = @(Invoke-PfbApiRequest -Array $probe -Method 'GET' -Endpoint 'admins' -QueryParams @{ names = $Array.Username })
        $row = $admins | Where-Object { $_.name -eq $Array.Username } | Select-Object -First 1
        # $null -ne, never truthiness: is_local is a BOOLEAN, so $false is a real answer ('remote')
        # and must not collapse into the indeterminate case the way -not $row.is_local would.
        if ($null -ne $row -and $null -ne $row.is_local) {
            return $(if ($row.is_local) { 'local' } else { 'remote' })
        }
        return $null
    }
    catch {
        Write-Verbose "Could not determine whether '$($Array.Username)' on $($Array.Endpoint) is a local or remote admin: $($_.Exception.Message). Cross-array context checks will not be pre-validated."
        return $null
    }
}

function Assert-PfbContextAdminLocality {
    <#
    .SYNOPSIS
        Throws when a LOCALLY authenticated admin sets any Fusion context.
    .DESCRIPTION
        Diagnostic, never a security boundary. For a CROSS-ARRAY context a local admin's call
        fails loudly on the wire with 'Operation not permitted' (code 20), so there this gate
        only replaces an opaque server error with the actionable reason.

        It is NOT free of behavioural cost, and this docstring must not claim otherwise: a local
        admin CAN successfully target its OWN array. Measured on FB-A 2026-08-06 -- pureuser with
        context_names=FB-A returned data; only cross-array attracts code 20. So for a
        self-targeting context this gate DOES convert a would-be success into a failure. That is
        INTENDED -- maintainer ruling 2026-08-05, no local-array exemption; see the comment at the
        throw below, which states the same thing from the other direction -- but it is a real
        rejection of a call the server would have served, not merely a nicer error message. An
        earlier revision of this paragraph asserted the opposite as a safety property; it was
        falsified by live testing. Do not restore it.

        Fails OPEN on an indeterminate locality and CLOSED on a known-local one. Those are not in
        tension: $null means no evidence (an OAuth2 client with no username, or GET /admins 403
        under a restrictive management-access policy), while 'local' is positive evidence the
        cross-array call cannot work. Failing closed on the unknown case would block legitimate OAuth2 and
        restricted-policy sessions while protecting nothing.

        Takes -Array, unlike the two pure shape gates, because the locality is a property of the
        SESSION rather than of the endpoint -- and takes no -Endpoint or -CapabilityMap for the
        same reason. -Context does not affect WHETHER this throws (there is no local-array
        exemption, so every context is rejected once the admin is local) but it is named in the
        message, which is what earns it its mandatory slot: the caller sees which values were
        rejected rather than a generic complaint.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][PSCustomObject]$Array,
        [Parameter(Mandatory)]$Context
    )

    # Fail OPEN on an indeterminate locality. See Resolve-PfbAdminLocality.
    if ($Array.AdminLocality -ne 'local') { return }

    # NO local-array exemption. An earlier draft let a local admin through when the context
    # named only the connected array, but (a) the connection object carries no array NAME to
    # compare against -- it has Endpoint, an IP or hostname -- so the check could only ever have
    # worked against an invented test fixture, and (b) maintainer ruling 2026-08-05: a local
    # user has no business setting a context at all. Naming your own array buys nothing anyway,
    # since the server short-circuits it. Do not reintroduce the exemption or an ArrayName field.
    $names = @($Context.Entries | ForEach-Object { ConvertTo-PfbContextWireValue -Entry $_ }) -join ', '
    throw "Setting a Fusion context requires a remotely authenticated (LDAP/SAML) admin; local accounts, including pureuser, custom local users and service accounts, are not permitted. The connected admin '$($Array.Username)' is a local account, so the context '$names' would return 'Operation not permitted' (code 20) on any cross-array call."
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

        THE code 20 CASE IS THE REACTIVE HALF OF Assert-PfbContextAdminLocality, not a
        duplicate of it. That gate can only throw proactively when the admin locality is
        known, and it is NOT known for a session that only ever supplies a context through
        Invoke-PfbInContext (no resolution site is ever reached), nor when GET /admins 403s under
        a restrictive management-access policy. In those cases the wire's bare code 20 "Operation
        not permitted" is the only signal the user ever gets. Do not remove this branch on the
        grounds that Task 11's gate "already covers it".

        It is NO LONGER also needed for the -ApiToken set specifically: Task 12b populates Username
        from the /api/login response body there, so that session now resolves its locality and the
        proactive gate does fire. The Invoke-PfbInContext hole is untouched by that and is why this
        branch stays.

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
        " The connected admin may be a local account -- Fusion contexts require a remotely authenticated (LDAP/SAML) admin; pureuser, custom local users and service accounts are all local."
    }
    else {
        switch ($scope) {
            'fleet' { " $key targets a fleet-scoped resource, which requires a bare fleet context." }
            'array' { " $key is array-scoped: use a member array name, or '<fleet>.arrays' to target every array in a fleet." }
            default { '' }
        }
    }

    # The REMEDY is branch-specific, and must stay that way. Offering the context cmdlets to a
    # local admin points them at the one lever that cannot help: no context VALUE works for
    # that account, so "change it / clear it / override it" is wrong advice delivered immediately
    # after correctly explaining that the account is the problem. Naming the active context value
    # is still right there -- that is diagnostic, not advice. Do NOT re-merge these two clauses.
    $remedy = if ($isPermissionFailure) {
        ' Reconnect as a remotely authenticated (LDAP/SAML) admin to use a context at all; changing or clearing the context will not help.'
    }
    else {
        ' Change it with Set-PfbContext, remove it with Clear-PfbContext, or override it for one call with Invoke-PfbInContext.'
    }

    "$Message (active context: $names.$requirement$remedy)"
}
