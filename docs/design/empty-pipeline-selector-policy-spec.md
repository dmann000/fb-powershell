# Empty-pipeline selector policy

Design spec for issue #126. Companion to #128, which lands with it.

## Status

**Proposed, with three questions still open** — see *Open questions* at the end. Those are marked
inline as **OPEN** where they bear on a section; everything else is settled.

This is not the module's first selector classifier. `tools/Build-PfbDeadKeyReport.ps1` already has
`Test-PfbDeadKeySelectorName`, used by the dead-key report. The two must be reconciled — see
*Relationship to the existing classifier*.

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
*means*. `-Filter` addresses objects the caller chose. `-Limit`, `-Sort`, `-Destroyed`, `-StartTime`
and `-Resolution` do not; they shape or scope a result set the caller did not choose. So the harm
#121 was filed for — an empty search silently becoming an unfiltered read — survives on every
invocation that binds a non-selector.

Issue #126's own table lists `-ContextNames` among the offending parameters. That is incorrect and is
not carried forward here: no guarded cmdlet has such a parameter. Fleet context arrives as session
state and is injected inside `Invoke-PfbApiRequest`, after the guard has already run, so
`@() | Get-PfbFileSystem` under a session context is **already suppressed today**.

## The goal, and the gap this proposal leaves

The rule this spec works toward:

> An empty pipeline should not become a request that returns or mutates objects the caller did not
> address.

Stated as a goal rather than an invariant, deliberately. **The policy below does not fully achieve
it**, and saying otherwise would be false. Two residual gaps are known and named in this document —
the unclassified-key default (*The decision*) and the container-scope case (*What a per-key list
cannot express*). Whether to close the first is the main open question.

### Why this is a safety concern and not a pipeline-semantics question

Issue #121's severity argument was about blast radius: *"for a read whose output feeds a `Remove-*`,
it is the case that destroys something the caller never selected"*, and *"silence is the dangerous
direction — the caller has no signal that the filter did not apply."* The measured finding was
`$empty | Get-PfbFileSystemSnapshot` returning 28 objects, the same count as an unfiltered read,
because the endpoint ignored a malformed `names` key.

PR #125 restated the goal the same way — "an empty pipeline no longer becomes an unfiltered read or
write" — and already made one classification of this kind by hand, for `Get-PfbRemoteArray`, on the
grounds that "`current_fleet_only` is a scope flag, not a selector."

## The decision

**OPEN — see question 1.** The proposal below is a global non-selector list. A reviewer has argued
for replacing it with a generated per-(cmdlet, endpoint, key) classification carrying an explicit
`unresolved` state that fails CI. The list below survives either way as the runtime data; what is
open is whether an *unclassified* key may default to "selector" at all.

Issue #126 offers a module-wide convention keyed on `names`/`ids` and their non-generic equivalents.
This spec inverts it: **enumerate the query keys that do not address objects, and treat everything
else as a selector.**

### Why the inversion, and not the allowlist

The two shapes fail differently:

| Policy shape | A key nobody classified | Consequence |
|---|---|---|
| Allowlist of selector keys | reads as *not a selector* → **suppress** | Silently breaks a working call — a new failure that did not exist before |
| Denylist of shaping keys | reads as *selector* → **issue** | The guard does not fire. Matches the pre-#126 behaviour of that call |

The allowlist's failure mode is concrete, not hypothetical. `Private/Add-PfbCommonQueryParams.ps1`
hardcodes the generic `names` and `ids` keys, so a convention derived from that helper does not see
`policy_names`, `remote_names`, `member_names` or `bucket_names` at all — it would classify the
module's most common selectors as non-selectors, which is the direction that issues the unfiltered
read. Under the inversion those keys need no entry and cannot be got wrong.

**State the limit of this argument plainly, because an earlier draft overstated it.** "Matches the
pre-#126 behaviour" is a compatibility property, not a safety property. A future key that broadens a
result set — a projection switch, an all-contexts flag, a recursive option — would default to
"selector", issue the request, and return a broader result than the caller addressed, with no
warning, because the warning below fires only on *known* non-selectors. `expose_api_token` is a live
example of the class and is caught only because it was hand-listed. The denylist's default is
therefore *better* than the allowlist's, not *safe*. Question 1 asks whether to remove the default
from the picture entirely by making the unclassified set provably empty.

The inversion is also self-limiting. Shaping, paging and scoping vocabulary is REST-wide and changes
rarely; selector vocabulary is per-resource and grows with every endpoint. Measured over the 130
guarded cmdlets, their own bodies write **32 distinct query keys** — and only **46 of the 130** write
any key at all; the other 84 see nothing but `Add-PfbCommonQueryParams`'s output. **23 of the 32** are
`*_names` / `*_ids` selectors:

```
policy_names 13   policy_ids 10   bucket_names 6    member_names 5   remote_names 4
remote_ids 4      names 4         member_ids 4      ids 3            bucket_ids 3
role_names 2      role_ids 2      file_system_names 2   file_system_ids 2
admin_names 1     admin_ids 1     certificate_names 1   certificate_group_ids 1
group_names 1     realm_names 1   source_names 1    local_port_names 1
names_or_owner_names 1
```

Every one of the 23 matches `names`, `ids`, or a `_names` / `_ids` suffix. The remaining **nine** are
the per-cmdlet non-selectors listed below.

## The non-selector list

Twelve entries the predicate can actually see.

### Written by `Add-PfbCommonQueryParams`

| Key | Why it is not a selector |
|---|---|
| `limit` | Caps the size of a result set. Does not choose which objects are in it |
| `sort` | Orders a result set |
| `total_only` | Changes the response shape to a count |

`filter` is written by the same helper and is **a selector**: `components.parameters.Filter` in the
published spec reads *"Narrows down the results to only the response objects that satisfy the filter
criteria"* — server-side evaluated and object-narrowing.

### Written by individual guarded cmdlets

Counts and cmdlet lists below are **the guarded population only**. Several of these keys are also
written by non-guarded cmdlets, where this policy has no effect; those occurrences are excluded.

| Key | Guarded cmdlets | Why it is not a selector |
|---|---|---|
| `start_time`, `end_time` | 8 each | Bounds a time window over whichever objects are in scope |
| `resolution` | 8 | Sample granularity |
| `destroyed` | 4 — `Get-PfbBucket`, `Get-PfbFileSystem`, `Get-PfbFileSystemSnapshot`, `Get-PfbRealm` | Lifecycle-state predicate. See the precision note below |
| `current_fleet_only` | 1 — `Get-PfbRemoteArray` | Scope flag. Already classified this way by hand in PR #125 |
| `type` | 1 — `Get-PfbArrayConnectionPerformanceReplication` | **OPEN, question 2** |
| `protocols` | 1 — `Get-PfbFileSystemSession` | **OPEN, question 2** |
| `flagged` | 1 — `Get-PfbAlert` | Boolean subset scope. Dead key today (#142) |
| `expose_api_token` | 1 — `Get-PfbApiToken` | Response projection |

Notes that make individual entries reviewable:

- **`destroyed` narrows; it does not "include".** The published parameter reads: `true` lists *only*
  destroyed objects pending eradication, `false` lists *only* non-destroyed, omitted lists both.
  Several cmdlet help strings say "Include destroyed…", which contradicts the published contract and
  should be corrected separately. The module only ever writes `'true'`, from a switch.
- **`expose_api_token`** changes whether a field is populated, not which objects are returned, so
  suppressing on it alone can only suppress a call that returns objects the caller did not address.
  Note it exposes a real credential, which is why it is a live example of the unclassified-key risk
  described above rather than a reassurance.
- **`flagged` is a dead key today** (#142 — undeclared in all 29 published versions), so classifying
  it changes no behaviour until #142 lands. `Get-PfbAlert` writes it via `ContainsKey`, so
  `-Flagged:$false` also writes the key.
- **`source_names` is classified a selector and is also a dead key.** PR #125's live run found
  `Get-PfbFileSystemSnapshot -SourceName` does not filter; the endpoint declares
  `names_or_owner_names`. Classification is about what the parameter means, not whether it works.
- **`protocols` has a `Protocols_required` variant** in the published spec, so on at least one
  endpoint it is required. A required non-selector can never satisfy the guard by itself, which is
  correct but surprising.

### Not visible to the predicate — do not add these to the list

An earlier draft listed `continuation_token`, `context_names` and `allow_errors` as centrally
injected non-selectors. All three are wrong, for different reasons, and each would break the
reachability rail below:

- **`context_names`** is injected at `Private/Invoke-PfbApiRequest.ps1:83`, into a **clone** made one
  line earlier specifically so the key cannot leak back to the caller. The guard runs in the caller's
  `end`, before `Invoke-PfbApiRequest` is entered.
- **`continuation_token`** is written inside the pagination loop, after a response.
- **`allow_errors`** is never written into any query hashtable anywhere in the module. It exists only
  as `$script:PfbAllowErrorsParameterName`, read as a capability-map discriminator.

The predicate's input is therefore the **pre-request query state**, not the fully built wire query.
The spec's wording should not imply otherwise, and central injection needs its own tests.

## What a per-key list cannot express

A key with selector spelling can sit on a parameter that addresses a *container* rather than the
returned objects. `Get-PfbBucketAccessPolicyRule` binds `BucketName` from the pipeline;
`-PolicyName` is `[Parameter()]` in every parameter set and writes `policy_names`:

```powershell
@() | Get-PfbBucketAccessPolicyRule -PolicyName 'read-only-policy'
  -> GET buckets/bucket-access-policies/rules?policy_names=read-only-policy
  -> every rule of that policy, across all buckets
```

That is #121's harm class, and this policy does **not** suppress it. `Get-PfbLocalGroupMember` has the
same shape (`$Group` piped → `group_names`; `-Member` → `member_names`).

No per-key list can express this, because the harm is per-(key, cmdlet, which-parameter-is-piped)
rather than per-key. It is a missed guard rather than new harm, so it does not sink the approach —
but "everything else is a selector" must not be read as coverage. Note that the rejected alternative
below handles this case correctly; that is a genuine advantage it has over this proposal.

## Behaviour

`Get-PfbFileSystem` as the worked example.

| Invocation | Today | Under this spec |
|---|---|---|
| `Get-PfbFileSystem` (direct, no args) | unfiltered read | unchanged — direct calls are never suppressed |
| `@() \| Get-PfbFileSystem` | suppressed, silent | unchanged |
| `@() \| Get-PfbFileSystem -Limit 10` | **unfiltered read of 10** | **suppressed** |
| `@() \| Get-PfbFileSystem -Filter "name='x'"` | issued | unchanged |
| `'fs1' \| Get-PfbFileSystem -Limit 10` | issued | unchanged |
| `@() \| Get-PfbFileSystem -Name 'only-this'` | suppressed | unchanged — the PR #125 sharp edge |
| `@() \| Get-PfbFileSystem -Name 'x' -Limit 10` | **unfiltered read of 10** | **suppressed** |

The last two rows together are a point in the proposal's favour: today the sharp edge is
*inconsistent* — adding `-Limit` to an already-suppressed call revives it as an unfiltered read.
Under this spec both suppress.

## Diagnostics

**OPEN — see question 3.** The rule below is proposed, not settled.

Suppression is silent today. Broadening it broadens silence, which is in tension with #121's
reasoning that silence is the dangerous direction.

Proposed: **no query keys at all → silent; non-selector keys only → `Write-Warning`.**

Two honest caveats about the motivation usually given for this:

- PR #125's "eleven cmdlets lost an actionable warning" is a correct count, but only **four** of the
  eleven catch a missing-selector error that would fire on a bare empty-pipeline call. The other
  seven catch model or version capability errors that fire on direct calls too, and `Get-PfbNode`
  lost a `/nodes` → `/blades` fallback rather than a warning.
- **This proposal restores none of the four**, because they sit on the no-keys path, which stays
  silent. The motivation and the rule do not meet, and the spec should not imply they do.

The message must be generated per cmdlet, not fixed text. A literal "Pass `-Name`, `-Id` or `-Filter`"
is wrong for the #90 specialized-selector cmdlets, which have no `-Name`/`-Id` and no alias for them —
`Get-PfbNetworkInterfaceNeighbor` has `-LocalPortName`, `Get-PfbRealmDefaults` has `-RealmName` — and
`Tests/PfbSpecializedSelectorKeys.Tests.ps1` actively asserts those parameters are absent.

## Completeness rail

**Scope it to the 130 guarded cmdlets, not all of `Public/`.** An earlier draft said `Public/`, which
was wrong twice over: it reds on the unmodified tree, and greening it would drag mutation controls
(`cascade_delete`, `disruptive`, `recursive`) into a policy that only governs reads. It would also
apply CI pressure in the unsafe direction — the natural way to green an unclassified-key failure is
to add the key to the *non-selector* list, and `gids`, `uids` and `user_sids` are genuine selectors
whose spelling the shape test cannot match. All three are written only by non-guarded cmdlets, so
correct scoping removes them from the picture.

Scoped to the guarded population the rail is **clean today: all 32 keys are either on the list or
match the shape, with zero unmatched.**

Assert that every query key written by a guarded cmdlet is either on the non-selector list or matches
`names` | `ids` | `*_names` | `*_ids`. An unclassified key reds the build and names the file.

Three constraints on building it, each of which would otherwise produce a rail that cannot fail:

- **It cannot be built on `Reports/PfbFieldCmdletMap.json`**, which an earlier draft claimed. That
  artifact has zero entries for `type`, `protocols` and `flagged` — three of the nine — and `flagged`
  is absent precisely because of the wire-name resolver gap in **#141**.
- **`tools/lib/PfbCmdletParamTools.ps1` restricts assignment targets to variables named `body` or
  `queryParams`.** In `Public/` many rows use `$q`, one uses `$destroyQuery`, and `Test-PfbConnection`
  passes an inline `-QueryParams @{ limit = 1 }`. A rail reusing that machinery misses all of them.
- **The non-vacuity test must therefore use `$q`-shaped and inline-literal fixtures**, not only a
  `$queryParams` one — otherwise it passes while the gap above persists. Prove the assertion reds and
  names the offending file.

Drop the "every entry reachable from some cmdlet" assertion in its earlier form, or scope it to the
nine per-cmdlet entries: the three `Add-PfbCommonQueryParams` keys are reachable from the helper
rather than from any cmdlet body.

## Relationship to the existing classifier

`tools/Build-PfbDeadKeyReport.ps1` already defines `Test-PfbDeadKeySelectorName`, with a comment that
warns against the exact formulation this spec adopts:

```powershell
# Exact anchors are intentional. In particular, do not use a suffix regex that would
# classify usernames, grids, ids_or_names, or context_names as selectors.
if ($WireName -in @('names', 'ids', 'name', 'id')) { return $true }
if ($WireName -in @('context_names', 'ids_or_names')) { return $false }
return $WireName.EndsWith('_names', ...) -or $WireName.EndsWith('_ids', ...)
```

It differs from this spec's shape in three ways: it excludes `context_names` and `ids_or_names`
explicitly, and it admits singular `name`/`id` (harmless today — neither is written as a query key
anywhere in `Public/`).

The two serve different purposes and may legitimately differ — a report that misclassifies produces a
wrong row, while this policy discards a request, so their failure directions are opposite. But the
divergence must be deliberate and commented at both sites, not discovered later.

## Implementation notes

- **The policy changes one file.** `Test-PfbEmptyPipelineRead` tests the built `$QueryParams`, not the
  bound parameters, so none of the 130 call sites move. Verified: the policy is computable from
  `$Caller.MyInvocation.ExpectingInput` plus the keys of `$QueryParams`, needing nothing else.
- The predicate's first line is unchanged: `ExpectingInput` still gates everything, so a direct call
  is never suppressed regardless of what it binds.
- **The list wins over the shape at runtime.** The shape test is a CI construct only and must never be
  consulted by the predicate — it classifies `context_names` as a selector, which the list does not.
- Store the list as a `$script:` constant in a `Private/Pfb*Constants.ps1`, following
  `Private/PfbContextConstants.ps1`. Not a `.psd1` — the predicate is on a hot path.
- **`Get-PfbRemoteArray`'s hand-placed guard becomes redundant.** PR #125 moved it above the
  `current_fleet_only` write; once that key is on the list, placement no longer matters. Behaviour is
  identical either way, but the comment there will read as stale. Leave the placement, update the
  comment — and note this is the one call site that is not literally untouched.
- **#128 lands with this**, since the guard's body changes and its rails assert placement.

## Testing

- Per-key table-driven tests over the list: for each entry, an empty pipeline binding only that key
  suppresses; that key plus a selector issues.
- `filter`-is-a-selector gets its own test — it is the deliberate divergence from the alternative.
- A direct-call control for at least one cmdlet. A suppression assertion with no control proves
  nothing about whether the request path still works.
- Central injection (`context_names`, `continuation_token`) tested separately from the predicate,
  since the predicate cannot see either.
- Warning emission on the scope-only path, and warning *absence* on the no-keys path.
- Both PowerShell editions; the predicate and its data stay in the 5.1-compatible subset.

## The rejected alternative

A pure pipeline-source rule: *if the pipeline was the selector source and it produced nothing, issue
nothing.* It needs no vocabulary at all.

**The mechanism, corrected.** An earlier draft described reading `ValueFromPipeline` parameters from
`$Caller.MyInvocation.MyCommand.Parameters` and checking `$Caller.MyInvocation.BoundParameters`. Three
corrections, all measured on both editions:

- The retention premise is **sound**: after a non-empty pipeline, the pipeline-bound parameter is
  present in `BoundParameters` in `end`; after `@()` it is absent.
- **It must read `ValueFromPipelineByPropertyName` too.** Eight of the 130 guarded cmdlets have no
  true `ValueFromPipeline` parameter — `Test-PfbSaml2Idp`, `Test-PfbActiveDirectory`,
  `Get-PfbOpenFile`, `Get-PfbResourceAccess` and four object-store role/user getters. For those the
  pipeline-parameter set is empty and the rule suppresses **every** piped invocation, including
  working ones.
- **`$null | cmd` binds the parameter** and runs `process` once. So the alternative fails to suppress
  a case today's guard catches. It is differently aggressive, not uniformly more aggressive.

**Why it is not adopted here — and why the earlier reasoning was too weak.** The draft rejected it
solely because it also suppresses `@() | Get-PfbFileSystem -Filter "name='x'"`. That is not
sufficient: whether an empty pipeline should veto an independent `-Filter` is a policy question, and
the intersection reading ("zero upstream objects means zero work") is defensible. It is also
repairable with a one-entry carve-out, which by this spec's own cost argument would favour it.

The honest comparison is:

- **For it:** one carve-out versus twelve list entries; and it handles the container-scope case above,
  which no per-key list can.
- **Against it:** the eight `ValueFromPipelineByPropertyName` cmdlets and the `$null` regression are
  real defects needing real handling; and it changes the meaning of an explicit `-Filter`, which is a
  user-visible contract change rather than a guard.

This remains a live alternative rather than a closed question, and question 1 may reopen it.

## Non-goals

- **Not a change to direct-call behaviour.** `Get-PfbX` with no arguments performs its unfiltered
  read, as always.
- **Not a fix for dead keys.** #142 and the `source_names` case are classified here, repaired
  elsewhere.
- **Not a replacement for `Test-PfbDeadKeySelectorName`.** See above.
- **Not the `-Name`-with-empty-pipeline sharp edge**, which is a parameter-binding consequence.

## Prior art

The other Everpure PowerShell toolkit was checked before this policy was invented, on the theory that
a solved problem should be copied rather than redesigned.

`PureStoragePowerShellSDK2` (2.47.190, PowerShell Gallery) has the same architecture — a binary module
whose generated cmdlets accumulate a pipeline-bound `-Name` in `ProcessRecord` and dispatch from
`EndProcessing` — and **no equivalent guard**. Verified by reflection over the shipped assembly:
`GetVolumeCmdlet::EndProcessing` normalizes an empty accumulator to `null`, which omits the `names`
query key, then dispatches unconditionally with no count test. `MyInvocation.ExpectingInput` is not
consulted anywhere in the class, so that module cannot distinguish a deliberate unfiltered read from
an accidental one.

Two conclusions were drawn, and a third was explicitly not:

- There is no precedent to copy, so the policy has to be decided here.
- There is no compatibility argument in either direction, since no existing caller of that module
  depends on behaviour it does not have.
- Its absence is **not** evidence the design was considered and rejected, and should not be cited as
  support for leaving #126 unfixed.

## Open questions

1. **Should an unclassified key be allowed to default to "selector" at all?** The alternative is a
   generated per-(cmdlet, endpoint, key) classification with an explicit `unresolved` state that fails
   CI, making the unclassified set provably empty. This decides whether the list above is the policy
   or merely its runtime data.
2. **Are `type` and `protocols` selectors?** Two reviewers disagreed. This turns on whether a
   *category* predicate addresses objects — and if it does not, why `filter` does, given a filter can
   express a category predicate.
3. **Is the warning line drawn correctly, and is `Write-Warning` the right stream?** A legitimate
   zero-result search that also passes `-Limit` would warn routinely, and warnings are
   preference-controlled and commonly suppressed.
