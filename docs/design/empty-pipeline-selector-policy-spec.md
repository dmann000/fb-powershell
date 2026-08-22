# Empty-pipeline selector policy

Design spec for issue #126. Companion to #128, which lands with it.

## Status

Proposed. Supersedes nothing; this is the first written statement of a policy the module has been
approximating since PR #125.

## The problem

PR #125 (issue #121) added `Private/Test-PfbEmptyPipelineRead`, consulted by the 130 public cmdlets
that collect in `process` and issue their request from `end`. It is three lines:

```powershell
if (-not $Caller.MyInvocation.ExpectingInput) { return $false }
return ($null -eq $QueryParams -or $QueryParams.Count -eq 0)
```

The second line is an emptiness test standing in for a selector policy the module has never defined.
Any bound key at all leaves the hashtable non-empty and defeats the guard:

```powershell
@() | Get-PfbFileSystem            # suppressed, no request issued
@() | Get-PfbFileSystem -Limit 10  # NOT suppressed, issues an unfiltered read of 10 objects
```

The distinction the predicate is missing is not "bound versus unbound" — it is what the bound key
*means*. `-Filter` addresses objects the caller chose. `-Limit`, `-Sort`, `-Destroyed`,
`-StartTime` and `-ContextNames` do not; they shape or scope a result set the caller did not choose.
So the harm #121 was filed for — an empty search silently becoming an unfiltered read — survives on
every invocation that binds a non-selector.

## Why this is a safety rail, not a pipeline-semantics rule

This framing decides the whole design, so it is stated before the mechanism.

Issue #121's severity argument was about blast radius, not about pipeline etiquette: *"for a read
whose output feeds a `Remove-*`, it is the case that destroys something the caller never selected"*,
and *"silence is the dangerous direction — the caller has no signal that the filter did not apply."*
The measured finding was `$empty | Get-PfbFileSystemSnapshot` returning 28 objects, the same count as
an unfiltered read, because the endpoint ignored a malformed `names` key.

PR #125 restated the goal in the same terms — "an empty pipeline no longer becomes an unfiltered read
or write" — and it already made one classification of exactly this kind by hand, for
`Get-PfbRemoteArray`, on the grounds that "`current_fleet_only` is a scope flag, not a selector."

So the rule this spec defines is:

> **An empty pipeline must never become a request that returns or mutates objects the caller did not
> address.**

The rejected alternative is worth recording because it is the more elegant rule and it is wrong for
this issue. A pure pipeline-source reading — *"if the pipeline was the selector source and it
produced nothing, issue nothing"* — needs no vocabulary at all: the guard can read
`$Caller.MyInvocation.MyCommand.Parameters` for the `ValueFromPipeline` parameters and ask whether
any appears in `$Caller.MyInvocation.BoundParameters`, which is about ten lines and no list to
maintain. It is rejected because it also suppresses `@() | Get-PfbFileSystem -Filter "name='x'"`,
where the caller *did* constrain scope and the array would have evaluated the constraint. That is a
regression against today's behaviour in the one case #126's own table calls correct.

## Decision: classify the non-selectors, not the selectors

Issue #126 offers a module-wide convention keyed on `names`/`ids` and their non-generic equivalents.
This spec inverts it: **enumerate the query keys that do *not* address objects, and treat everything
else as a selector.**

### Why the inversion, and not the allowlist

The failure directions are asymmetric, and only one of them is acceptable under a safety rail:

| Policy shape | A key nobody classified | Consequence |
|---|---|---|
| Allowlist of selector keys | reads as *not a selector* → **suppress** | Silently breaks a working call. New harm, in the same silent direction #121 was filed for, just pointed the other way |
| Denylist of shaping keys | reads as *selector* → **issue** | Exactly today's behaviour. The guard simply has not been extended to that case yet |

A forgotten key must degrade to a missed guard, never to an eaten request.

The allowlist's failure mode is not hypothetical. `Private/Add-PfbCommonQueryParams.ps1` hardcodes
the generic `names` and `ids` keys, so a convention derived from that helper does not see
`policy_names`, `remote_names`, `member_names` or `bucket_names` at all — it would classify the
module's most common selectors as non-selectors, which is precisely the direction that issues the
unfiltered read. Under the inversion those keys need no entry and cannot be got wrong.

The inversion is also self-limiting. Shaping, paging and scoping vocabulary is REST-wide and changes
rarely; selector vocabulary is per-resource and grows with every endpoint added. Measured over the
130 guarded cmdlets, their own bodies write **32 distinct query keys** — this count excludes the keys
written centrally, which are enumerated in full below — and **23 of the 32** are `*_names` / `*_ids`
selectors:

```
policy_names 13   policy_ids 10   bucket_names 6    member_names 5   remote_names 4
remote_ids 4      names 4         member_ids 4      ids 3            bucket_ids 3
role_names 2      role_ids 2      file_system_names 2   file_system_ids 2
admin_names 1     admin_ids 1     certificate_names 1   certificate_group_ids 1
group_names 1     realm_names 1   source_names 1    local_port_names 1
names_or_owner_names 1
```

Every one of the 23 matches `names`, `ids`, or a `_names` / `_ids` suffix, which is what makes the
shape test in the completeness rail below viable. The remaining **nine**, plus the three common and
three centrally-injected keys, are the entire list to maintain — fifteen entries.

## The non-selector list

Fifteen entries, grouped by where the key is written. Each carries the reason it does not address
objects, because that reason is the only thing that makes the entry reviewable.

### Written by `Add-PfbCommonQueryParams`

| Key | Why it is not a selector |
|---|---|
| `limit` | Caps the size of a result set. Does not choose which objects are in it |
| `sort` | Orders a result set |
| `total_only` | Changes the response shape to a count. Harmless in effect, but it does not address objects |

`filter` is written by the same helper and is **a selector**: the array evaluates it server-side to
choose objects. This is the case that separates this spec from the pipeline-semantics alternative.

### Injected centrally by `Invoke-PfbApiRequest`

| Key | Why it is not a selector |
|---|---|
| `continuation_token` | Pagination cursor |
| `context_names` | Scopes to arrays in a fleet — it *widens* the object set rather than narrowing it |
| `allow_errors` | Error-handling behaviour, not object selection |

### Written by individual guarded cmdlets

| Key | Cmdlets | Why it is not a selector |
|---|---|---|
| `start_time`, `end_time` | 16 performance/log cmdlets | Bounds a time window over whichever objects are in scope |
| `resolution` | 15 performance cmdlets | Sample granularity |
| `destroyed` | `Get-PfbBucket`, `Get-PfbFileSystem`, `Get-PfbFileSystemSnapshot`, `Get-PfbRealm`, `Get-PfbWorkload` | Scopes to a lifecycle subset. Every destroyed object, not chosen ones |
| `current_fleet_only` | `Get-PfbRemoteArray` | Scope flag. Already classified this way by hand in PR #125 |
| `type` | `Get-PfbArraySpace`, `Get-PfbArrayPerformanceReplication`, `Get-PfbArrayConnectionPerformanceReplication` | Narrows to a category of measurement, not to named objects |
| `protocols` | `Get-PfbFileSystemSession` | Narrows to a protocol category |
| `flagged` | `Get-PfbAlert` | Boolean subset scope. See the note below |
| `expose_api_token` | `Get-PfbApiToken` | Response projection — decides whether a field is populated |

Three of the per-cmdlet keys deserve a note so that a future reader does not read them as mistakes:

- **`flagged` is a dead key today** (issue #142 — the endpoint declares no such parameter in any of
  the 29 spec versions), so classifying it changes no behaviour until #142 lands. It is listed now
  because the list should describe intent, not the current wire.
- **`source_names` is classified as a selector and is also a dead key.** PR #125's live run found
  `Get-PfbFileSystemSnapshot -SourceName` does not filter; the endpoint declares
  `names_or_owner_names`. Its classification is still *selector*, because the classification is about
  what the parameter means, not whether it currently works.
- **`expose_api_token` is security-relevant but is not a selector.** Suppressing on it alone would be
  correct under this policy; nothing about the token surface changes.

## Behaviour

`Get-PfbFileSystem` as the worked example. Only the third row changes.

| Invocation | Today | Under this spec |
|---|---|---|
| `Get-PfbFileSystem` (direct, no args) | unfiltered read | unfiltered read — **unchanged**, direct calls are never suppressed |
| `@() \| Get-PfbFileSystem` | suppressed, silent | suppressed, silent — unchanged |
| `@() \| Get-PfbFileSystem -Limit 10` | **unfiltered read of 10** | **suppressed, with a warning** |
| `@() \| Get-PfbFileSystem -Filter "name='x'"` | issued | issued — unchanged |
| `'fs1' \| Get-PfbFileSystem -Limit 10` | issued | issued — unchanged |
| `@() \| Get-PfbFileSystem -Name 'only-this'` | suppressed | suppressed — unchanged, and still the sharp edge PR #125 documented |

The last row is unchanged but remains counter-intuitive: `-Name` is the pipeline-bound parameter, so
an empty pipeline means `process` never ran and the accumulator the query is built from stays empty.
That is orthogonal to this spec and is not fixed by it.

## Diagnostics: warn where we discard something the caller typed

Suppression is silent today. Broadening it broadens silence, which is in tension with #121's own
reasoning that silence is the dangerous direction — and PR #125 already paid that cost once, when
eleven cmdlets lost an actionable `catch`-block warning on the empty-pipeline path because the guard
now returns before the request that produced it.

So the rule is drawn on whether anything was discarded, not on severity:

- **No query keys at all → silent.** Already shipped across 130 cmdlets, and the caller passed
  nothing to explain.
- **Non-selector keys only → `Write-Warning`.** The caller typed `-Limit 10` and got nothing back;
  they are owed the reason.

The warning names the key that was insufficient, so the message is diagnostic rather than a
restatement:

```
WARNING: Get-PfbFileSystem received no pipeline input, so no object was selected. -Limit
shapes a result set but does not select objects, so no request was issued. Pass -Name, -Id
or -Filter to read explicitly.
```

This is what makes a hand-maintained list safe to ship: a misclassification surfaces as a complaint
naming the key, instead of a request vanishing.

## Completeness rail

The list's risk is not being wrong, it is going stale. A new cmdlet writing a new shaping key
inherits *selector* treatment, which is the safe direction but is still a silently missed guard.

Close it in CI rather than by review: assert that every query key written anywhere under `Public/` is
either on the non-selector list or matches the selector shape (`names`, `ids`, or a `_names` / `_ids`
suffix). An unclassified key that matches neither reds the build and names the file. The AST
inventory this needs already exists — it is what produces `Reports/PfbFieldCmdletMap.json`.

Note the rail's boundary, which is deliberate and worth stating so nobody reads it as full coverage:
scanning `Public/` does not see the seven keys written in `Private/` — `filter`, `sort`, `limit` and
`total_only` from `Add-PfbCommonQueryParams`, and `continuation_token`, `context_names` and
`allow_errors` from `Invoke-PfbApiRequest`. Six of those seven are on the non-selector list; `filter`
is the selector among them. Those are a fixed, small set that changes only when the
request layer changes, so they are pinned by name in the predicate's own tests rather than
discovered. A key added to either helper without a matching test entry is the one gap this rail
cannot close.

Two non-vacuity requirements, since a rail that cannot fail is worse than none:

- Prove the assertion discriminates by adding a fabricated key to a fixture and confirming the test
  reds and names the offending file.
- Assert the non-selector list is non-empty and that every entry is reachable from some cmdlet, so a
  key deleted from `Public/` does not leave a permanent stale entry.

## Implementation notes

- **The policy changes one file.** `Test-PfbEmptyPipelineRead` tests the *built* `$QueryParams`, not
  the bound parameters, so none of the 130 call sites move. This is the property that makes the
  decision cheap to adopt and cheap to revise.
- The predicate's first line is unchanged: `ExpectingInput` still gates everything, so a direct call
  is never suppressed regardless of what it binds.
- The non-selector list is module-internal data, not user-facing configuration. It should live where
  the predicate can read it without a file load on every call.
- **#128 lands with this.** The guard's body changes and its rails assert placement, so the two
  should be reviewed together rather than leaving a window where the rails describe the old shape.
  #128's own scope — asserting the guard *executes on every path* rather than merely precedes the
  request — is unchanged by this spec.

## Testing

- Per-key table-driven tests over the non-selector list: for each entry, an empty pipeline binding
  only that key suppresses; an empty pipeline binding that key plus a selector issues.
- The `filter`-is-a-selector case gets its own test, since it is the deliberate divergence from the
  rejected alternative.
- A direct-call control for at least one cmdlet, because a suppression assertion with no control
  proves nothing about whether the request path still works.
- Warning-emission assertions on the scope-only path and warning *absence* on the no-keys path.
- Both PowerShell editions. The predicate and its data must stay inside the 5.1-compatible subset,
  as the existing predicate and guard line already do.

## Non-goals

- **Not a change to direct-call behaviour.** `Get-PfbX` with no arguments performs its unfiltered
  read, as it always has. Nothing here makes an unfiltered read harder to ask for deliberately.
- **Not a fix for dead keys.** #142 and the `source_names` case are classified here but repaired
  elsewhere.
- **Not a general selector vocabulary for the drift or dead-key tooling.** This list exists to decide
  suppression at runtime. Tooling that wants a selector classification for reporting should not reuse
  it without deciding its own failure direction, which is the opposite of this one: a report that
  guesses wrong is a wrong row, not a discarded request.
- **Not the `-Name`-with-empty-pipeline sharp edge**, which is a parameter-binding consequence rather
  than a policy choice.

## Prior art

The other Everpure PowerShell toolkit was checked before this policy was invented, on the theory
that a solved problem should be copied rather than redesigned.

`PureStoragePowerShellSDK2` (2.47.190, PowerShell Gallery) has the same architecture — a binary
module whose generated cmdlets accumulate a pipeline-bound `-Name` in `ProcessRecord` and dispatch
from `EndProcessing` — and **no equivalent guard**. Verified by reflection over the shipped assembly:
`GetVolumeCmdlet::EndProcessing` normalizes an empty accumulator to `null`, which omits the `names`
query key, and then dispatches unconditionally with no count test. `MyInvocation.ExpectingInput` is
not consulted anywhere in the class, so that module cannot distinguish a deliberate unfiltered read
from an accidental one. The same shape holds for its `Remove-*` cmdlets, where the only gate is
`ShouldProcess` and its target string is empty when the accumulator is.

Two conclusions were drawn, and a third was explicitly not:

- There is no precedent to copy, so the policy has to be decided here.
- There is no compatibility argument in either direction, since no existing caller of that module
  depends on behaviour it does not have.
- Its absence is **not** evidence the design was considered and rejected. It should not be cited as
  support for leaving #126 unfixed.

## Open points for review

1. **`type` and `protocols`** are the two entries where "category" versus "selector" is a judgment
   rather than a reading. Both narrow to a class of thing rather than to named objects, which is why
   they are listed — but a reviewer who disagrees should say so now, because moving them later
   changes behaviour rather than a comment.
2. **Whether to propose the guard upstream** to the FlashArray toolkit, given the direction toward a
   unified cmdlet surface. Out of scope for this issue; worth deciding once the policy has shipped
   and held.
