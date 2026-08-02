# Design: Fusion context injection (`context_names` / `allow_errors`)

Status: **Draft / for review** (rev 3)
Author: Don Mann
Revised with live-testing evidence and design input from: Justin Emerson, Wes Mertes
(API architecture consult)
Related: Fusion / fleet support, `Private/Invoke-PfbApiRequest.ps1`, capability map
(`Data/PfbCapabilityMap.json`), `Private/Assert-PfbApiCapability.ps1`

## What changed since rev 2

Rev 2 fixed rev 1's two central errors (silent skip -> hard throw; module script scope ->
connection-object state). Both survive unchanged. Rev 3 closes gaps rev 2 left open and
corrects one claim rev 2 stated as settled:

- **`allow_errors` is specified.** Rev 2 did not mention it at all, though it is one of the
  two parameters this feature exists to inject.
- **`context_names` is a family of context kinds**, not an array name. Rev 2 treated it
  throughout as "a specific fleet member."
- **The verb rule is withdrawn.** Rev 2 proposed treating every `GET` as
  multi-context-capable. Live testing on 2026-08-01 disproved that for four endpoints.
  Cardinality is now data-driven from the capability map.
- **HTTP 207 and the `errors` response array** are specified as a response-layer
  requirement.
- **A cross-array authorization precondition** (`authorization_model`) is specified.
- **The capability-map staleness question is decided** rather than left implicit, and the
  dissenting view is recorded.
- **Phasing is corrected.** Rev 2 put `Invoke-PfbInContext` in Phase 2 while relying on it
  in Phase 1 as the documented escape hatch from the Phase 1 hard throw.

Everything asserted below about wire behavior was measured against real arrays. See
Appendix A. Section 8's rule and its supporting figures were independently reproduced
against the specs, and re-verified on a live fleet using a **remote** member, by a second
agent implementing the predicate.

**Scope of this document.** This is the design only. The cardinality predicate ships ahead of
it on its own branch; the implementation described here lands as a separate PR built on top of
that one.

---

## Problem

Many FlashBlade REST endpoints accept a `context_names` query parameter (Fusion fleet
context) so a single management connection can target something other than the local array.
Today the module has no first-class way to set that: a caller would have to drop to raw REST
or hand-build query params.

The naive fix -- add a `-Context` parameter to every affected cmdlet -- is a non-starter:

- The module exports ~520 cmdlets. Threading a new parameter through all of them (and
  keeping it in sync as endpoints change) is a large, error-prone surface.
- Not every endpoint accepts `context_names`. A blanket parameter would let callers send it
  to endpoints that cannot honor it -- and, as measured, most of those **silently accept and
  ignore it** rather than returning an error.
- `context_names` arrived at a specific REST version per endpoint. The capability map
  already records that; we should reuse it rather than re-encode it by hand.

## Goals

- Let a caller pick a fleet context once and have it apply to subsequent calls, with a
  per-call override that needs no session-wide change.
- Support the full family of context kinds the API exposes -- a single array, a Fleet, a
  Topology Group, and fan-out across member arrays.
- **Never let a context request be silently dropped.** A context-scoped call must either
  land where the caller asked or fail loudly -- never silently execute against the local
  array.
- Never send `context_names` to an endpoint (or array version) that cannot honor it.
- Handle partial-fleet failures (`allow_errors`, HTTP 207) as a first-class sibling of
  context, not a later bolt-on.
- Zero change to the ~520 public cmdlet signatures.

## Non-goals

- Modelling every Fusion concept (realms, presets, fleet-membership management as a
  feature). This spec covers injecting `context_names` / `allow_errors` into outbound
  requests and the minimal cmdlet surface to control them.
- `context_ids` (id-based targeting). Names first; ids can follow the same shape.
- **Cross-platform context.** A Fusion fleet may contain FlashArrays as well as
  FlashBlades, and `Get-PfbFleetMember` will return them. Whether a FlashBlade management
  connection can carry a FlashArray context is unresolved (Open Question 5) and is out of
  scope for this pass. The module neither supports nor blocks it.
- Client-side write fan-out across multiple contexts.

---

## Background: `context_names` is a family of context kinds

This is the correction everything below depends on. Following an architecture discussion
with Wes Mertes and live testing against a real 3-array fleet, `context_names` addresses
**four distinct things**:

1. **A single array** in the fleet -- switch this call's target to that array.
2. **A Fleet** -- address the fleet-level object itself. A Workload Preset is stored at the
   fleet level, not on any one array. This is *not* shorthand for "all arrays in the fleet."
3. **A Topology Group** -- address the group object itself.
4. **Fan-out across member arrays** -- a separate mechanism expressed by an **undocumented
   `.arrays` suffix** (`<fleet-name>.arrays`, `<topology-group-name>.arrays`). This is the
   only way to run a read against every array in a fleet or group.

Fan-out is orthogonal to the target kind: you do not infer "fan out to all members" from
"the name is a fleet." You must ask for it with the `.arrays` suffix. The design therefore
models a context as **a kind plus a separate fan-out flag**, rather than deriving fan-out
from the kind.

> **Spec gap:** the OpenAPI `context_names` description never mentions `.arrays` in any
> version from 2.17 through 2.28. It says only "an array in the fleet, or the fleet itself."
> The module's `.arrays` support rests entirely on live testing plus the Fusion
> administration guide, not on the API contract. Recorded in Appendix B.

### Array-scoped versus fleet-scoped endpoints

Each resource type accepts only the context kind it is scoped to. Measured behavior:

| `context_names` value | array-scoped (`/file-systems`, `/arrays`) | fleet-scoped (`/presets/workload`, `/topology-groups`) |
|---|---|---|
| *(not specified)* | local array | the local array's view of the fleet object |
| bare **remote array** name | works -- switches target | rejected -- `code 13 "Invalid context."` |
| bare **fleet** name | rejected -- `code 42 "Cannot specify context that is a fleet"` | **works** -- targets the fleet-level object |
| `<fleet>.arrays` | works -- fans out across fleet members | rejected -- `code 13 "Invalid context."` |
| `<topology-group>.arrays` | works -- fans out across exactly the group's members | n/a |
| two or more names | accepted (subject to authorization) | rejected -- `code 15 "Multiple location contexts are not allowed."` |

This matches the internal documentation: for fleet-scoped objects the only valid context is
the fleet name, and `.arrays` is not meaningful there.

Because the server's rejection messages are inconsistent across kinds and the `.arrays`
suffix is undocumented, the module validates kind-vs-scope **client-side** and produces one
uniform error rather than relaying the server's grab-bag of messages.

### The local-context short-circuit -- a testing trap

Middleware resolves `context_names` before scope validation: if the context matches the
**local** array, the call executes locally and no context validation happens at all. So
`GET /presets/workload?context_names=<local array>` returns 200 on a fleet-scoped endpoint
that rejects every other array name with `code 13`.

Two consequences:

- **A self-context test proves nothing** about whether an endpoint supports a context kind.
  Any live verification of context behavior must use a *remote* member.
- The module deliberately does not copy this behavior. See "Local context is still a
  context."

---

## Design

### 1. The single choke point

Every request funnels through `Invoke-PfbApiRequest`. That is the one place context is
resolved and injected, so no public cmdlet changes and the "zero change across ~520
signatures" property holds.

### 2. Context state lives on the connection object

Two properties on the `$Array` connection object, with two mutation policies:

- **`.DefaultContext`** -- the durable session default. Set at connect time or via
  `Set-PfbContext` / `Clear-PfbContext`, which are **copy-on-write**: they return a *new*
  connection object and never mutate the one the caller passed in.
- **`.ContextOverride`** -- the ambient, block-scoped value `Invoke-PfbInContext` sets.
  Mutable, but scoped by construction and restored via `try`/`finally`.

Storing this on the object rather than in `$script:` module scope fixes three failure modes
at once: cross-connection leakage disappears structurally; `$using:`-passed parallel work
sees the right context (`ForEach-Object -Parallel` / `Start-ThreadJob` share the live
instance, while `Start-Job` CliXml-clones it at fork time, which is what a fan-out wants);
and nesting works without an explicit stack.

It also matches how the module already writes `AuthToken` / `TokenExpiresAt` back onto
`$Array` during auto-reconnect. The distinction justifying copy-on-write for
`.DefaultContext` is that token refresh is a *transparent* mutation while context is a
*targeting* mutation that changes which array a write hits -- different risk classes, so a
different policy, not an inconsistency.

**Residual caveat to document:** concurrent workers mutating `.ContextOverride` on the same
shared object would still race. Guidance: set context before forking parallel work; do not
push ambient overrides from inside concurrent workers on a shared connection.

### 3. The context value object: `PfbContext`

A context is not a bare `string[]`:

| Field | Meaning |
|---|---|
| `Entries` | one or more context entries (below) |
| `AllowErrors` | tri-state -- governs partial-failure tolerance; see the `allow_errors` section |

Each **entry** carries its own kind and fan-out flag:

| Entry field | Meaning |
|---|---|
| `Name` | the context name |
| `Kind` | `Array` (default) \| `Fleet` \| `TopologyGroup` |
| `FanOut` | `bool` -- when `$true`, emit `<name>.arrays` instead of addressing the object |

**Why kind is per-entry rather than one scalar for the whole context.** Mixed-kind context
lists are on the near roadmap: with Fleet Users and Fleet Audits, `context_names` will accept
`ArrayA,ArrayB,myFleet` in a single `GET`, and the Fleet-audits design already documents
exactly that shape. A single `Kind` covering all names cannot express it. The field costs
nothing now and is a breaking change to add later, so the object reserves the shape in
Phase 1 even though Phase 1 only ever populates entries of one kind. Same reasoning as
reserving `AllowErrors` in Phase 1 while surfacing it in Phase 2.

Wire composition from an entry:

- `Kind = Array`, `FanOut = $false` -> bare array name.
- `Kind = Fleet` / `TopologyGroup`, `FanOut = $false` -> bare fleet/group name (addresses
  the object).
- `FanOut = $true` -> `<name>.arrays`.

Reserved by implication, not implemented: `Realm` as a future kind.

### 4. Resolving and injecting context in `Invoke-PfbApiRequest`

Resolve the effective context once, at the top of the choke point:

```
explicit -QueryParams['context_names']  >  $Array.ContextOverride  >  $Array.DefaultContext  >  (none)
```

**Tri-state "none":** distinguish *unset* (`$null`) from *explicit no-context*
(`[string[]]@()`). Both resolve to "nothing to inject," but the empty-array form is a
deliberate "run this one call locally" -- hence `[AllowEmptyCollection()]` and a `-ne $null`
check, not a truthiness check. Only a **non-empty** resolved context is subject to the
hard-throw gate, so `Invoke-PfbInContext -Context @()` is the escape hatch for running one
call locally on an endpoint that does not support `context_names`.

#### Injection / gating decision table

| Condition | Action |
|---|---|
| No context set (`$null` or explicit `@()`) | No injection, no check. Unchanged behavior. |
| Context set **and** the map entry lists `context_names` | Inject. Let `Assert-PfbApiCapability` catch "recorded but array too old." |
| Context set, map has no entry for `Method Endpoint` **or** the entry does not list `context_names`, **and** the array's version is *within* the map's scanned range | **Throw.** Name the endpoint; do not send the request. |
| Same, but the array's version *exceeds* the scanned range | Do **not** throw. Proceed permissively -- see "Capability-map staleness." |
| Context is multi-value **and** the endpoint is not multi-context-capable | **Throw**, telling the caller to narrow to one context. See "Cardinality." |
| Context kind is incompatible with the endpoint's scope | **Throw** with one uniform message. See "Background." |

Inject by **mutating the `$QueryParams` hashtable**, never the built query string.

**Apply the throw uniformly across all verbs, including `GET`.** Softening reads to
`Write-Warning` does not hold up: `-WarningAction SilentlyContinue` is routine in exactly the
automation most likely to set a read-scoped context; a wrong-scoped read inside a loop over
fleet members corrupts a result set invisibly; and a `GET`'s output routinely feeds a
subsequent mutating call.

#### Local context is still a context

If the caller sets a context naming the **local** array and then invokes a cmdlet whose
endpoint does not support `context_names`, the module **still throws**. It does not
special-case "this context happens to resolve to where we already are."

This deliberately diverges from server behavior, which short-circuits a local context before
validating anything. The reason: a cmdlet that works only *some* of the time, depending on
which array the context happens to name, is a worse contract than one that fails
consistently. A caller who wants to touch the local system should `Clear-PfbContext` (or
`Invoke-PfbInContext -Context @()`) and say so, rather than setting a context that means "no
context." Settled with Wes on 2026-07-23.

#### Why "always send, let the array error" was rejected

Two hypotheses were live-tested:

- **Endpoint that never supported `context_names`** (`/alert-watchers`): the array **silently
  accepted** the parameter -- HTTP 200, real create/update mutations applied, zero mention of
  `context_names`. There is no error to surface.
- **Parameter recorded but introduced later than the requested version** (`GET /admins` via
  `/api/2.10/`, `GET /dns` via `/api/2.22/`): cleanly rejected, HTTP 400, `code 24`. This case
  `Assert-PfbApiCapability` already catches locally today.

An audit of all 113 GET endpoints that never recorded `context_names` (REST <= 2.26) found
**90 of 113 silently accept** a bogus value, including the fleet-management surface itself
(`/fleets`, `/fleets/members`), and **2 endpoints that do process the parameter despite the
map, at the time of the audit, never recording it** (`GET /audits`; `GET /snmp-managers/test`).
21 were inconclusive.

Only one of those two is still a map gap. **`GET /audits` was fixed upstream at 2.28**, where
it now declares `Context_names_get`, `allow_errors` and a `207` -- a fully consistent
endpoint, recorded in the map, requiring nothing special. `GET /snmp-managers/test` remains
unrecorded at every scanned version; see section 8 for what the rule does with it.

Re-confirmed 2026-08-01, and more broadly: the array performs **no query-parameter validation
at all** on reads. An entirely invented parameter returns 200, and
`allow_errors=not_a_boolean` returns 200 even on an endpoint that genuinely declares
`allow_errors`. **Accepting a parameter is therefore not evidence that an endpoint supports
it**, which is why every capability decision below is made client-side from the map rather
than by probing the wire.

### 5. Implementation ordering (two non-obvious requirements)

1. **Inject before the existing `Assert-PfbApiCapability` call**
   (`Invoke-PfbApiRequest.ps1` line 41), not "immediately before the request is built"
   (which is near URL construction, around lines 77-80 -- after Assert has already run). If
   `context_names` lands in `$QueryParams` after Assert executes, Assert never sees it and the
   version check this design leans on never fires.
   > The original live test that "confirmed" the version gate called `Invoke-PfbApiRequest`
   > with `context_names` *already present* in `-QueryParams`, which is not how injection
   > delivers it. The ordering fix is what makes the real code path match the tested behavior.
2. **Mutate `$QueryParams`, not the built query string.** The `-AutoPaginate` loop rebuilds
   the query string from `$QueryParams` on every page (lines 224-230). Appending
   `context_names` to the first page's URI would drop it from page 2 onward. Not
   hypothetical: `Get-PfbArraySpace` already paginates.
3. **Move component resolution into `Private/` before wiring the cardinality check.** A
   prerequisite, not a nicety. The three-step resolution that turns a capability-map entry into
   a component name (override key-present-but-null, override key-absent, then the default) lives
   in `tools/lib/PfbContextRuleTools.ps1`, and `tools/` is **not shipped with the module**. The
   injection path needs that resolution to produce the predicate's `-ContextComponent` input and
   cannot import it from where it currently sits, so implementing in this order would silently
   force a second copy of the rule -- the exact duplication the single-declared-rule design
   exists to prevent. Move it first, then consume it from both sides.

### 6. `Set-PfbContext` / `Clear-PfbContext`

```powershell
Set-PfbContext
    [-Array] <PSCustomObject>   # ordinary param; defaults to the current default connection
    [-Context] <string[]>       # binds by property name (see Ergonomics)
    [-Kind <ContextKind>]       # Array (default) | Fleet | TopologyGroup
    [-FanOut]                   # switch -> .arrays suffix
    [-AllowErrors]              # tri-state; see allow_errors
    -> always returns the new connection object

Clear-PfbContext
    [-Array] <PSCustomObject>
    -> always returns the new connection object
```

- **Copy, not mutate.** A helper function, an outer stack frame, or a loop iteration holding
  the old `$fb` keeps its original scope; only the caller who captures the return value sees
  the change. This closes the "shared reference's scope changes out from under it" failure
  mode.
- **Always return the new object; no `-PassThru`.** The output *is* the effect.
- **Must swap the cache pointer.** The module tracks connections in `$script:PfbArrays` and
  `$script:PfbDefaultArray`. Both cmdlets must repoint those at the new copy, or callers using
  the implicit default connection would keep hitting the old object after the cmdlet
  "succeeded."
- **`Clear-PfbContext` ships as its own cmdlet**, matching the `Set-`/`Clear-PfbCredential`
  precedent, and because `@()` must keep its distinct meaning at the `Invoke-PfbInContext`
  layer.

Both are **Phase 1**. Without them, a context set at connect can only be changed by
reconnecting.

### 7. `Invoke-PfbInContext`

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

- **Nesting works with no explicit stack** -- each invocation captures its own `$previous`, so
  the PowerShell call stack provides push/pop discipline and the inner block's exit restores
  the *outer* value rather than clearing it.
- **Exception-safe via `finally`**, at every nesting level.
- **Per-connection by construction.**
- **Non-pipeable by design** -- its pipeline payload would have to be the scriptblock, which no
  cmdlet emits.

This is **Phase 1**, not Phase 2. It is the documented escape hatch from the Phase 1 hard
throw, so shipping the throw without it would ship a gate with no key.

### 8. Cardinality: which endpoints actually accept multiple contexts

The plural parameter is two spec components that both surface as `context_names`:

- **`Context_names_get`** -- documented multi-target fan-out, comma-separated.
- **`Context_names`** -- "the context names must be an **array of size 1**." The restriction
  lives only in free-text description, with no structured `maxItems`.

#### The verb rule is withdrawn

Rev 2 proposed treating this split as clean by verb -- `GET` multi-value, mutations size-1.
**That is false.** Live-tested 2026-08-01 against FB-A, with two valid fleet-member names:

```
GET /presets/workload?context_names=FB-A,FB-C          -> 400 code 15 "Multiple location contexts are not allowed."
GET /topology-groups?context_names=FB-A,FB-C           -> 400 code 15
GET /topology-groups/members?context_names=FB-A,FB-C   -> 400 code 15
GET /topology-groups/arrays?context_names=FB-A,FB-C    -> 400 code 15
GET /file-systems?context_names=FB-A,FB-C              -> 400 code 20 "Operation not permitted."   (control)
GET /admins, GET /arrays  (same query)                 -> 400 code 20                              (controls)
```

`code 15` fires *before* the cross-array authorization gate that produces `code 20`, so it is
a structural property of the endpoint, not a permission artifact. It is also independent of
name validity: `FB-A,no-such-array` yields `code 15` on these four but `code 42 "Cannot find
array in fleet"` on `/file-systems`.

These four are fleet-scoped endpoints. A fleet-scoped endpoint has exactly one meaningful
context -- the fleet -- so multi-value is not merely restricted there, it is meaningless.
Their spec entries reference `Context_names_get` in error.

#### The rule the module implements

> **An endpoint is multi-context-capable if and only if its `context_names` parameter
> resolves to component `Context_names_get` AND the endpoint also declares `allow_errors`.**

Both facts are already recorded per endpoint in `Data/PfbCapabilityMap.json`, so this is a map
lookup -- no new derivation and no new tooling. Against the committed map (`generatedFrom`
2.0-2.28, describing 2.28) that is **135** multi-context-capable endpoints of the 139
referencing the multi-value component; against fb2.27 it is 134 of 139.

Why `allow_errors` rather than the component name alone: the component reference is wrong for
five endpoints, while `allow_errors` is correct on every case for which evidence exists. A
genuinely multi-context endpoint needs a partial-failure story, so the absence of
`allow_errors` is strong evidence the endpoint cannot fan out -- which is exactly how the
upstream bug report characterizes the defect ("missing e.g. `allow_errors` / HTTP 207 /
`_context`").

**The verb remains only as a fallback** for an endpoint absent from the map entirely, where no
signal exists. It is not the rule.

#### The predicate this design consumes

Settled, and shipping ahead of this work as `Private/Test-PfbContextMultiValueCapable.ps1`.
Treat the signature as fixed -- the injection path is its first runtime caller, not its owner:

```powershell
Test-PfbContextMultiValueCapable
    -Method              <string>   # mandatory; used ONLY on the no-signal fallback path
    -ContextComponent    <string>   # nullable; $null/empty is what selects the fallback
    -DeclaresAllowErrors <bool>     # mandatory
    -> [bool]
```

It is pure -- no file I/O, no map loading, no module state. Each caller supplies facts from its
own source: the injection path from the map entry it has already resolved, the maintainer drift
check from the map or from a single spec version. That is what keeps one rule with two callers
instead of two copies of the rule. An unrecognized verb throws, but only when the fallback path
is actually reached; an unknown verb carrying a component signal is decided on evidence.

#### The conjunct is what makes the rule version-robust

An unplanned property, worth stating because it is a real argument for the two-signal rule over
the component alone. Four endpoints changed component across versions --
`DELETE /management-access-policies` (2.28), and `DELETE`/`PATCH /nfs-export-policies/rules`
plus `PATCH /object-store-roles/object-store-trust-policies/upload` (2.22) -- all
`Context_names_get` to `Context_names`. **None changes the rule's verdict**, because all four
declare no `allow_errors` at any version, so the conjunct absorbs the instability.

That is currently luck rather than design, and the exposure should be tracked. The capability
map is last-seen-wins with **no version dimension on component identity**, so an endpoint that
flipped component *while* declaring `allow_errors` would hand an array on an older REST version
the newer version's answer. Endpoints in that position today: **0**. Note the asymmetry --
`allow_errors` presence *is* version-stamped in the map (`parameters` maps name to introduced
version), so that half can be version-gated; the component half cannot. If the count ever leaves
zero, the component half needs a version dimension before it can be trusted.

#### The fallback fails open, deliberately -- with one live instance

Where the map has no component at all, the predicate falls back to the verb and a `GET` is
treated as capable. That is a decision, not an oversight: it matches the module's founding
principle of not blocking calls that may well work. **It has one live instance today.**
`GET /snmp-managers/test` processes `context_names` on the wire, yet no scanned spec records
it, so the predicate returns capable on zero evidence. Accepted: a wrong "capable" produces a
clean wire-400 the caller can read, whereas a wrong "size-1" produces a local throw against an
endpoint that would have worked. Revisit only if the unrecorded set grows or a fail-open case
is found to do something worse than 400.

#### Signals considered, and their reliability

Counts are **version-specific and moving**, so both scanned versions are given. The
reliability judgements are unchanged between them; only the populations differ.

| Signal | fb2.27 | fb2.28 | Reliability as a cardinality signal |
|---|---|---|---|
| References `Context_names_get` | 139 | 139 | Wrong for 5 at 2.27, 4 at 2.28 (the fleet-scoped GETs, plus one DELETE that is fixed at 2.28) |
| Declares `allow_errors` | 135 | 136 | Correct on every case with evidence |
| Declares an HTTP `207` response | 124 | 132 | Correct, but stricter -- excludes endpoints of unknown status (11 at 2.27, 4 at 2.28) |
| Carries an `errors` envelope field | 139 | 139 | **Unreliable** -- applied by authoring convention |
| Satisfies the ratified rule | 134 | 135 | -- |

The `errors` envelope arrives via an `allOf`-composed `_errorContextResponse` component and is
present on 15 endpoints that declare no `207`, including all four fleet-scoped GETs. It says
nothing about fan-out capability and must not be used as a signal.

`207` is the strictest signal and the one upstream tooling uses, but gating on it would treat
endpoints of unknown status as size-1 on no evidence, blocking calls that may well work --
contrary to the module's founding capability-check principle. That set is shrinking as 207
coverage grows: 11 at fb2.27 (`/realms`, `/file-systems/sessions`, `/file-systems/locks` and
the management-authentication-policies family), down to 4 at fb2.28
(`/realms`, `/arrays/ssh-certificate-authority-policies`,
`/audit-file-systems-policy-operations`, `/log-targets/file-systems`). The argument does not
depend on the size of the set, only on its being non-empty. It is also **not
available at runtime**: the capability map records the request surface only, with no response
data at all. `207` therefore serves as a corroborating signal for the maintainer drift check,
sourced from the specs under `tools/`, and never as a runtime gate.

#### Behavior when a multi-value context meets a size-1 endpoint

**Throw, and tell the caller to narrow to one.** The module does not silently fan the call out
client-side, because:

1. It silently changes the return shape -- one object becomes N, driven by session state the
   calling code may not see.
2. Partial failure has no clean silent answer.
3. It is not equivalent to the server's read-side fan-out, which resolves a multi-context
   `GET` as one atomic request. N client-issued calls have no atomicity and no retry safety.

Wes confirmed the server throws in this case and that the client should too, while noting he
would otherwise prefer the client send and let Purity error. That preference does not survive
the silent-accept finding above: for endpoints that ignore unknown parameters there is no
server error to surface, so the client-side check does work the server will not.

> A separately-named, explicit opt-in helper returning per-context-annotated results with loud
> partial-failure reporting remains a possible future addition -- never behavior triggered
> automatically by cmdlet-plus-context-shape. (Open Question 4.)

#### Keeping the rule honest

Cardinality is a moving target: the upstream fix for the four fleet-scoped endpoints is in
review, and when it lands their signals change. The rule above therefore must not live as a
comment in the injection path. It is declared in exactly one place and verified by the
maintainer drift report, which compares the module's rule against all available spec signals
and reports any endpoint whose signals do not agree -- including the case where the rule and
the component name agree but the remaining signals dissent, which is precisely the case that
exists today. Two-signal comparison is insufficient: it cannot see both sides being wrong in
the same direction.

### 9. `allow_errors`

Surfaced through the same `PfbContext` object and the same two-tier mechanism as context, not
as a bare per-call switch.

- **Two-tier surfacing.** A durable connection default (`PfbContext.AllowErrors`, via
  `Set-PfbContext -AllowErrors`) plus a block-scoped override. "Tolerate individual array
  failures while exploring the fleet" is a session mode, set once.
- **Default `$true` only when a multi-value or fan-out context is actually being sent.** This
  **deliberately diverges from the API's own default of `false`**, to match PowerShell's
  native multi-target idiom (`Get-ChildItem` over several `-Path`s, `Get-Process
  -ComputerName` over several hosts) where one bad target degrades gracefully. The divergence
  is stated here rather than buried, because it is a reviewable decision.
- **Only injected when the endpoint declares it.** This follows from the cardinality rule: an
  endpoint that does not declare `allow_errors` is not multi-context-capable, so the case
  cannot arise. The gate is belt-and-braces, and it keeps the module from injecting a
  parameter the endpoint never declared.
- **With single-value or no context, `allow_errors` is irrelevant and is not sent.**

### 10. Response layer: HTTP 207 and the `errors` array

When a multi-context request partially fails, the array returns **HTTP 207 Multi-Status** with
a body containing both `items` (successful results) and `errors`, each error entry carrying a
`location_context` naming the array where that lookup failed. Live-verified against a 3-array
fleet, and documented in the Fleet-audits design.

`Private/Invoke-PfbApiRequest.ps1` handles neither half today:

- It inspects the status code only in its failure path, and only for 401/403. A 207 is a 2xx,
  so `Invoke-RestMethod` does not throw and the response is treated as a clean success.
- Its response handling reads only `items`, `total_item_count`, and `continuation_token`
  (around lines 206-215). There is no `errors` branch. Those three fields are the module's
  only hardcoded response contract.

**Required:** recognize 207 as a distinct outcome, and emit one non-terminating `Write-Error`
per failed context (naming the array from `location_context`) while passing successful `items`
down the pipeline. Without this, per-array failures are silently dropped and a partial result
is indistinguishable from a complete one.

This is currently unreachable dead ground -- nothing shipped sends a multi-value context --
which is why it is a feature requirement here rather than a standalone bug. The maintainer
drift work will separately *report* the missing `errors` branch as a response-shape finding;
**fixing it belongs to this feature**, and that split is deliberate so the two efforts do not
collide on `Invoke-PfbApiRequest`.

### 11. Precondition: cross-array context requires a dynamic-authorization-model admin

Live-tested: **every `context_names` call targeting anything other than the connected array's
own local context** -- a single-value switch, an explicit multi-array list, or `.arrays`
fan-out -- fails with `code 20 "Operation not permitted."` when connected as the local
`pureuser`, and succeeds for an LDAP-authenticated admin. There is no single-vs-multi
distinction; a bare single-array switch fails exactly like fan-out does.

This is **not** a "`pureuser` vs everyone" distinction:

- Since 4.5.0, admins can create additional named **local** users with the same privileges;
  the 4.8.1 **service-account** admin type is also local.
- All three -- `pureuser`, custom local users, service accounts -- have
  `authorization_model: static`.
- Only **LDAP/SAML remote-user admins** get `authorization_model: dynamic`.

Confirmed on FB-A, where `GET /admins` reports `pureuser` as `static` and the LDAP admin as
`dynamic`. Independently documented: "Only AD/LDAP authenticated users are allowed to execute
fleet commands or do remote provisioning... Non-LDAP users (`pureuser`, `puresupport`, etc.)
are disallowed to issue cross-array requests."

**Recommendation: check client-side** at `Connect-PfbArray` / `Set-PfbContext` and throw
immediately when a static-model admin sets or uses any cross-array context:

> "targeting a context other than the local array requires a dynamic-authorization-model
> (LDAP/SAML) admin; static-model admins, including `pureuser` and other local accounts, are
> not permitted."

A user hitting the raw "Operation not permitted" has no obvious reason to suspect their *auth
method* rather than their fleet setup.

---

## Capability-map staleness

`Assert-PfbApiCapability`'s founding principle: *a capability check must never be the reason a
call that would otherwise succeed gets blocked.* A naive "absent from map -> throw" breaks it:
if an array runs firmware newer than anything the map was built from, and that firmware added
`context_names` to an endpoint the map never scanned, a flat throw would block a call that
would actually succeed.

The throw therefore keys on `Data/PfbCapabilityMap.json`'s `generatedFrom` array, which
records exactly which REST versions were scanned:

- **Connected version within the scanned range** and no `context_names` entry -> absence is
  *confirmed*. Throwing blocks nothing that should work.
- **Connected version exceeds the scanned range** -> no evidence either way. Stay permissive:
  proceed without injecting or throwing.

> The gating table's third and fourth rows must mirror each other exactly. The likeliest real
> staleness case is an endpoint that exists today and *gains* `context_names` in a future
> version -- entry present, parameter absent -- not an endpoint missing from the map.

**Decision, and the dissent.** Wes argued the opposite: that permissiveness trades away safety,
and that he would prefer erring toward caution given the module cannot distinguish "never
supported" from "supported in a version we have not scanned." That objection is recorded
because it is reasonable. The decision is nonetheless to keep the permissive fallback, for a
reason specific to this module rather than to the API:

> A caller using the REST API directly names a version in the URL -- they have already chosen
> `/api/2.26/` and can reason about what that version supports. A cmdlet caller has not; the
> module negotiates the version for them. Blocking a call because *the module's bundled map* is
> older than the array punishes the user for a packaging lag they cannot see and did not
> choose. The correct remedy is to tell them the map is behind, not to refuse the call.

The connect-time warning below is what makes that trade honest, and is a required part of the
decision rather than a nicety.

### Connect-time staleness warning

Not specific to `context_names` -- it is the general fact that the module's capability
knowledge can lag a customer's Purity//FB release. `context_names` is the sharpest instance
because its lag has a silent rather than a clean wire-400 failure mode.

- **Check once, unconditionally, at `Connect-PfbArray`**, regardless of whether `-Context` is
  passed. Compare the negotiated `$Array.ApiVersion` against the map's `generatedFrom` maximum
  and cache the result on the connection (e.g. `.ExceedsCapabilityMapCoverage`) rather than
  recomputing per call.
- **One-shot per connection** -- fires once for the life of the connection no matter how many
  calls or context changes follow.
- Because it fires at connect universally, `Set-PfbContext` / `Invoke-PfbInContext` need no
  trigger of their own; a defensive re-check there is cheap insurance for a connection cached
  from before an upgrade.
- **Concrete message**, naming the sharp case:

  > Connected array is running REST 2.29; this module's capability map only covers through REST
  > 2.28 -- capability checks for anything newer, including context scoping, cannot be fully
  > verified and may not error even if unsupported. Check the PowerShell Gallery for a newer
  > release (`Update-Module`).

- **No live Gallery lookup.** `Find-Module` is a network dependency with real latency and
  failure modes, and this module runs against air-gapped lab and customer arrays. Point at the
  mechanism; do not auto-detect whether an update exists.

---

## Ergonomics: `Get-PfbFleetMember` -> context

A natural flow is discovering fleet members and piping them into a context cmdlet. Neither of
these binds today:

```powershell
Get-PfbFleetMember -FleetName 'fleet-prod' | Set-PfbContext             # does not bind
Get-PfbFleetMember -FleetName 'fleet-prod' | Invoke-PfbInContext { ... } # never pipeable
```

`Get-PfbFleetMember` returns raw `FleetMember` objects whose top-level properties are
`coordinator_of`, `fleet`, `member`, `status`, `status_details`. The array name is nested at
`.member.name`, and `ValueFromPipelineByPropertyName` matches only top-level names, so nothing
binds and the pipe silently no-ops -- the same silent-wrong-scope family this design fights.

### Works today, no code change -- document as the canonical form

```powershell
$fb = Set-PfbContext -Array $fb -Context (Get-PfbFleetMember -FleetName 'fleet-prod').member.name

Invoke-PfbInContext -Array $fb -Context (Get-PfbFleetMember -FleetName 'fleet-prod').member.name {
    Get-PfbFileSystem -Array $fb
}
```

This is the blessed form for the non-pipeable `Invoke-PfbInContext`.

### Make `Get-PfbFleetMember | Set-PfbContext` first-class

- **(a) Emit useful top-level properties.** Decorate each object with top-level `MemberName`
  (`= $_.member.name`) and `FleetName` (`= $_.fleet.name`). Worth doing on its own merits: it
  makes the object readable at the console *and* gives the pipeline something to bind.
- **(b) `-Context` binds by property name:**
  ```powershell
  [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
  [Alias('MemberName','Name')]
  [string[]]$Context
  ```
- **(c) Give the pipeline slot to the context.** `-Array` becomes an ordinary parameter
  defaulting to the current default connection. Because `Set-PfbContext` is copy-on-write it
  must **accumulate piped items in `process{}` and emit exactly one connection in `end{}`**,
  scoped to the union -- otherwise N piped members yield N connection objects.

```powershell
$fb = Get-PfbFleetMember -FleetName 'fleet-prod' | Set-PfbContext
```

**`$fb | Set-PfbContext` is dropped as redundant.** Piece (c) trades away piping the
*connection* in. That trade is correct: `Set-PfbContext -Array $fb -Context 'b'` and the
implicit-default form already cover it, and it is the only thing standing between us and the
far more valuable `Get-PfbFleetMember | Set-PfbContext`. (Rev 2 documented
`$fb = $fb | Set-PfbContext -Context 'b'` as the durable path; that form is withdrawn.)

**`IsLocal` is deliberately not surfaced.** The obvious third property looks useful -- filter
out the local array before scoping a context -- but `is_local` is relative to *the call's
context*, not to the connection: call `/fleets/members` with context ArrayB and ArrayB reports
`is_local = true` while ArrayA reports `false`. A documented `Where-Object { -not $_.IsLocal }`
idiom would therefore select a different array once a context is active, silently. Determining
the local array should use the connection, not a per-call response field. (`/fleets/members`
may not accept `context_names` at all yet, which masks the problem today but does not fix it.)

**Multi-value hits the cardinality limit.** Piping many members yields a multi-value context:
valid for fan-out-capable `GET`s, rejected elsewhere. "Pipe all members into a durable context"
is a *read-scoping* ergonomic and should be documented as such.

**Topology groups get a cmdlet path, not a `Set-PfbContext` feature.** Rather than teaching
`Set-PfbContext` to understand group membership, a `Get-PfbTopologyGroupMember` cmdlet feeds
the same pipeline: `Get-PfbTopologyGroupMember -Group g | Set-PfbContext`. That reaches the
same outcome as `<group>.arrays` for the read-scoping case while keeping group semantics out of
the context cmdlet.

---

## Security / authorization note

`context_names` is **not itself an auth boundary.** Any caller with a valid management
connection can *attempt* to target any fleet member by name; protection is entirely server-side
-- the `authorization_model` gate above, and RBAC (e.g. the `403 Access Denied` observed on
`/management-access-policies`). The client enforces nothing about which contexts a caller may
target beyond the proactive `authorization_model` and kind-vs-scope checks, which exist to
produce clear errors, not to grant or deny access.

## Error surfacing for fleet-membership failures

The array returns `code 42 "Cannot find array in fleet"` for a context name it cannot resolve.
As drafted, that flows through `ConvertTo-PfbApiError` as a bare "FlashBlade API error: Cannot
find array in fleet" -- with no indication of *which* context name caused it, or that it came
from a session default set several calls earlier. **The injection layer should annotate
context-targeting failures with the active context name(s).** (Open Question 3.)

---

## Testing plan

- **Three-level precedence resolution**, including the empty-array "explicit none" case.
- **Capability-gated injection on both paths** -- allow and hard-throw.
- **Version gate** -- `Assert-PfbApiCapability` for `context_names`, verified to run *after*
  injection so it actually sees the parameter.
- **Staleness behavior** -- within-range absence throws; beyond-range absence stays permissive;
  the connect-time warning fires exactly once per connection.
- **`Invoke-PfbInContext` exception safety** -- override restored when the scriptblock throws
  partway through, not just on the happy path.
- **Nested `Invoke-PfbInContext`** -- the inner block restores the *outer* value, including when
  the inner block throws.
- **Cross-connection isolation** -- an override set via `$fb1` must not affect calls made with
  `$fb2`.
- **`Set-PfbContext` copy-on-write** -- the original object's `.DefaultContext` untouched while
  the cache and default pointers move to the new copy.
- **Pipeline accumulation** -- N piped members produce exactly one connection object scoped to
  the union.
- **Pagination** -- `context_names` persists across pages.
- **Cardinality** -- a multi-value context on an endpoint that is not multi-context-capable
  throws; a capable endpoint injects. Include one of the four fleet-scoped endpoints as a
  fixture, since they are the case the verb rule got wrong.
- **Local context is not special-cased** -- a context naming the local array still throws on an
  endpoint that does not support `context_names`.
- **`allow_errors`** -- injected only when the endpoint declares it; defaulted `$true` only when
  a multi-value or fan-out context is sent; never sent otherwise.
- **HTTP 207** -- recognized as a distinct outcome; one non-terminating `Write-Error` per
  `errors` entry, keyed by `location_context`; successful `items` still flow down the pipeline.
- **Kind-vs-scope validation** -- a bare fleet or group name rejected client-side on
  array-scoped endpoints and vice versa, with one uniform error.
- **`authorization_model` gate** -- a static-model admin setting or using any cross-array
  context throws client-side.

Live verification must use a **remote** fleet member. A self-context test passes for the wrong
reason (see "The local-context short-circuit").

---

## Phasing

- **Phase 1**: `-Context` on `Connect-PfbArray`; the `PfbContext` object (per-entry
  `Kind`/`FanOut`, reserved `AllowErrors`) plus `.DefaultContext` / `.ContextOverride` on the
  connection; central capability-gated hard-throw injection with the ordering fixes;
  `Set-PfbContext` / `Clear-PfbContext`; `Invoke-PfbInContext`; kind and fan-out with
  client-side kind-vs-scope validation; the data-driven cardinality rule and its throw; the
  `authorization_model` precondition; the connect-time staleness warning; `Get-PfbFleetMember`
  top-level `MemberName`/`FleetName` and the `Set-PfbContext` pipeline binding.
- **Phase 2**: `allow_errors` end-to-end -- surfacing, default rules, and the response-layer
  work (HTTP 207 recognition plus the `errors` branch with per-array non-terminating errors).
- **Phase 3**: `context_ids`; `Get-PfbTopologyGroupMember`; an explicit multi-value mutating
  fan-out helper if wanted; display of the active context in `Get-PfbArrayConnection`; `Realm`
  as a context kind when the API ships it.

> Rev 2's phasing deferred `Invoke-PfbInContext` to Phase 2 while Phase 1 depended on it as the
> escape hatch from the Phase 1 throw. That is corrected above.

---

## Open questions

1. **"Explicit `-QueryParams['context_names']` wins" -- over what, concretely?** Nothing in the
   shipped public surface can populate that tier: every public cmdlet builds its own fixed
   `QueryParams` and `Invoke-PfbApiRequest` is private. The tier is reachable only by
   module-internal code or a future cmdlet. Stated here so no reader assumes a path exists.
   Keep as defensive layering, or drop it?
2. **Object-model surfacing of `Kind` / `FanOut`.** This doc assumes explicit `-Kind` (default
   `Array`) plus a `-FanOut` switch with client-side validation. The alternative -- inferring
   kind by querying the fleet's topology -- was rejected to avoid hidden network calls, but is
   legitimate if discoverability is valued over predictability. Confirm.
3. **Context-name annotation on fleet-membership failures.** Recommendation is to annotate
   `code 42` and similar with the active context name(s). Confirm, or accept as a known rough
   edge.
4. **Multi-value mutating writes.** This doc chooses throw, narrow-to-one. Confirm throw-only
   for the first pass.
5. **Cross-platform context.** Can a FlashBlade connection carry a FlashArray context within the
   same fleet? Unanswered upstream. Currently a non-goal: the module neither supports nor blocks
   it, and `Get-PfbFleetMember` will happily return FlashArrays for piping into
   `Set-PfbContext`. Needs an answer before that pipeline is documented as safe.
6. **Fail-open on the no-signal fallback.** Section 8 chooses to treat an unmapped `GET` as
   multi-value-capable, on the grounds that a wrong "capable" yields a readable wire-400 while a
   wrong "size-1" locally blocks a call that would have worked. This is consistent with the
   module's capability-check principle but it is a behavioral choice, and it has one live
   instance (`GET /snmp-managers/test`). Confirm, or fail closed.

---

## Alternatives considered and rejected

- **Silent skip-injection when the endpoint does not support `context_names`** (rev 1's step 3).
  For a mutating call it produces a *successful* request that silently landed on the local array
  -- worse than an error.
- **"Always send `context_names`, let the array's error surface."** 90 of 113 never-supported
  GET endpoints silently accept and ignore it, and the array performs no query-parameter
  validation at all on reads. There is no error to surface.
- **Softening reads (`GET`) to `Write-Warning`.** Warnings are routinely suppressed in the
  automation most likely to set a read-scoped context.
- **The verb rule as the cardinality rule** (rev 2). Falsified by live testing: four
  fleet-scoped `GET`s reject multi-value context with `code 15`.
- **Gating cardinality on the component name alone.** Wrong for five endpoints, and it cannot
  distinguish a spec defect from a real capability.
- **Gating cardinality on HTTP `207`.** The strictest and most accurate signal, and the one
  upstream tooling uses -- but it would treat endpoints of unknown status as size-1 on no
  evidence (11 at fb2.27, 4 at fb2.28), and it is unavailable at runtime because the
  capability map holds no response data.
- **Treating the `errors` envelope field as a fan-out signal.** It is applied by an
  `allOf`-composed authoring convention and is present on 15 endpoints that declare no `207`,
  including all four fleet-scoped GETs.
- **Special-casing the local array as "no context needed."** The server does this; the module
  deliberately does not, because a cmdlet that works only when the context happens to name the
  local array is a worse contract than one that fails consistently.
- **Special-casing `pureuser`** for the cross-array permission gate. Custom local users and
  service accounts share `authorization_model: static` and hit the same wall.
- **Storing ambient context in module `$script:` scope.** Cross-connection leakage, no runspace
  portability, single-slot nesting bugs.
- **Mutating `.DefaultContext` in place, and piping the connection into `Set-PfbContext`.**
  In-place mutation changes scope out from under other holders of the reference; the pipeline
  slot is worth more to `Get-PfbFleetMember | Set-PfbContext`.
- **Surfacing `IsLocal` on `Get-PfbFleetMember`.** It is relative to the call's context, so any
  filter built on it changes meaning once a context is active.
- **A single scalar `Kind` for the whole context.** Cannot express the mixed
  `ArrayA,ArrayB,myFleet` lists already designed upstream.
- **Live PowerShell Gallery lookup (`Find-Module`) for the staleness warning.** Network
  dependency, unusable against air-gapped arrays.

---

## Appendix A: empirical basis

Behavioral claims were verified against real arrays, not read from the spec.

**3-array Fusion fleet `cc-test-fleet`** -- bare-name versus `.arrays` semantics per context
kind; topology-group fan-out correctly excluding a non-member array; the `authorization_model`
gate; the `items` + `errors` + `location_context` response shape.

**FB-A (Purity//FB 4.8.2, REST 2.26), fleet coordinator of `cc-test-fleet` with FB-C as a
member, 2026-08-01:**

- All four fleet-scoped GETs reject any two-name context with `code 15`, while `/file-systems`,
  `/admins`, and `/arrays` reach `code 20` on the same input -- `code 15` precedes the
  authorization gate.
- `code 15` is independent of name validity (`FB-A,no-such-array` also yields it, where
  `/file-systems` yields `code 42`).
- Fleet-scoped endpoints accept a bare fleet name (200) and reject `<fleet>.arrays` (`code 13`);
  `/file-systems` rejects a bare fleet name with `code 42 "Cannot specify context that is a
  fleet"`.
- A context naming the **local** array returns 200 on `/presets/workload` while a remote array
  name returns `code 13` -- the middleware short-circuit.
- No query-parameter validation on reads: an invented parameter returns 200 everywhere, and
  `allow_errors=not_a_boolean` returns 200 on `/file-systems`, which genuinely declares it.
- `GET /admins` reports `pureuser` as `authorization_model: static` and the LDAP admin as
  `dynamic`.

**Independent re-verification, 2026-08-01** (second agent, FB-A, fleet `cc-test-fleet`, all
probes against remote member **FB-C** rather than the local array, so the middleware
short-circuit could not mask a result). Nine endpoints, **9 of 9 matching the rule's verdict**:
the four fleet-scoped GETs return `code 15` on a two-name context, while `/file-systems`,
`/admins`, `/arrays`, `/buckets` and `/policies` return `code 20`. The single-context control
is the load-bearing half -- a one-name context yields `code 13` on the size-1 set and `code 20`
on the capable set, so `code 15` tracks cardinality and not context rejection.

**Probing caveat:** `GET /topology-groups/arrays` cannot be probed bare. Its own parameter
validation runs *before* the context check and returns `code 24` ("`recursive` must be used
with `topology_group_names` or `topology_group_ids`") when the fleet has no topology groups.
Passing `topology_group_names=nonexistent` clears it, after which the endpoint returns `code 15`
as expected. **A `code 24` from that endpoint is not evidence either way** -- it means the
context check was never reached.

**FB-A and a second simulator (Purity//FB 4.6.5 / REST 2.22)** -- silent acceptance of
never-supported `context_names` on `/alert-watchers` across a create/patch/delete round trip;
clean wire-400 (`code 24`) for recorded-but-too-old on `/admins` and `/dns`.

**Audit of all 113 never-recorded GET endpoints (REST <= 2.26)** -- 90 silently accept, 2
map gaps at the time of the audit (`GET /audits`, since fixed at 2.28; `GET /snmp-managers/test`,
still open), 21 inconclusive. POST/PATCH/DELETE not audited.

**Spec analysis** -- at fb2.27: 139 endpoints reference `Context_names_get`, 236 reference
`Context_names`, 135 declare `allow_errors`, 124 declare a `207` response, 139 carry an
`errors` envelope field; 134 satisfy the cardinality rule. At fb2.28: 139 / 136 declaring
`allow_errors` / 132 declaring `207`; 135 satisfy the rule.
`DELETE /management-access-policies` is corrected to `Context_names` at 2.28, and `GET /audits`
becomes fully consistent, while the four fleet-scoped GETs are unchanged.
Independently reproduced 2026-08-01 by a second agent working from the specs directly.

**Capability map** (`generatedFrom` 2.0-2.28) -- 376 endpoints record `context_names`, of which
136 also record `allow_errors`; 139 resolve to `Context_names_get`, 237 to `Context_names`, 0 to
no component. 135 satisfy the cardinality rule. The map records the request surface only; it
holds no response data, so HTTP 207 is not available at runtime.

**Not verified** -- `PATCH /directory-services/test`, the one size-1 endpoint declaring
`allow_errors`, was not probed (mutating verb). Whether the wire's clean-rejection behavior
depends on live firmware knowing a later version's field remains inconclusive: the only endpoint
where `context_names` was introduced at exactly REST 2.26
(`POST/PATCH/DELETE /management-access-policies`) is RBAC-restricted.

## Appendix B: known spec defects

Tracked so the module's workarounds can be retired with evidence when each is fixed.

| Defect | Status |
|---|---|
| `DELETE /management-access-policies` referenced `Context_names_get` in 2.26/2.27 | **Fixed** in 2.28 (now `Context_names`). No exception was ever implemented in the module. |
| `GET /presets/workload`, `GET /topology-groups`, `GET /topology-groups/arrays`, `GET /topology-groups/members` reference `Context_names_get` but are size-1 on the wire, and declare neither `allow_errors` nor `207` | **Open upstream, in review.** Reported as incomplete remote-execution support, with fixes in flight against both the spec and the server. Still present at 2.28. |
| The `context_names` description never documents the `.arrays` suffix (2.17-2.28) | **Open.** The module's fan-out support rests on live testing and the administration guide, not the API contract. |
| `GET /audits` processed `context_names` though 2.26/2.27 did not record it | **Fixed** in 2.28: declares `Context_names_get`, `allow_errors` and `207`. Recorded in the map; no workaround needed. |
| `GET /snmp-managers/test` processes `context_names` though no scanned version records it | **Open.** A map gap within the scanned range, not staleness. The predicate falls back to the verb and returns capable on no evidence -- see section 8. |
| The `errors` envelope field is applied by authoring convention to 15 endpoints that cannot return a partial failure | **Cosmetic**, but it makes the field useless as a capability signal. |
