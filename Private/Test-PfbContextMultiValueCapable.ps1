function Test-PfbContextMultiValueCapable {
    <#
    .SYNOPSIS
        THE single declared home of the Fusion `context_names` cardinality rule: can this
        endpoint accept MANY context names, or exactly one?
    .DESCRIPTION
        The rule, ratified in rev 3 of docs/design/fusion-context-injection.md (section 8):

            An endpoint is multi-context-capable if and only if its `context_names`
            parameter resolves to component `Context_names_get` AND the endpoint also
            declares `allow_errors`.

        Both facts are recorded per endpoint in Data/PfbCapabilityMap.json, so at runtime
        this is a lookup, not a derivation. Against the committed map (generatedFrom
        2.0-2.28) the rule yields 135 capable endpoints of the 139 referencing the
        multi-value component; against fb2.27, 134 of 139.

        This function is deliberately PURE -- no map loading, no file I/O. Each caller
        supplies facts from its own source: the maintainer drift check from the capability
        map or from a single spec version, the context-injection path from the map entry it
        has already resolved. That is what lets both execute the same rule instead of
        re-deriving it.

        WHY NOT THE HTTP VERB. Rev 2 proposed a clean verb split -- GET multi-value,
        mutations size-1 -- and this file previously described it as ground truth. It is
        not, and that claim has been withdrawn. Live testing on 2026-08-01 against FB-A
        (Purity//FB 4.8.2, REST 2.26, coordinator of fleet `cc-test-fleet` with FB-C as a
        remote member) disproved it: four fleet-scoped GETs reject any two-name context
        with `400 code 15 "Multiple location contexts are not allowed."` --
        `GET /presets/workload`, `GET /topology-groups`, `GET /topology-groups/arrays`,
        `GET /topology-groups/members`. `code 15` fires BEFORE the cross-array
        authorization gate that yields `code 20` on control endpoints, so it is structural
        to the endpoint, not a permission artifact. A fleet-scoped endpoint has exactly one
        meaningful context -- the fleet -- so multi-value is not merely restricted there,
        it is meaningless. Their spec entries reference `Context_names_get` in error
        (upstream defect, in review; still present at 2.28). See Appendix A of the design
        doc for the full evidence and Appendix B for the defect registry.

        WHY `allow_errors` RATHER THAN THE COMPONENT NAME ALONE. The component reference is
        wrong for five endpoints (those four plus `DELETE /management-access-policies` in
        2.26/2.27, since fixed in 2.28), while `allow_errors` is correct on every case for
        which evidence exists. A genuinely multi-context endpoint needs a partial-failure
        story, so its absence is strong evidence the endpoint cannot fan out -- which is
        how the upstream bug report characterizes the defect ("missing e.g. `allow_errors`
        / HTTP 207 / `_context`").

        WHY NOT HTTP 207. It is the strictest and most accurate signal, and the one
        upstream tooling uses, but the capability map records the request surface only and
        holds no response data at all, so it is unavailable at runtime. Gating on it would
        also treat 11 endpoints of unknown status as size-1 on no evidence. It serves as a
        corroborating signal for the maintainer drift check, sourced from tools/specs, and
        never as a runtime gate.

        The verb survives ONLY as a fallback for an endpoint with no component signal at
        all -- i.e. absent from the capability map entirely. It is not the rule.
    .PARAMETER Method
        The endpoint's HTTP method. Case-insensitive. Used only in the no-signal fallback.
    .PARAMETER ContextComponent
        The component the endpoint's `context_names` parameter resolves to, e.g.
        'Context_names_get' or 'Context_names'. Pass $null or omit when no component is
        known -- that, and only that, selects the verb fallback.
    .PARAMETER DeclaresAllowErrors
        Whether the endpoint declares an `allow_errors` parameter.
    .OUTPUTS
        [bool] -- $true when the endpoint may carry multiple context names, $false when it
        accepts exactly one.
    .NOTES
        The fallback throws on a method it has no verdict for. Returning $false there would
        quietly assume "size-1" for a verb nobody has reasoned about; failing loudly forces
        a human decision.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Method,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$ContextComponent,

        [Parameter(Mandatory)]
        [bool]$DeclaresAllowErrors
    )

    if (-not [string]::IsNullOrWhiteSpace($ContextComponent)) {
        return ($ContextComponent -eq 'Context_names_get') -and $DeclaresAllowErrors
    }

    # No component signal at all -- the endpoint is not in the capability map. Fall back to
    # the verb, which is a guess, not the rule.
    switch ($Method.ToUpperInvariant()) {
        'GET' { return $true }
        'POST' { return $false }
        'PATCH' { return $false }
        'PUT' { return $false }
        'DELETE' { return $false }
        default {
            throw ("Test-PfbContextMultiValueCapable: no context-cardinality verdict is " +
                "defined for HTTP method '$Method', and no component signal was supplied " +
                'to decide it on evidence. The verb fallback covers GET/POST/PUT/PATCH/' +
                'DELETE only -- extend this function deliberately rather than assuming a ' +
                'default.')
        }
    }
}
