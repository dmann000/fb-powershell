# Empty-pipeline selector policy (issue #126).
# Design: docs/design/empty-pipeline-selector-policy-spec.md
#
# A SELECTOR is a query key whose bound the caller can enumerate or author. Two forms only:
# identity (names, ids, *_names, *_ids) and a caller-authored predicate, which today means
# 'filter' alone. Everything else is a scope or shaping key: it selects among SERVER-DEFINED
# partitions whose membership the caller does not control. The test for a key nobody has
# classified yet -- if the SERVER decides how many objects come back, it is scope.
#
# This is a DENYLIST on purpose, and the direction matters. An allowlist of selector spellings
# would have to know policy_names, remote_names, member_names and bucket_names; every one it
# missed would read as "not a selector" and SUPPRESS a working call -- a new failure that did not
# exist before. The denylist's miss direction is to ISSUE the request, which is the pre-#126
# behaviour of that call.
#
# That default is a COMPATIBILITY property, not a safety one, and it is not defended here. It is
# made unreachable: Tests/PfbSelectorPolicyCompleteness.Tests.ps1 reds the build when a guarded
# cmdlet writes a key that is neither on this list nor identity-shaped, so no release can contain
# an unclassified key.
#
# This is NOT a general-purpose selector classifier. tools/Build-PfbDeadKeyReport.ps1 has its own,
# Test-PfbDeadKeySelectorName, and the two deliberately differ -- see the comment at that site.
# A report that misclassifies produces a wrong row; this policy DISCARDS A REQUEST. The failure
# directions are opposite, so the divergence is intended rather than drift.
#
# Do NOT add context_names, continuation_token or allow_errors. None of the three is ever in the
# hashtable this policy inspects: context_names is injected into a CLONE inside
# Invoke-PfbApiRequest (Private/Invoke-PfbApiRequest.ps1) after the guard has already run,
# continuation_token is written inside the pagination loop, and allow_errors is never written into
# any query hashtable anywhere in the module.
$script:PfbNonSelectorQueryKeys = [System.Collections.Generic.HashSet[string]]::new(
    [string[]]@(
        # --- Written by Add-PfbCommonQueryParams -------------------------------------------
        # 'filter' is written by the same helper and is deliberately ABSENT: it is the module's
        # one caller-authored predicate, and therefore a selector.
        'limit',              # caps result-set size; does not choose which objects are in it
        'sort',               # orders a result set
        'total_only',         # response shape (a count), explicitly applied AFTER filtering

        # --- Written by individual guarded cmdlets -----------------------------------------
        'start_time',         # time-window bound over whichever objects are already in scope
        'end_time',           # ditto
        'resolution',         # sample granularity
        'destroyed',          # lifecycle partition. Published contract is "lists ONLY destroyed
                              # objects"; several cmdlet help strings say "Include destroyed",
                              # which contradicts it and is a separate fix
        'current_fleet_only', # scope flag. Already classified this way by hand in PR #125
        'type',               # metric-type partition -- decided by its SERVER-SIDE default: a key
                              # the server fills in when omitted cannot be what the caller addressed
        'protocols',          # protocol partition; the caller cannot enumerate the members. Our own
                              # -Protocol help reads as selection, but the PUBLISHED parameter
                              # description is a bare value list with no verb, and that governs
        'flagged',            # boolean partition. A dead key SERVER-SIDE (#142, undeclared in all
                              # 29 published versions) -- but classifying it changes behaviour
                              # TODAY, because this predicate decides on key PRESENCE and never
                              # reaches the server. Get-PfbAlert writes it under ContainsKey and
                              # nothing blocks the send, so `@() | Get-PfbAlert -Flagged $true`
                              # returns every alert on main and is suppressed here. Pinned by a
                              # behavioural test in Tests/Test-PfbEmptyPipelineRead.Tests.ps1
        'expose_api_token'    # response projection: changes whether a field is populated, not
                              # which objects return. The live example of why the unclassified
                              # default needed closing rather than defending
    ),
    [System.StringComparer]::Ordinal)
