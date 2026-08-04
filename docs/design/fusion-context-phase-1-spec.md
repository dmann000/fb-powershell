# Spec: Fusion context support, Phase 1 (context injection)

Status: proposed
Design doc: `docs/design/fusion-context-injection.md` (rev 4)
Tracking: #25 (Fusion `context_names` injection)
Depends on: Phase 0 (`feat/fusion-context-phase-0`) — **must merge first**
Branch: `feat/fusion-context-phase-1`

---

## Purpose

Phase 1 makes `context_names` work: a caller can target another array, a fleet, or every array
in a fleet or topology group, and every one of the module's ~520 cmdlets inherits that without
a signature change.

It ships the whole user-facing control surface at once — the context object, connection state,
central injection, the three client-side gates, and the two cmdlets plus one helper that drive
them. It is kept whole deliberately: the gates and the escape hatches are the same feature.
Shipping the hard throw without `Invoke-PfbInContext` would ship a gate with no key.

### Dependency on Phase 0

Phase 1 cannot be built on `main` as it stands. Two Phase 0 items are load-bearing:

| Phase 0 item | What Phase 1 needs it for |
|---|---|
| `Private/Resolve-PfbParameterComponent` (#74) | Produces the `-ContextComponent` input to `Test-PfbContextMultiValueCapable`. Without it the cardinality rule gets silently reimplemented inside `Private/`, giving the codebase two copies of a rule whose entire premise is one declared home |
| `contextScope` in the capability map (`schemaVersion` 2) | Kind-vs-scope validation and every scope-aware error message are map lookups. Not implementable before the field exists |

**Rebase this branch onto `main` after Phase 0 merges.** Both branches currently sit on
`ad00aae`; without the rebase, Phase 1's PR diff would carry Phase 0's commits.

---

## Already closed prerequisites

The design's single-choke-point premise now holds. It did not when the doc was first drafted:
five public cmdlets called `Invoke-RestMethod` directly. Three are connection lifecycle
(`Connect-PfbArray`, `Disconnect-PfbArray`, `Get-PfbApiVersion`) and legitimately sit outside
the choke point — none takes a context. The other two were ordinary writes that bypassed it:

| Cmdlet | Status |
|---|---|
| `Set-PfbPresetWorkload` | Closed — folded onto the shared path (#76); `Invoke-PfbApiRequest` gained `PUT` |
| `Set-PfbWorkloadTag` | Closed — folded onto the shared path (#77 / PR #81, merged); `Invoke-PfbApiRequest` and `Assert-PfbApiCapability` gained array request bodies |

This mattered more than tidiness: a cmdlet bypassing the choke point gets no injection and does
so **silently**, since the injection path cannot warn about a caller it never sees. Verify both
closures are on `main` before starting — if either regresses, "every request funnels through
`Invoke-PfbApiRequest`" has a counterexample again.

---

## Scope

### 1. The `PfbContext` object

A context is not a bare `string[]`.

| Field | Meaning |
|---|---|
| `Entries` | one or more context entries |
| `AllowErrors` | tri-state; **reserved in Phase 1, surfaced in Phase 2** |

Each entry:

| Field | Meaning |
|---|---|
| `Name` | the context name |
| `Kind` | `Array` (default) \| `Fleet` \| `TopologyGroup` |
| `Form` | `Object` (default) \| `AllArrays` |

**`Kind` is per-entry, not one scalar for the whole context.** Mixed-kind lists are on the near
roadmap — with Fleet Users and Fleet Audits, `context_names` will accept `ArrayA,ArrayB,myFleet`
in a single `GET`, and the Fleet-audits design documents exactly that shape. A single `Kind`
cannot express it. The field costs nothing now and is a breaking change to add later, so Phase 1
reserves the shape while only ever populating entries of one kind.

**`Form` is an enum, not a boolean.** The suffix vocabulary is already known to be open;
`.arrays` is the only form the server accepts today, but an all-sub-groups equivalent and
realm-as-context would each need their own flag. Two booleans can also encode a meaningless
state (both set), which an enum makes unrepresentable. Retrofitting is a breaking change to a
published parameter, since a `-AllArrays` switch and a `-Form` parameter cannot coexist cleanly.

Wire composition — **note the two invalid combinations, both rejected client-side**:

| `Kind` | `Form` | Wire value |
|---|---|---|
| `Array` | `Object` | bare array name |
| `Fleet` | `Object` | bare fleet name — addresses the fleet-level object |
| `Fleet` / `TopologyGroup` | `AllArrays` | `<name>.arrays` |
| `Array` | `AllArrays` | **invalid** — an array has no members |
| `TopologyGroup` | `Object` | **invalid** — no endpoint accepts a bare group name |

The second invalid row is measured, not inferred: a bare topology-group name is rejected on
every endpoint probed, including the topology-group endpoints themselves (`code 13` there,
`code 42` on array-scoped resources). A group is reachable as a context **only** through
`<group>.arrays`, and that suffix is case-sensitive. Fleet and group are asymmetric — a fleet is
addressable as an object *and* as a membership, a group only as a membership.

### 2. Context state on the connection object

Two properties, two mutation policies:

- **`.DefaultContext`** — the durable session default. Set at connect or via
  `Set-PfbContext` / `Clear-PfbContext`, which are **copy-on-write**: they return a *new*
  connection object and never mutate the caller's.
- **`.ContextOverride`** — the ambient, block-scoped value `Invoke-PfbInContext` sets. Mutable,
  but scoped by construction and restored in `finally`.

State on the object rather than `$script:` module scope fixes three failure modes structurally:
cross-connection leakage disappears; `$using:`-passed parallel work sees the right context
(`ForEach-Object -Parallel` / `Start-ThreadJob` share the live instance, `Start-Job` CliXml-clones
at fork time, which is what a fan-out wants); and nesting works without an explicit stack.

Copy-on-write for `.DefaultContext` is not inconsistent with the module writing `AuthToken` /
`TokenExpiresAt` back onto `$Array` during auto-reconnect: token refresh is a *transparent*
mutation, context is a *targeting* mutation that changes which array a write hits. Different
risk classes, so a different policy.

**Residual caveat to document:** concurrent workers mutating `.ContextOverride` on the same
shared object still race. Guidance — set context before forking parallel work; do not push
ambient overrides from inside concurrent workers on a shared connection.

### 3. Resolution and injection in `Invoke-PfbApiRequest`

Resolve once at the top of the choke point:

```
explicit -QueryParams['context_names']  >  $Array.ContextOverride  >  $Array.DefaultContext  >  (none)
```

**Tri-state "none" is required.** Distinguish *unset* (`$null`) from *explicit no-context*
(`[string[]]@()`). Both inject nothing, but the empty-array form is a deliberate "run this one
call locally" — so `[AllowEmptyCollection()]` and a `-ne $null` check, never a truthiness check.
Only a **non-empty** resolved context is subject to the hard-throw gate, which is what makes
`Invoke-PfbInContext -Context @()` the escape hatch for an endpoint that does not support
`context_names`.

Injection / gating decision table:

| Condition | Action |
|---|---|
| No context (`$null` or explicit `@()`) | No injection, no check. Unchanged behaviour |
| Context set **and** the map entry lists `context_names` | Inject; let `Assert-PfbApiCapability` catch "recorded but array too old" |
| Context set, no map entry for `Method Endpoint` **or** entry lacks `context_names`, **and** the array's version is *within* the map's scanned range | **Throw.** Name the endpoint; do not send |
| Same, but the array's version *exceeds* the scanned range | Do **not** throw. Proceed permissively |
| Context is multi-value **and** the endpoint is not multi-context-capable | **Throw**, tell the caller to narrow to one |
| Context kind incompatible with the endpoint's `contextScope` | **Throw**, one uniform message |

The third and fourth rows **must mirror each other exactly**. The likeliest real staleness case
is an endpoint that exists today and *gains* `context_names` later — entry present, parameter
absent — not an endpoint missing from the map.

**Apply the throw uniformly across all verbs, including `GET`.** Softening reads to
`Write-Warning` does not hold up: `-WarningAction SilentlyContinue` is routine in exactly the
automation most likely to set a read-scoped context; a wrong-scoped read inside a loop over
fleet members corrupts a result set invisibly; and a `GET`'s output routinely feeds a subsequent
mutating call.

**Local context is still a context.** A context naming the local array, on an endpoint that does
not support `context_names`, **still throws**. This deliberately diverges from the server, which
short-circuits a local context before validating anything. A cmdlet that works only *some* of
the time, depending on which array the context happens to name, is a worse contract than one
that fails consistently. A caller wanting the local system should `Clear-PfbContext` or
`Invoke-PfbInContext -Context @()` and say so.

#### Why the gate is client-side and not "send it and let the array error"

Because in the case that matters there is no error to surface. An endpoint that never supported
`context_names` (`/alert-watchers`) **silently accepts** it — HTTP 200, real mutations applied,
zero mention of the parameter. That is the majority behaviour across GET endpoints that never
recorded it, and it includes the fleet-management surface itself (`/fleets`, `/fleets/members`).

More broadly the array performs **no query-parameter validation at all** on reads: an entirely
invented parameter returns 200, and `allow_errors=not_a_boolean` returns 200 even on an endpoint
that genuinely declares `allow_errors`. **Accepting a parameter is not evidence an endpoint
supports it** — which is why every capability decision here is made client-side from the map
rather than by probing.

The converse also holds: an endpoint can process `context_names` with no scanned spec version
recording it. `GET /snmp-managers/test` does exactly that.

### 4. Three implementation-ordering requirements

These are the non-obvious ones. Each has a silent failure mode.

1. **Inject before the existing `Assert-PfbApiCapability` call.** In the current file that call
   is at `Private/Invoke-PfbApiRequest.ps1:46` — **not** line 41 as the design doc states; the
   doc's line numbers are stale and should not be trusted for placement. Do **not** inject
   "immediately before the request is built," which is near query-string construction at `:84`,
   after Assert has already run. If `context_names` lands in `$QueryParams` after Assert
   executes, Assert never sees it and the version check this design leans on never fires.
2. **Mutate `$QueryParams`, never the built query string.** The `-AutoPaginate` loop rebuilds
   the query from `$QueryParams` on every page (`:240`). Appending to the first page's URI drops
   the context from page 2 onward. Not hypothetical — `Get-PfbArraySpace` already paginates.
3. **Consume Phase 0's `Resolve-PfbParameterComponent`** rather than resolving components
   locally. The three-step contract (override key-present-but-`null`, override key-absent, then
   the default) has one declared home. Note that key-present-`null` and key-absent both return
   `$null`; the distinction is only whether the defaults table is consulted, which is exactly why
   a local reimplementation goes subtly wrong.

### 5. Three client-side gates

All three exist to convert an obscure server code into an actionable message. None is a security
boundary — see "Authorization" below.

**(a) Capability gate.** Rows 3-4 of the decision table. Keyed on the map's `generatedFrom`, so
absence within the scanned range is *confirmed* absence and absence beyond it is *no evidence*.

**(b) Cardinality gate.** The rule, already shipped as
`Private/Test-PfbContextMultiValueCapable.ps1` (PR #73) and currently inert with zero runtime
callers:

> An endpoint is multi-context-capable **iff** its `context_names` parameter resolves to
> component `Context_names_get` **AND** the endpoint also declares `allow_errors`.

Phase 1's job is to *call* it, with `-ContextComponent` from Phase 0's resolver. Against the
committed map (`generatedFrom` 2.0-2.28) it yields 135 capable endpoints of the 139 referencing
the multi-value component.

**The HTTP-verb rule is falsified — do not reintroduce it.** Rev 2 proposed GET multi-value /
mutations size-1. Four fleet-scoped GETs reject any two-name context with
`400 code 15 "Multiple location contexts are not allowed."`: `GET /presets/workload`,
`GET /topology-groups`, `GET /topology-groups/arrays`, `GET /topology-groups/members`. `code 15`
fires *before* the cross-array authorization gate, so it is structural to the endpoint, not a
permission artifact. A fleet-scoped endpoint has exactly one meaningful context, so multi-value
there is not merely restricted, it is meaningless. The verb survives **only** as a fallback for
an endpoint with no component signal at all, and that fallback throws on a method it has no
verdict for rather than assuming `$false`.

**(c) Kind-vs-scope gate.** Reject a bare fleet or group name on an array-scoped endpoint and
vice versa, with one uniform message, reading `contextScope` from the map. Entries marked
`unknown` (19 operations) **suppress this check** and leave today's behaviour — the gate must
degrade, not throw, on absent metadata.

### 6. Authorization-model precondition

**Every `context_names` call targeting anything other than the connected array's own local
context** — a single-value switch, a multi-array list, or an `.arrays` context — fails with
`code 20 "Operation not permitted."` as a static-model admin, and succeeds for an
LDAP-authenticated one. There is no single-vs-multi distinction.

This is **not** "`pureuser` vs everyone": since 4.5.0 admins can create additional named local
users with the same privileges, and the 4.8.1 service-account admin type is also local. All
three — `pureuser`, custom local users, service accounts — are `authorization_model: static`.
Only LDAP/SAML remote admins are `dynamic`. `GET /admins` reports the model per admin, which is
what makes the check implementable.

Check client-side at `Connect-PfbArray` / `Set-PfbContext` and throw when a static-model admin
sets or uses any cross-array context:

> targeting a context other than the local array requires a dynamic-authorization-model
> (LDAP/SAML) admin; static-model admins, including `pureuser` and other local accounts, are
> not permitted.

**This earns its keep for diagnosis as much as ergonomics.** As a static-model admin, *every*
call to a fleet-scoped endpoint returns `code 20`, read and write alike, whatever the context
value — indistinguishable from the endpoint being unsupported on the platform. That exact
confusion produced a wrong conclusion twice during design testing ("presets are unsupported on
FB-A"). Converting it into a statement about the admin's authorization model, before the call,
is the difference between a diagnosable failure and a dead end.

### 7. `Set-PfbContext` / `Clear-PfbContext`

```powershell
Set-PfbContext
    [-Array] <PSCustomObject>   # ordinary param; defaults to the current default connection
    [-Context] <string[]>       # binds by property name
    [-Kind <ContextKind>]       # Array (default) | Fleet | TopologyGroup
    [-AllArrays]                # switch -> Form = AllArrays (.arrays suffix)
    [-AllowErrors]              # tri-state; reserved, Phase 2
    -> always returns the new connection object

Clear-PfbContext
    [-Array] <PSCustomObject>
    -> always returns the new connection object
```

- **Copy, not mutate.** A helper frame, an outer scope, or a loop iteration holding the old
  `$fb` keeps its original scope; only the caller capturing the return value sees the change.
- **Always return the new object; no `-PassThru`.** The output *is* the effect.
- **Must swap the cache pointers.** The module tracks connections in `$script:PfbArrays` and
  `$script:PfbDefaultArray`. Both cmdlets must repoint these at the new copy, or callers using
  the implicit default connection keep hitting the old object after the cmdlet "succeeded."
- **`Clear-PfbContext` is its own cmdlet**, matching the `Set-`/`Clear-PfbCredential` precedent,
  and because `@()` must keep its distinct meaning at the `Invoke-PfbInContext` layer.
- **Neither cmdlet makes a network call.** See "`-AllArrays`" below.

#### Pipeline binding

```powershell
$fb = Get-PfbFleetMember -FleetName 'fleet-prod' | Set-PfbContext
$fb = Get-PfbFleet         | Set-PfbContext -AllArrays   # -> cc-test-fleet.arrays
$fb = Get-PfbTopologyGroup | Set-PfbContext -AllArrays   # -> region-1.arrays
```

```powershell
[Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
[Alias('MemberName','Name')]
[string[]]$Context
```

- `-Array` becomes an ordinary parameter defaulting to the current default connection, giving
  the pipeline slot to the context.
- Because `Set-PfbContext` is copy-on-write it **must accumulate in `process{}` and emit exactly
  one connection in `end{}`**, scoped to the union — otherwise N piped members yield N
  connection objects.
- **`$fb | Set-PfbContext` is dropped as redundant.** `Set-PfbContext -Array $fb -Context 'b'`
  and the implicit-default form already cover it, and it is the only thing standing between us
  and the far more valuable `Get-PfbFleetMember | Set-PfbContext`.
- Phase 0 supplies `MemberName` on `Get-PfbFleetMember`. **`Get-PfbTopologyGroup` does not exist
  yet** — it is #38's, under a binding contract to emit a top-level `Name`. Until it lands, the
  `-AllArrays` group form is exercised against a fleet and against hand-constructed input.
- **Piping many members yields a multi-value context**, valid for fan-out-capable GETs and
  rejected elsewhere. Document "pipe all members into a durable context" as a *read-scoping*
  ergonomic.

### 8. `Invoke-PfbInContext`

```powershell
function Invoke-PfbInContext {
    param(
        [Parameter(Mandatory)][PSCustomObject]$Array,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Context,
        [Parameter(Mandatory, Position=0)][scriptblock]$ScriptBlock
    )
    $previous = $Array.ContextOverride
    $Array.ContextOverride = $Context
    try     { & $ScriptBlock }
    finally { $Array.ContextOverride = $previous }
}
```

- **Nesting works with no explicit stack** — each invocation captures its own `$previous`, so
  the call stack provides push/pop discipline and the inner block restores the *outer* value
  rather than clearing it.
- **Exception-safe via `finally`**, at every nesting level.
- **Non-pipeable by design** — its pipeline payload would have to be the scriptblock, which no
  cmdlet emits. The blessed form for it is
  `-Context (Get-PfbFleetMember -FleetName 'x').member.name`.

### 9. `-AllArrays`

`-AllArrays` emits the single `.arrays` context and lets the server resolve membership, rather
than enumerating names client-side.

**This is not sugar for piping members.** For topology groups the two are not equivalent:

- **A group's members may themselves be groups.** `GET /topology-groups/members` returns direct
  members, which can be sub-groups. Piping them yields group names where array names are
  required. `.arrays` is transitive over the whole sub-tree; enumerating members is not.
  Measured on the standing nested fixtures: `parent.arrays` → 2 arrays, reaching `FB-B` *through*
  the sub-group, while the member list returns a group plus one array.
- **Membership drifts.** A client-side name list is a snapshot; `.arrays` is re-resolved
  server-side on every request, so a durable context stays correct as arrays join or leave.
- **One request, not N.** Enumerating costs a round trip per level of nesting.

`Get-PfbTopologyGroupMember | Set-PfbContext` remains correct for "scope to these specific
members," but is not how to express "the whole group."

**The name is not resolved before the context is stored, and no network call is made.** This is
a change from rev 3, which specified a validating round trip. The wire rejects a bad name
loudly at first use:

| Context | Result |
|---|---|
| `zz-no-such-group.arrays` | `code 42 "Executor not found for zz-no-such-group.arrays"` |
| `cc-test-fleeet.arrays` | `code 42 "Executor not found for cc-test-fleeet.arrays"` |
| `<group>.array` / `.ARRAYS` | `code 42 "Cannot find array in fleet"` — the suffix is case-sensitive |
| `FB-B.arrays` (array + suffix) | `code 42 "Cannot specify parameter FB-B.arrays ..."` |

The `.arrays` forms **quote the offending value verbatim**, so the failure names its own cause
and arrives on the very next call. Rev 3's justification — a mistyped name stored and then
silently misdirecting every subsequent call — is empirically false. Validating would buy only
failing one call earlier, at the cost of a hidden network call on every context set and a
resolution path differing by kind (`GET /fleets?names=` for a fleet,
`GET /topology-groups/arrays?topology_group_names=` for a group, there being no `/fleets/arrays`),
where the group call is the weaker diagnostic of the two.

**No `-NoValidate` escape hatch ships**, because there is no validation to escape.

`-AllArrays` does still validate **locally**: `Kind = Array` with `-AllArrays` is rejected, as
is `Kind = TopologyGroup` with `Form = Object`.

### 10. Error annotation

The array returns `code 42 "Cannot find array in fleet"` for an unresolvable context name. As
drafted that flows through `ConvertTo-PfbApiError` as a bare "FlashBlade API error: Cannot find
array in fleet" — with no indication of *which* name caused it or that it came from a session
default set several calls earlier.

**The injection layer annotates context-targeting failures with the active context name(s).**
With `contextScope` in hand the annotation names the required context *kind* and the cmdlet that
sets it, not merely the value that failed:

> `Set-PfbPresetWorkload` targets a fleet-scoped resource, which requires a fleet context. The
> current context is the local array. Set one with `Set-PfbContext -Fleet <name>`, or run this
> call in a fleet context with `Invoke-PfbInContext -Fleet <name> { ... }`. Get the fleet name
> from `Get-PfbFleet`.

and the inverse:

> `Get-PfbFileSystem` targets an array-scoped resource; a fleet name is not a valid context for
> it. Use a member array name, or `<fleet>.arrays` to target every array in the fleet.

Every affected cmdlet's comment-based help also gains a `.NOTES` line stating its context
requirement, generated from the same field so it cannot drift from the validation.

### 11. Per-item attribution

A fanned-out response carries a **`context`** field on every item, naming its source array.
(Measured — the field is `context`, not `_context` as some upstream material suggests.) Without
surfacing it, fanned-out items are indistinguishable. Phase 1 must not strip it: the response
layer currently reads only `items` (`:219`), `total_item_count` (`:230`), and
`continuation_token` (`:236`) — everything else on the response body is discarded.

The `errors`-array and HTTP 207 half of fan-out is **Phase 2** — Phase 1 has no 207 branch, and
the status code is currently inspected only in failure paths (`:148`, `:352`).

---

## Resolved open questions

The design doc left seven open. Six are settled:

| # | Question | Resolution |
|---|---|---|
| 1 | Keep the explicit `-QueryParams['context_names']` precedence tier, which nothing in the public surface can populate? | **Keep** as defensive layering |
| 2 | Object-model surfacing of `Kind` / `Form` | Settled: explicit `-Kind` plus `-AllArrays` over an enum `Form`. **Do not ship `-NoValidate`** — rev 4 removes the validation it would have escaped |
| 3 | Annotate fleet-membership failures with the context name | **Yes** — section 10 |
| 4 | Multi-value mutating writes | **Throw, narrow-to-one**, first pass |
| 5 | Cross-platform (FlashArray) context in the same fleet | **No support.** Remains a non-goal; the module neither supports nor blocks it. Note `Get-PfbFleetMember` will happily return FlashArrays for piping into `Set-PfbContext`, so this pipeline must not be documented as safe for mixed-platform fleets |
| 6 | Fail-open on the no-signal verb fallback (unmapped `GET` treated as multi-value-capable) | **No work** — keep as is. One live instance, `GET /snmp-managers/test` |

**Open Question 7 remains open**: what a fleet-scoped endpoint should do with no context set.
Phase 1 **ships the client-side throw** with a message naming the requirement and the cmdlet
that satisfies it, and revisits later.

Default-to-fleet is no longer blocked on cost — an array belongs to at most one fleet (the API
states it at `POST /fleets/members/batch`, the endpoint family is singular throughout, and
`GET /fleets` returns exactly one entry even on a coordinator, measured), so the fleet name is
unambiguous and resolvable once at connect. What remains open is whether one-fleet membership is
a **guaranteed property of the model or a current limitation** — pending confirmation from Wes.
That answer decides whether the module may rely on it; until then, synthesizing a context the
caller never asked for is not justified.

---

## Out of scope

- **Phase 2** — `allow_errors` end-to-end: surfacing, default rules, HTTP 207 recognition, and
  the `errors` branch with per-array non-terminating errors keyed by `location_context`.
  Phase 1 reserves `AllowErrors` on the object and injects nothing for it.
- **Phase 3** — `context_ids`; an explicit multi-value mutating fan-out helper; display of the
  active context in `Get-PfbArrayConnection`; `Realm` as a context kind when the API ships it.
- **#38** — topology-group and fleet/realm object-management cmdlets, including
  `Get-PfbTopologyGroup` and `Get-PfbTopologyGroupMember`. Phase 1 owes #38 exactly one thing:
  the binding contract that `Get-PfbTopologyGroup` emit a top-level `Name`.
- **Module version bump and CHANGELOG** — the maintainer's own decision, not part of feature PRs.

---

## Testing

Per this repo's rule: **scope every run, both PowerShell editions**, via
`.claude/skills/run-pester-tests/scripts/Invoke-ScopedPester.ps1 -Path <files>`. Read the
`Container` column, not the counts. Never the aggregate suite as a completion check.

`[Parameter(Mandatory)]` tested by `Should -Throw` alone prompts and hangs under
`-NonInteractive` — use an optional parameter with an explicit throw. This applies directly to
`Invoke-PfbInContext`, which has three mandatory parameters.

Unit coverage:

- **Three-level precedence resolution**, including the empty-array "explicit none" case.
- **Capability-gated injection on both paths** — allow and hard-throw.
- **Version gate** — `Assert-PfbApiCapability` verified to run *after* injection so it actually
  sees the parameter. A test that supplies `context_names` in `-QueryParams` itself **cannot
  detect the ordering bug** — an early live test "confirmed" the gate that way and exercised a
  path the shipped code would not take. Drive it through the injection path.
- **Staleness** — within-range absence throws; beyond-range absence stays permissive.
- **`Invoke-PfbInContext` exception safety** — override restored when the scriptblock throws
  partway through, not only on the happy path.
- **Nested `Invoke-PfbInContext`** — the inner block restores the *outer* value, including when
  the inner block throws.
- **Cross-connection isolation** — an override set via `$fb1` must not affect `$fb2`.
- **Copy-on-write** — the original object's `.DefaultContext` untouched while the cache and
  default pointers move to the new copy.
- **Pipeline accumulation** — N piped members produce exactly one connection scoped to the union.
- **Pagination** — `context_names` persists across pages.
- **Cardinality** — multi-value on a non-capable endpoint throws; a capable one injects. Include
  one of the four fleet-scoped GETs as a fixture, since they are the case a verb-shaped rule
  gets wrong.
- **Local context is not special-cased** — a context naming the local array still throws on an
  unsupported endpoint.
- **Kind-vs-scope** — bare fleet or group name rejected on array-scoped endpoints and vice
  versa, one uniform error; `contextScope = unknown` suppresses the check rather than throwing.
- **`-AllArrays` composition** — `Form = AllArrays` renders `<name>.arrays` and not the bare
  name; `Kind = Array` with `-AllArrays` rejected; `Kind = TopologyGroup` with `Form = Object`
  rejected; and **no network call is made** when a context is set.
- **`authorization_model` gate** — a static-model admin setting or using any cross-array context
  throws client-side.
- **Fleet-scoped mutation with no context** — the OQ7 throw is asserted rather than left to the
  endpoint. A `New-`/`Set-`/`Remove-PfbPresetWorkload` call with no context must not reach the
  wire only to come back `code 13`.
- **Name-scoped read on a fleet-scoped endpoint** — `?names=` with no context must behave like a
  mutation, not an unfiltered list. This is the case a verb-shaped test misses.
- **Per-item `context` attribution survives** the response layer.

Test files in scope — existing: `Tests/Invoke-PfbApiRequest.*.Tests.ps1`,
`Tests/Assert-PfbApiCapability.Tests.ps1`, `Tests/PfbContextRuleTools.Tests.ps1`,
`Tests/Connect-PfbArray.*.Tests.ps1`, `Tests/ModuleManifest.Tests.ps1`. New:
`Tests/Set-PfbContext.Tests.ps1`, `Tests/Clear-PfbContext.Tests.ps1`,
`Tests/Invoke-PfbInContext.Tests.ps1`, `Tests/PfbContext.Tests.ps1`, and
`Tests/Test-PfbContextMultiValueCapable.Tests.ps1` — the predicate shipped in #73 with **no
dedicated test file**; its coverage today is indirect, via `PfbContextRuleTools.Tests.ps1`.
Phase 1 is the first runtime caller, so it owes the predicate direct tests.

Restoring a module `$script:` variable between tests (`$script:PfbDefaultArray`,
`$script:PfbArrays`) must pass the value through `param()` — a `.GetNewClosure()` against a
module scope fails under `StrictMode` and silently leaves state leaked.

---

## Live verification

Mandatory before this branch opens a PR. Two preconditions, each of which produces confident
wrong conclusions when violated:

1. **Probe from a remote member, never the local array.** A self-context test passes for the
   wrong reason — the server short-circuits a local context before validating anything.
2. **Run as a dynamic-authorization-model admin** (FSA `juemerson`), never static `pureuser`,
   which fails every probe with `code 20`. Multi-value context was once recorded as `code 20`
   and used as a cardinality contrast; that was a static-credential artifact. As a dynamic
   admin, `GET /file-systems?context_names=FB-B,FB-C` returns 200 with 2 items. `code 15` is
   the real cardinality signal and is independent of the authorization model.

Target FB-A (`cc-test-fleet` coordinator, Purity//FB 4.8.2, REST 2.26) with FB-B and FB-C as
members. Standing nested fixtures exist and are **retained deliberately**:

| Group | Direct members |
|---|---|
| `zz-claude-tg-parent` | `zz-claude-tg-child` (a group), `FB-C` |
| `zz-claude-tg-child` | `FB-B` |

`FB-A` is in neither. **A `.arrays` test must assert `FB-A`'s absence, not just the item
count** — a correct 2-array result and a silent fallback to local execution differ only in
which arrays come back. Transitivity cannot be tested against a flat hierarchy at all; a
single-level fixture passes a test that proves nothing.

Verify live, at minimum: single-array context switch; multi-value fan-out on a capable GET;
`code 15` on one of the four fleet-scoped GETs; `.arrays` transitivity through the sub-group;
the kind-vs-scope throw against `/presets/workload`; the OQ7 throw; and `context_names`
persisting across a paginated call.

⚠ `GET /topology-groups/arrays` cannot be probed bare — its own parameter validation runs
*before* the context check and returns `code 24`. A bare `code 24` from it is not evidence
either way.

---

## Risks

| Risk | Handling |
|---|---|
| Phase 0 does not merge first | Hard dependency. Rebase before opening the PR; do not stack |
| Injection placed after `Assert-PfbApiCapability` | The version gate silently never fires. Covered by a test that drives injection rather than supplying the parameter |
| Context lost on page 2+ | Covered by a pagination test against an endpoint that genuinely paginates |
| Cardinality rule reimplemented instead of called | Phase 0's resolver plus the existing predicate; assert there is exactly one `Context_names_get` comparison in `Private/` |
| Concurrent workers race on `.ContextOverride` | Documented limitation with explicit guidance; not fixed in Phase 1 |
| A static-model lab session makes a real capability look unsupported | The authorization gate converts it to a clear message; live testing uses the dynamic admin |
| `Get-PfbTopologyGroup` absent, so the group `-AllArrays` path has no source cmdlet | Exercise via fleet and hand-constructed input; the contract on #38 covers the eventual pipeline |
