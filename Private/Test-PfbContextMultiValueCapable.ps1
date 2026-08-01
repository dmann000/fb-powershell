function Test-PfbContextMultiValueCapable {
    <#
    .SYNOPSIS
        THE single declared home of the Fusion `context_names` cardinality rule: is an
        endpoint with the given HTTP method able to accept MANY context names, or exactly
        one?
    .DESCRIPTION
        The rule:

            GET is multi-context-capable. POST / PATCH / DELETE are single-context-only.

        This function is deliberately the ONLY place that rule is expressed. Context
        injection (PR #22) must call this rather than testing the verb inline, and the
        spec-vs-module-assumption check in tools/lib/PfbContextRuleTools.ps1 dot-sources
        THIS FILE and executes THIS function rather than re-deriving the rule. A check
        that re-implements the rule it is checking verifies nothing, so the two must never
        drift into separate copies.

        Why a verb rule rather than reading cardinality out of the OpenAPI spec: the
        cardinality is NOT machine-readable. The spec expresses it only through which
        component a parameter `$ref`s -- `Context_names_get` (multi-value) versus
        `Context_names` (size-1) -- and those two components have *identical* schemas.
        There is no `maxItems`; the size-1 restriction lives only in free-text
        `description`. The component name is therefore the sole mechanical signal, and it
        has been observed to be wrong (see below).

        This rule is GROUND TRUTH -- live-tested against a FlashBlade plus upstream
        confirmation. It is deliberately NOT derived from the spec, and must not be
        "corrected" to match the spec when the two disagree. Where they disagreed, the
        spec was the side that was wrong:

          - fb2.26 and fb2.27 had `DELETE /management-access-policies` referencing
            `Context_names_get` (multi-value), contradicting this rule. Investigated and
            confirmed an upstream documentation/spec defect. NO exception was ever
            implemented here -- the clean verb rule was kept.
          - REST 2.28 fixed it: that endpoint now references `Context_names`. As of fb2.28
            the spec and this rule agree on every endpoint carrying `context_names`.

        The check exists so that a FUTURE divergence -- in particular a genuine
        multi-context mutation endpoint, the case where this rule would be the wrong side
        -- gets noticed instead of silently mis-serving callers.
    .PARAMETER Method
        The endpoint's HTTP method. Case-insensitive.
    .OUTPUTS
        [bool] -- $true when the method may carry multiple context names (fan-out),
        $false when it accepts exactly one.
    .NOTES
        Throws on a method the rule has no verdict for. Returning $false for an
        unrecognized verb would quietly assume "size-1" for a verb nobody has reasoned
        about -- precisely the silent-wrongness this rule's verification is meant to
        prevent. Failing loudly forces a human decision.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Method
    )

    switch ($Method.ToUpperInvariant()) {
        'GET' { return $true }
        'POST' { return $false }
        'PATCH' { return $false }
        'PUT' { return $false }
        'DELETE' { return $false }
        default {
            throw ("Test-PfbContextMultiValueCapable: no context-cardinality verdict is " +
                "defined for HTTP method '$Method'. The Fusion context_names verb rule " +
                'covers GET/POST/PUT/PATCH/DELETE only -- extend this function ' +
                'deliberately rather than assuming a default.')
        }
    }
}
