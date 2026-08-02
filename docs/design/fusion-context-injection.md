# Design: Fusion context injection (`context_names` / `allow_errors`)

Status: **Draft / for review** (rev 3)
Author: Don Mann
Revised with live-testing evidence and design input from: Justin Emerson, Wes Mertes
(API architecture consult)
Related: Fusion / fleet support, `Private/Invoke-PfbApiRequest.ps1`, capability map
(`Data/PfbCapabilityMap.json`), `Private/Assert-PfbApiCapability.ps1`

**Scope of this document.** This is the design only. The cardinality predicate ships ahead of
it on its own branch; the implementation described here lands as a separate PR built on top of
that one.

**How to read the evidence.** Every claim below about wire behavior is measured against real
arrays rather than read from the spec. The measurements are in Appendix A; the known spec
defects the design works around are in Appendix B; the spec and capability-map figures the
design's counts rest on are in Appendix C. Appendix D states the two preconditions any live
context probe must satisfy to mean anything. Appendix E is the revision history.

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
  Topology Group, and every member array of a fleet or group.
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

Everything below depends on this. `context_names` addresses **four distinct things**:

1. **A single array** in the fleet -- switch this call's target to that array.
2. **A Fleet** -- address the fleet-level object itself. A Workload Preset is stored at the
   fleet level, not on any one array. This is *not* shorthand for "all arrays in the fleet."
3. **A Topology Group** -- address the group object itself.
4. **Every member array of a fleet or group** -- a separate mechanism expressed by an
   **undocumented `.arrays` suffix** (`<fleet-name>.arrays`, `<topology-group-name>.arrays`).
   This is the only way to run a read against every array in a fleet or group. Membership is
   resolved **server-side** and is **transitive**: `<group>.arrays` covers arrays reached
   through nested sub-groups, not just direct members.

The `.arrays` form is orthogonal to the target kind: you do not infer "address all members"
from "the name is a fleet." You must ask for it. The design therefore models a context as
**a kind plus a separate form**, rather than deriving the form from the kind.

> **Terminology.** Three things could be called "fan-out" and this document keeps them apart.
> **`.arrays`** is one specific context form: a single request the server expands across a
> resolved membership, read-only. **Server-side fan-out** is the general capability of an
> endpoint to execute against more than one context in one request -- the subject of section 8,
> and always qualified as "server-side" where the distinction matters. **Client-side fan-out**
> is an N-request serial loop that could carry mutations; the module does not have one, it is
> a stated non-goal, and the unqualified term is reserved for it. No user-facing parameter is
> named `-FanOut`; the switch for `.arrays` is `-AllArrays`.

> **Spec gap:** the OpenAPI `context_names` description never mentions `.arrays` in any
> version from 2.17 through 2.28. It says only "an array in the fleet, or the fleet itself."
> The module's `.arrays` support rests entirely on live testing plus the Fusion
> administration guide, not on the API contract. Recorded in Appendix B.

### Array-scoped versus fleet-scoped endpoints

Each resource type accepts only the context kind it is scoped to. For **reads** (measured --
Appendix A):

| `context_names` value | array-scoped (`/file-systems`, `/arrays`) | fleet-scoped (`/presets/workload`, `/topology-groups`) |
|---|---|---|
| *(not specified)* | local array | the local array's view of the fleet object -- but see below, list-only |
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

#### Fleet-scoped mutations have no usable default

Mutations differ from the table above in its first row, and the difference is the one that
matters: **on a fleet-scoped endpoint, omitting `context_names` does not resolve to a local
view -- it fails.** On `/presets/workload` (measured -- Appendix A):

| Call | Context | Result |
|---|---|---|
| `POST` | *(none)* | `code 13 "Creating a preset in the array context is not supported."` |
| `PUT`, `DELETE` | *(none)* | `code 6 "Preset does not exist."` |
| `POST`/`PUT`/`DELETE` | bare **fleet** name | **works** |
| `POST` | bare **member array** name | `code 13 "Invalid context."` |
| `GET`, unfiltered | *(none)* | works -- returns the replicated copy |
| `GET ?names=...` | *(none)* | `code 6 "Preset does not exist."` |
| `GET ?names=...` | bare **fleet** name | works |

Two things follow.

**The local view is list-only.** An unfiltered read with no context returns the object, yet
the same object is not addressable *by name* without fleet context. So "the local array's
view of the fleet object" is weaker than it reads: sufficient to enumerate, insufficient to
resolve a name against. Any cmdlet that targets by `names=` is in the mutation case, not the
read case, regardless of its verb.

**This is not a future concern -- it describes shipped code.** No cmdlet in
`Public/Presets/` has ever sent `context_names`, so five of the six preset operations are
non-functional today: every write, plus every name-scoped read. Only the unfiltered `Get`
works. This is tracked separately from the design; the point here is that context injection
is not an enhancement for these endpoints but the thing that makes them work at all, which
is a reason to keep them in Phase 1 rather than deferring them.

The design consequence is that a fleet-scoped endpoint cannot be left to the no-context
default the way an array-scoped one can. See Open Question 7.

### The local-context short-circuit

Middleware resolves `context_names` before scope validation: if the context matches the
**local** array, the call executes locally and no context validation happens at all. So
`GET /presets/workload?context_names=<local array>` returns 200 on a fleet-scoped endpoint
that rejects every other array name with `code 13`.

**The short-circuit does not extend to mutations.** `POST`/`PUT`/`DELETE /presets/workload`
fail with local or absent context (see "Fleet-scoped mutations have no usable default"), so
the forgiving behavior a `GET` observes is read-only.

The module deliberately does not copy this behavior -- see "Local context is still a
context." The short-circuit also constrains how any of this can be verified, because a
self-context probe passes for the wrong reason; that consequence is Appendix D.

---

## Design

### 1. The single choke point

Every request funnels through `Invoke-PfbApiRequest`. That is the one place context is
resolved and injected, so no public cmdlet changes and the "zero change across ~520
signatures" property holds.

**With exceptions, which this design depends on being closed.** Five public cmdlets call
`Invoke-RestMethod` directly. Three are connection lifecycle -- `Connect-PfbArray`,
`Disconnect-PfbArray`, `Get-PfbApiVersion` -- and are legitimately outside the choke point,
since they run before or around the connection the shared path requires; none of them takes a
context. The other two are ordinary write cmdlets that simply bypass it:

| Cmdlet | Status |
|---|---|
| `Set-PfbPresetWorkload` | **Closed.** Folded onto the shared path (issue #76); `Invoke-PfbApiRequest` gained `PUT` to make that possible. |
| `Set-PfbWorkloadTag` | **Closed pending merge.** Folded onto the shared path (issue #77, PR #81); `Invoke-PfbApiRequest` and `Assert-PfbApiCapability` gained array request bodies to make that possible. |

This matters more than a tidiness note. A cmdlet that bypasses `Invoke-PfbApiRequest` gets no
context injection, and does so *silently* -- the injection path cannot warn about a caller it
never sees. `Set-PfbPresetWorkload` showed what that costs: a fleet-scoped write that could
not work, with nothing in the module able to say why. `/workloads/tags/batch` is
**array-scoped**, so it does not repeat that specific failure -- but it declares
`context_names` at 2.23 and so still needs injection to be reachable at all beyond the local
array. Both closures are prerequisites for this design holding as written rather than
parallel cleanups: until they land, "every request" has a counterexample.

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

Each **entry** carries its own kind and form:

| Entry field | Meaning |
|---|---|
| `Name` | the context name |
| `Kind` | `Array` (default) \| `Fleet` \| `TopologyGroup` |
| `Form` | `Object` (default) \| `AllArrays` -- how the name is rendered on the wire |

**Why kind is per-entry rather than one scalar for the whole context.** Mixed-kind context
lists are on the near roadmap: with Fleet Users and Fleet Audits, `context_names` will accept
`ArrayA,ArrayB,myFleet` in a single `GET`, and the Fleet-audits design already documents
exactly that shape. A single `Kind` covering all names cannot express it. The field costs
nothing now and is a breaking change to add later, so the object reserves the shape in
Phase 1 even though Phase 1 only ever populates entries of one kind. Same reasoning as
reserving `AllowErrors` in Phase 1 while surfacing it in Phase 2.

**Why `Form` is an enum and not a boolean.** A boolean can express exactly one alternative
to the default, and the suffix vocabulary is already known to be open: `.arrays` is the only
form the server accepts today, but an all-sub-groups equivalent, realm-as-context, and
whatever else the suffix grammar grows would each need their own flag. Two booleans on one
entry can also encode a meaningless state (both set), which an enum makes unrepresentable.
The cost of the enum now is a type declaration; the cost of retrofitting it is a breaking
change to a published parameter, since a `-AllArrays` switch and a `-Form` parameter cannot
coexist cleanly. Same reasoning as making `Kind` per-entry.

Wire composition from an entry:

| `Kind` | `Form` | Wire value |
|---|---|---|
| `Array` | `Object` | bare array name |
| `Fleet` / `TopologyGroup` | `Object` | bare fleet/group name -- addresses the object itself |
| `Fleet` / `TopologyGroup` | `AllArrays` | `<name>.arrays` |
| `Array` | `AllArrays` | **invalid** -- rejected client-side; an array has no members |

Reserved by implication, not implemented: `Realm` as a future kind, and further `Form`
members as the suffix grammar grows.

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
context."

#### Why "always send, let the array error" was rejected

The strategy assumes that sending a parameter an endpoint cannot honor produces an error to
surface. In the case that matters, it does not:

- **Endpoint that never supported `context_names`** (`/alert-watchers`): the array **silently
  accepts** the parameter -- HTTP 200, real create/update mutations applied, zero mention of
  `context_names`. There is no error to surface. This is the majority behavior across the GET
  endpoints that never recorded `context_names`, and it includes the fleet-management surface
  itself (`/fleets`, `/fleets/members`); the audited proportion is in Appendix A.
- **Parameter recorded but introduced later than the requested version** (`GET /admins` via
  `/api/2.10/`, `GET /dns` via `/api/2.22/`): cleanly rejected, HTTP 400, `code 24`. This case
  `Assert-PfbApiCapability` already catches locally today.

More broadly, the array performs **no query-parameter validation at all** on reads. An
entirely invented parameter returns 200, and `allow_errors=not_a_boolean` returns 200 even on
an endpoint that genuinely declares `allow_errors`. **Accepting a parameter is therefore not
evidence that an endpoint supports it**, which is why every capability decision below is made
client-side from the map rather than by probing the wire.

The converse holds too: an endpoint can process `context_names` without any scanned spec
version recording it. `GET /snmp-managers/test` does exactly that; section 8 states what the
rule does with it, and Appendix B tracks it as a map gap.

### 5. Implementation ordering (three non-obvious requirements)

1. **Inject before the existing `Assert-PfbApiCapability` call**
   (`Invoke-PfbApiRequest.ps1` line 41), not "immediately before the request is built"
   (which is near URL construction, around lines 77-80 -- after Assert has already run). If
   `context_names` lands in `$QueryParams` after Assert executes, Assert never sees it and the
   version check this design leans on never fires. This ordering is also what makes the real
   code path match the behavior the version gate has been verified against -- see Appendix D.
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
   > Tracked as **issue #74**. Do this as the first commit of the implementation PR, not as a
   > separate piece of work: only the resolution step belongs in `Private/`, while
   > `Get-PfbContextParameterFact`'s record-shaping and HTTP 207 merging stay in `tools/`, so
   > landing it separately means touching the same functions twice. `tools/` may depend on
   > `Private/`; the reverse is what this fixes.

### 6. `Set-PfbContext` / `Clear-PfbContext`

```powershell
Set-PfbContext
    [-Array] <PSCustomObject>   # ordinary param; defaults to the current default connection
    [-Context] <string[]>       # binds by property name (see Ergonomics)
    [-Kind <ContextKind>]       # Array (default) | Fleet | TopologyGroup
    [-AllArrays]                # switch -> sets Form = AllArrays (.arrays suffix)
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
- **`-AllArrays` is a switch over an enum field.** The switch is the ergonomic surface;
  `Form` on the entry is the stored representation. A future form adds a sibling switch (or a
  parameter set) without changing what is persisted -- see section 3.
- **`-AllArrays` resolves membership before it returns.** The name must denote a real fleet or
  topology group, so the cmdlet verifies it rather than deferring to the wire. This is the one
  place the context cmdlets make a network call, and it is a deliberate exception to
  "no hidden network calls" -- justified below.

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

This is **Phase 1**. It is the documented escape hatch from the Phase 1 hard throw, so
shipping the throw without it would ship a gate with no key.

### 8. Cardinality: which endpoints actually accept multiple contexts

The plural parameter is two spec components that both surface as `context_names`:

- **`Context_names_get`** -- documented multi-target server-side fan-out, comma-separated.
- **`Context_names`** -- "the context names must be an **array of size 1**." The restriction
  lives only in free-text description, with no structured `maxItems`.

#### The verb does not determine cardinality

The split is not clean by verb -- `GET` multi-value, mutations size-1 -- however plausible
that reads. Four fleet-scoped `GET`s reject a two-name context outright:

- `GET /presets/workload`
- `GET /topology-groups`
- `GET /topology-groups/members`
- `GET /topology-groups/arrays`

Each returns `400 code 15 "Multiple location contexts are not allowed."` on a context of two
valid fleet-member names, where `/file-systems`, `/admins` and `/arrays` reach
`400 code 20 "Operation not permitted."` on the same input. `code 15` fires *before* the
cross-array authorization gate that produces `code 20`, so it is a structural property of the
endpoint, not a permission artifact. It is also independent of name validity:
`FB-A,no-such-array` yields `code 15` on these four but `code 42 "Cannot find array in fleet"`
on `/file-systems`. (Measured -- Appendix A.)

These four are fleet-scoped endpoints. A fleet-scoped endpoint has exactly one meaningful
context -- the fleet -- so multi-value is not merely restricted there, it is meaningless.
Their spec entries reference `Context_names_get` in error.

Cardinality is therefore data-driven from the capability map rather than inferred from the
verb.

#### The rule the module implements

> **An endpoint is multi-context-capable if and only if its `context_names` parameter
> resolves to component `Context_names_get` AND the endpoint also declares `allow_errors`.**

Both facts are already recorded per endpoint in `Data/PfbCapabilityMap.json`, so this is a map
lookup -- no new derivation and no new tooling. Against the committed map the rule admits all
but a handful of the endpoints referencing the multi-value component; the exact populations,
at each scanned version, are in Appendix C.

Why `allow_errors` rather than the component name alone: the component reference is wrong for
the fleet-scoped GETs above, plus one `DELETE` since corrected upstream (counted per version in
Appendix C), while `allow_errors` is correct on every case for which evidence exists. A
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

A real argument for the two-signal rule over the component alone. Component identity is not
stable across versions: four endpoints have flipped from `Context_names_get` to
`Context_names` (named, with the versions, in Appendix C). **None changes the rule's
verdict**, because all four declare no `allow_errors` at any version, so the conjunct absorbs
the instability.

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

| Signal | Reliability as a cardinality signal |
|---|---|
| References `Context_names_get` | Wrong for the fleet-scoped GETs, plus one `DELETE` that is fixed at 2.28 |
| Declares `allow_errors` | Correct on every case with evidence |
| Declares an HTTP `207` response | Correct, but stricter -- excludes endpoints of unknown status |
| Carries an `errors` envelope field | **Unreliable** -- applied by authoring convention |
| Satisfies the ratified rule | -- |

Populations are version-specific and moving, and are tabulated at both scanned versions in
Appendix C. The reliability judgements above are unchanged between them; only the populations
differ.

The `errors` envelope arrives via an `allOf`-composed `_errorContextResponse` component and is
present on 15 endpoints that declare no `207`, including all four fleet-scoped GETs. It says
nothing about fan-out capability and must not be used as a signal.

`207` is the strictest signal and the one upstream tooling uses, but gating on it would treat
endpoints of unknown status as size-1 on no evidence, blocking calls that may well work --
contrary to the module's founding capability-check principle. That set is shrinking as `207`
coverage grows (Appendix C names it at both scanned versions); the argument does not depend on
the size of the set, only on its being non-empty. `207` is also **not available at runtime**:
the capability map records the request surface only, with no response data at all. It
therefore serves as a corroborating signal for the maintainer drift check, sourced from the
specs under `tools/`, and never as a runtime gate.

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

**Every `context_names` call targeting anything other than the connected array's own local
context** -- a single-value switch, an explicit multi-array list, or an `.arrays` context --
fails with `code 20 "Operation not permitted."` when connected as the local `pureuser`, and
succeeds for an LDAP-authenticated admin. There is no single-vs-multi distinction; a bare
single-array switch fails exactly like a multi-context call does. (Measured -- Appendix A.)

This is **not** a "`pureuser` vs everyone" distinction:

- Since 4.5.0, admins can create additional named **local** users with the same privileges;
  the 4.8.1 **service-account** admin type is also local.
- All three -- `pureuser`, custom local users, service accounts -- have
  `authorization_model: static`.
- Only **LDAP/SAML remote-user admins** get `authorization_model: dynamic`.

`GET /admins` reports the model per admin, which is what makes the check implementable. The
vendor documentation states the same rule independently: "Only AD/LDAP authenticated users are
allowed to execute fleet commands or do remote provisioning... Non-LDAP users (`pureuser`,
`puresupport`, etc.) are disallowed to issue cross-array requests."

**Recommendation: check client-side** at `Connect-PfbArray` / `Set-PfbContext` and throw
immediately when a static-model admin sets or uses any cross-array context:

> "targeting a context other than the local array requires a dynamic-authorization-model
> (LDAP/SAML) admin; static-model admins, including `pureuser` and other local accounts, are
> not permitted."

A user hitting the raw "Operation not permitted" has no obvious reason to suspect their *auth
method* rather than their fleet setup.

#### `code 20` masks every other finding

The client-side check earns its keep for diagnosis as much as for ergonomics. Connected as a
static-model admin, **every** call to a fleet-scoped endpoint returns `code 20`, read and
write alike, whatever the context value. That is indistinguishable from the endpoint being
unsupported on the platform: a static-model session cannot tell "not permitted for you" from
"not implemented here." Converting the condition into an explicit statement about the admin's
authorization model, before the call, is the difference between a diagnosable failure and a
dead end. The testing precondition that follows from the same fact is in Appendix D.

### 12. Context scope is metadata, and the module has to supply it

Two earlier sections depend on the module knowing whether an endpoint is fleet-scoped or
array-scoped. "Array-scoped versus fleet-scoped endpoints" has it validating kind-vs-scope
**client-side** and producing one uniform error; "Fleet-scoped mutations have no usable
default" needs the same fact before it can say anything useful about a missing context. This
section is where that fact comes from.

#### The spec declares scope -- in vendor extensions, from 2.28

The obvious places are empty. Operation `tags` are resource groupings (`Presets`,
`File Systems`), and fleet-scoped and array-scoped endpoints are indistinguishable under
them. Cardinality is not a proxy either: a fleet-scoped endpoint is necessarily size-1, but
so is every array-scoped mutation, so size-1 is implied by fleet scope and does not imply it
back.

The signal is in three `x-pure-*` vendor extensions, all of which arrive or expand
substantially at **fb2.28**:

| Extension | Meaning |
|---|---|
| `x-pure-remote-execution-context-domains-override` | The context domains this operation accepts, overriding the default |
| `x-pure-block-remote-execution` | Remote execution not supported here at all |
| `x-pure-incomplete-gre` | Global Remote Execution annotation is **known incomplete** on this operation |

Per-version occurrence counts for all three are in Appendix C. The override carries exactly
the fact this section needs, and it agrees with live testing without qualification:

```
GET    /presets/workload   ->  ARRAY|FLEET
PUT    /presets/workload   ->  FLEET
POST   /presets/workload   ->  FLEET
DELETE /presets/workload   ->  FLEET
PATCH  /presets/workload   ->  FLEET
```

Read that against the mutation table in "Fleet-scoped mutations have no usable default":
reads are legal in either domain, writes are fleet-only -- precisely what the wire does. The
declaration and the measurement are independent derivations of the same fact, and their
agreeing is the strongest evidence in this document for either. (Appendix A.)

#### But it covers five endpoints, so curation does not go away

Those five are the only operations in the API carrying the override. Topology groups --
fleet-scoped on the same live evidence -- carry no override at all.

`x-pure-incomplete-gre` explains why, and is the more useful of the three extensions. It
marks 28 operations whose remote-execution annotation upstream considers unfinished, and it
contains **every endpoint this design has had to establish by live testing**: all four
fleet-scoped GETs from section 8, all five preset operations, `GET /realms`, and
`GET /workloads/tags`. It is upstream's own machine-readable statement of the defect
Appendix B tracks as "open, in review."

So the three extensions are not three independent signals. They are a partially-completed
annotation pass plus a flag marking where it is incomplete. Treat them accordingly:

| Endpoint state | Scope source |
|---|---|
| Has an override | **Trust it.** Declared, and live-verified where we could check |
| No override, not flagged incomplete | Default `array` |
| Flagged `x-pure-incomplete-gre` | **Do not trust the absence of an override.** Curated value if we have live evidence, `unknown` otherwise |

That reduces curation to the third row: topology groups (8 endpoints, fleet, live-tested)
and `GET /realms` plus `/realms/defaults` (unknown, untested). Down from thirteen
hand-maintained entries to eight, each now justified against a declared upstream flag rather
than resting on our testing alone -- and the list has an exit condition, since entries retire
as the override is filled in.

#### Representation

A `contextScope` field per endpoint in the capability map, alongside the existing
`parameterComponentOverrides`, populated by the generator: from the override where present,
from the curated table where the endpoint is flagged incomplete, and `array` otherwise. Each
entry records provenance -- `declared`, `live-tested`, or `unknown` -- so the curated set is
visibly temporary.

**Default `array`**, which is the fail-safe direction: mis-marking a fleet-scoped endpoint as
array-scoped costs the caller the extra guidance and leaves today's behavior, while the
reverse would throw on a call that would have worked. That matches the fail-open principle
section 8 already argues for.

Scope is not version-gated even though the extensions only exist at 2.28. A resource does not
migrate between the fleet database and an array, so last-seen-wins is correct here in a way it
is not for component identity (section 8). The 2.28 annotations describe 2.23-era endpoints
accurately.

#### Encoding it in the shipped map

The signal being in the spec does not put it in the module -- `tools/Build-PfbCapabilityMap.ps1`
reads none of the `x-pure-*` extensions today, and `Data/PfbCapabilityMap.json` is
`schemaVersion 1` with no field to hold this. Concretely required:

1. **Generator reads the three extensions.** The map is already built across 2.0-2.28 with
   last-seen-wins, so a value present only in the 2.28 document lands correctly with no
   change to the version-merging logic.
2. **`contextScope` becomes an additive per-endpoint field**, alongside `minVersion`,
   `parameters`, `bodyProperties` and `parameterComponentOverrides`. Additive, so existing
   readers are unaffected -- but **bump `schemaVersion` to 2** rather than growing the shape
   silently, since `Get-PfbCapabilityMap` is the single gate through which every consumer
   sees it.
3. **The curated table lives in the generator**, not in `Private/`. Runtime code must read
   scope from the shipped map and nowhere else; a curated list consulted at runtime would be
   a second source of truth for the same fact, which is the failure mode section 8 exists to
   avoid. The map is the interface; curation is a build-time input to it.
4. **A drift test asserts the five declared overrides still match** what the generator emits,
   and flags any curated entry whose endpoint has since gained an override -- so the curated
   set shrinks on its own as upstream finishes the annotation pass, instead of quietly
   shadowing better data.

This rides the existing capability-map workflow (`.github/workflows/update-api-capability-map.yml`),
so there is no new pipeline -- one generator change, one schema bump, one test.

Note the ordering consequence: the map has to carry `contextScope` before any of the guidance
in this section can be written, which puts the generator work at the front of Phase 1 rather
than alongside it.

#### Consequences for section 8

Two, both flagged for decision rather than settled here:

- **`x-pure-incomplete-gre` belongs in the drift check.** Section 8 ratifies
  `Context_names_get` AND `allow_errors` as the cardinality rule and notes that two-signal
  comparison "cannot see both sides being wrong in the same direction." This flag is upstream
  telling us exactly where that risk lives, and all four endpoints the verb rule got wrong
  carry it. It is a strong candidate for a third signal in the maintainer report -- not as a
  cardinality predicate, which it is not, but as a "prefer live evidence here" marker.
- **`x-pure-block-remote-execution` contradicts `context_names` on 11 endpoints** that declare
  both. All 11 are inside the 28 flagged incomplete, which is self-consistent -- the flag says
  the annotation is unfinished -- but it means `block` cannot be used as a runtime signal
  without excluding the flagged set first. Recorded in Appendix B.

#### What it buys, and why it answers two open questions

One field, three consumers:

**1. Validation** -- the kind-vs-scope check becomes a map lookup instead of a hardcoded list,
so it is declared in one place and checked by the maintainer drift report, exactly as the
cardinality rule is.

**2. Errors that say what to do.** This is the point. The failures a user actually hits are
`code 13 "Invalid context."`, `code 6 "Preset does not exist."`, and `code 42 "Cannot specify
context that is a fleet."` None names the cause and none suggests a fix; `code 6` actively
misleads, since the preset does exist. With scope in hand the module can say so before the
call, or annotate it after:

> `Set-PfbPresetWorkload` targets a fleet-scoped resource, which requires a fleet context.
> The current context is the local array. Set one with
> `Set-PfbContext -Fleet <name>`, or run this call in a fleet context with
> `Invoke-PfbInContext -Fleet <name> { ... }`.
> Get the fleet name from `Get-PfbFleet`.

and, for the inverse:

> `Get-PfbFileSystem` targets an array-scoped resource; a fleet name is not a valid context
> for it. Use a member array name, or `<fleet>.arrays` to target every array in the fleet.

**3. Discoverability before the error.** Every affected cmdlet's comment-based help gains a
`.NOTES` line stating the context requirement, generated from the same field so it cannot
drift from the validation. A user reading `Get-Help New-PfbPresetWorkload` learns the
requirement without hitting `code 13` first.

This subsumes two open questions rather than sitting beside them. **Open Question 3**
(annotating fleet-membership failures with the context name) is consumer 2's after-the-call
half. **Open Question 7** (what a fleet-scoped endpoint should do with no context) becomes
answerable: of its three options, "throw client-side" is only attractive if the throw can be
*specific*, and scope metadata is what makes it specific. Without this field the best
available message is a generic "this might need a fleet context"; with it, the message names
the resource, the requirement, and the cmdlet that fixes it.

It does not settle the third option, defaulting to the fleet. Scope tells the module a fleet
context is required; it does not supply the fleet's name, which still costs a call to
discover. Recommendation is to throw with guidance in the first pass and revisit
default-to-fleet once `Get-PfbFleet` is on the connection path.

#### Drift

The exposure is a new fleet-scoped resource appearing in a later REST version and being
silently treated as array-scoped. That is the benign direction -- it degrades to current
behavior -- but it should still be visible. The maintainer drift report already compares
rule against spec for cardinality; it should also flag any endpoint that newly declares
`context_names` under a resource family the curated list marks fleet-scoped, so a new verb
on `/presets/workload` or a new topology-group sub-resource surfaces for classification
rather than defaulting quietly. Cross-version scope changes are not a concern in the way
component identity is: a resource does not migrate between the fleet database and an array.

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

## Ergonomics: piping into context

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
far more valuable `Get-PfbFleetMember | Set-PfbContext`.

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

### Whole-fleet and whole-group scope: `-AllArrays`

The member-by-member pipeline above enumerates names client-side. `-AllArrays` instead emits
the single `.arrays` context and lets the server resolve membership:

```powershell
$fb = Get-PfbFleet         | Set-PfbContext -AllArrays   # -> cc-test-fleet.arrays
$fb = Get-PfbTopologyGroup | Set-PfbContext -AllArrays   # -> region-1.arrays
```

Both source cmdlets bind by property name on `Name`, the same mechanism piece (b) above
establishes for `MemberName`.

**Why this is not just sugar for piping members.** For topology groups the two are not
equivalent, and the member pipeline is the wrong answer:

- **A group's members may themselves be groups.** `GET /topology-groups/members` returns
  direct members, which can be sub-groups rather than arrays. Piping them into a context
  yields group names where array names are required. `.arrays` is transitive over the whole
  sub-tree; enumerating members is not.
- **Membership drifts.** A client-side name list is a snapshot taken when the pipeline ran.
  `.arrays` is re-resolved by the server on every request, so a durable context stays correct
  as arrays join or leave.
- **One request, not N.** Enumerating costs a round trip per level of nesting before the real
  call is made.

So `Get-PfbTopologyGroupMember | Set-PfbContext` remains available and is correct for
"scope to these specific members," but it is **not** the way to express "the whole group."

**Membership is validated before the context is stored.** `-AllArrays` resolves the name
against the array rather than trusting it:

| `Kind` | Validation call | Available from |
|---|---|---|
| `TopologyGroup` | `GET /topology-groups/arrays?topology_group_names=<name>` | 2.26 |
| `Fleet` | `GET /fleets?names=<name>` | 2.17 |

The asymmetry is unavoidable -- there is no `/fleets/arrays` -- and it is why validation
belongs in the context layer rather than being pushed onto either cmdlet.

This is a deliberate exception to the design's preference against hidden network calls, and
it is narrower than the inference this document rejects elsewhere. The rejected form was
*inferring `Kind`* from topology on every context set, silently and unbidden. This is
*confirming a name the caller explicitly supplied*, only when `-AllArrays` is passed, once,
at the moment a durable context is established. The failure it prevents is the expensive one:
a mistyped group name is accepted, stored, and then silently narrows or misdirects every
subsequent call in the session, with `code 13` arriving far from its cause.

For topology groups the validation call has a probing quirk that also applies here --
`/topology-groups/arrays` returns `code 24` unless `topology_group_names` or
`topology_group_ids` is supplied. The call above always supplies it, so the shipped path does
not hit it; Appendix D records it because a bare probe does.

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
  fixture, since they are the case a verb-shaped rule gets wrong.
- **Local context is not special-cased** -- a context naming the local array still throws on an
  endpoint that does not support `context_names`.
- **`allow_errors`** -- injected only when the endpoint declares it; defaulted `$true` only when
  a multi-value or fan-out context is sent; never sent otherwise.
- **HTTP 207** -- recognized as a distinct outcome; one non-terminating `Write-Error` per
  `errors` entry, keyed by `location_context`; successful `items` still flow down the pipeline.
- **Kind-vs-scope validation** -- a bare fleet or group name rejected client-side on
  array-scoped endpoints and vice versa, with one uniform error.
- **`-AllArrays` composition and validation** -- that `Form = AllArrays` renders `<name>.arrays`
  and not the bare name; that `Kind = Array` with `-AllArrays` is rejected client-side; that an
  unresolvable group or fleet name throws at `Set-PfbContext` rather than being stored; and that
  a nested sub-group's arrays are reached, which is the property distinguishing `.arrays` from
  the member pipeline and the one a flat single-level fixture cannot detect.
- **`authorization_model` gate** -- a static-model admin setting or using any cross-array
  context throws client-side.
- **Fleet-scoped mutation with no context** -- whatever Open Question 7 resolves to, the
  behavior is asserted rather than left to the endpoint. A `New-`/`Set-`/`Remove-PfbPresetWorkload`
  call with no context must not reach the wire only to come back `code 13`.
- **Name-scoped read on a fleet-scoped endpoint** -- `?names=` with no context must behave
  like a mutation, not like an unfiltered list. This is the case a verb-shaped test misses.

Live verification must use a **remote** fleet member, and must run as a **dynamic**-model
admin. A self-context test passes for the wrong reason; a static-model session fails every
probe with `code 20` for the wrong reason. Both produce confident, wrong conclusions.
**Appendix D** states both preconditions and the probing caveats that go with them.

---

## Phasing

- **Phase 1**: `-Context` on `Connect-PfbArray`; the `PfbContext` object (per-entry
  `Kind`/`Form`, reserved `AllowErrors`) plus `.DefaultContext` / `.ContextOverride` on the
  connection; central capability-gated hard-throw injection with the ordering fixes;
  `Set-PfbContext` / `Clear-PfbContext`; `Invoke-PfbInContext`; kind and form with
  client-side kind-vs-scope validation; the data-driven cardinality rule and its throw; the
  `contextScope` map field and the scope-aware guidance messages built on it (section 12) --
  Phase 1 because kind-vs-scope validation cannot be implemented without it; the
  `authorization_model` precondition; the connect-time staleness warning; `Get-PfbFleetMember`
  top-level `MemberName`/`FleetName` and the `Set-PfbContext` pipeline binding; `-AllArrays`
  and the membership-resolution path it depends on.
- **Phase 2**: `allow_errors` end-to-end -- surfacing, default rules, and the response-layer
  work (HTTP 207 recognition plus the `errors` branch with per-array non-terminating errors).
- **Phase 3**: `context_ids`; an explicit multi-value mutating fan-out helper if wanted;
  display of the active context in `Get-PfbArrayConnection`; `Realm` as a context kind when
  the API ships it.

### Ownership boundary with the topology-group cmdlets

Topology-group **object management** -- `GET`/`POST`/`PATCH`/`DELETE /topology-groups` and the
`/members` writes -- belongs to issue #38, not to this design. That split holds: those cmdlets
inherit context injection at runtime like every other cmdlet and are not otherwise coupled to
it. All seven topology-group endpoints declare `context_names` and none declares
`allow_errors`, so they are uniformly single-context under section 8's rule and need no
special handling here.

Two things cross the boundary and are owned by **this** design instead:

1. **Membership resolution** -- the `GET /topology-groups/arrays` and `GET /fleets` calls
   backing `-AllArrays`. These are context plumbing, not object management, and live in
   `Private/` beside the rest of the injection path.
2. **A binding contract on #38.** `Get-PfbTopologyGroup` must emit a top-level `Name` property
   that binds to `Set-PfbContext` by property name. This costs #38 nothing -- it is the
   existing pipeline mechanism -- but stated as a requirement it cannot be missed, and without
   it the documented `Get-PfbTopologyGroup | Set-PfbContext -AllArrays` form silently no-ops in
   exactly the way "Ergonomics" describes for `Get-PfbFleetMember`.

`Get-PfbTopologyGroupMember` is likewise #38's, and is no longer listed as a phase item here:
this design's dependency is on `-AllArrays`, not on enumerating members.

---

## Open questions

1. **"Explicit `-QueryParams['context_names']` wins" -- over what, concretely?** Nothing in the
   shipped public surface can populate that tier: every public cmdlet builds its own fixed
   `QueryParams` and `Invoke-PfbApiRequest` is private. The tier is reachable only by
   module-internal code or a future cmdlet. Stated here so no reader assumes a path exists.
   Keep as defensive layering, or drop it?
2. **Object-model surfacing of `Kind` / `Form`.** *Settled.* Explicit `-Kind` (default
   `Array`) plus an `-AllArrays` switch over an enum-valued `Form` field (section 3). The
   alternative -- inferring `Kind` by querying the fleet's topology on every context set --
   stays rejected: it is unbidden, it runs on every call rather than on request, and it makes
   the stored context depend on state the caller never named. The bounded membership check
   `-AllArrays` performs is not that inference; see "Ergonomics" for why the two are
   distinguished. What remains genuinely open is only whether the membership check should be
   suppressible by a `-NoValidate`-style escape for offline or high-latency use.
3. **Context-name annotation on fleet-membership failures.** Recommendation is to annotate
   `code 42` and similar with the active context name(s). Confirm, or accept as a known rough
   edge. **Section 12 proposes the mechanism**: with `contextScope` in the map the annotation
   can name the required context *kind* and the cmdlet that sets it, not just echo the context
   that failed. What remains open is scope of effort, not feasibility.
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
7. **What should a fleet-scoped endpoint do with no context set?** Array-scoped endpoints have
   a sensible no-context default -- the local array. Fleet-scoped ones do not: on a mutation or
   a name-scoped read the call is guaranteed to fail (`code 13` / `code 6`). Three options, and
   this doc does not pick one:
   - **Send nothing, let it fail.** Honest and simple, but every preset cmdlet stays broken
     out of the box and the error names neither the cause nor the fix.
   - **Throw client-side**, naming the fleet requirement. Consistent with the
     `authorization_model` gate and the kind-vs-scope validation, both of which already
     convert an obscure server code into an actionable message.
   - **Default to the fleet** when the endpoint is fleet-scoped and no context is set. Most
     ergonomic and matches the only value the endpoint accepts, but it means synthesizing a
     context the caller never asked for -- and discovering the fleet name costs a call.

   The third conflicts with the goal "never let a context request be silently dropped" only in
   spirit, not in letter, since nothing is being dropped. Worth deciding explicitly rather than
   by default.

   **Section 12 supplies the missing input** -- a `contextScope` field, without which none of
   the three options can be implemented, since the module cannot currently tell a fleet-scoped
   endpoint from an array-scoped one. With it, the recommendation is the second option: throw
   client-side with a message naming the requirement and the cmdlet that satisfies it.
   Default-to-fleet stays open, blocked on discovering the fleet name without an extra call.

---

## Alternatives considered and rejected

- **Silent skip-injection when the endpoint does not support `context_names`.** For a mutating
  call it produces a *successful* request that silently landed on the local array -- worse than
  an error.
- **"Always send `context_names`, let the array's error surface."** 90 of 113 never-supported
  GET endpoints silently accept and ignore it, and the array performs no query-parameter
  validation at all on reads. There is no error to surface.
- **Softening reads (`GET`) to `Write-Warning`.** Warnings are routinely suppressed in the
  automation most likely to set a read-scoped context.
- **The verb as the cardinality rule.** Falsified by live testing: four fleet-scoped `GET`s
  reject multi-value context with `code 15`.
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
member, 2026-08-01.** A two-name context, both names valid fleet members:

```
GET /presets/workload?context_names=FB-A,FB-C          -> 400 code 15 "Multiple location contexts are not allowed."
GET /topology-groups?context_names=FB-A,FB-C           -> 400 code 15
GET /topology-groups/members?context_names=FB-A,FB-C   -> 400 code 15
GET /topology-groups/arrays?context_names=FB-A,FB-C    -> 400 code 15
GET /file-systems?context_names=FB-A,FB-C              -> 400 code 20 "Operation not permitted."   (control)
GET /admins, GET /arrays  (same query)                 -> 400 code 20                              (controls)
```

All four fleet-scoped GETs reject any two-name context with `code 15`, while `/file-systems`,
`/admins`, and `/arrays` reach `code 20` on the same input -- `code 15` precedes the
authorization gate. Also measured on the same array:

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

**Probing caveat:** `GET /topology-groups/arrays` cannot be probed bare; its own parameter
validation runs before the context check. See Appendix D.

**FB-A (Purity//FB 4.8.2, REST 2.26), fleet `cc-test-fleet`, 2026-08-02** -- the first probe
of fleet-scoped **mutations**, run as a dynamic-model admin during issue #76 live testing. A
full `POST` -> `PUT` (revision 1 -> 2) -> `DELETE` round trip on `/presets/workload` succeeded
under `context_names=<fleet>`, and each verb was also probed with no context and with a member
array name:

- With **no context**, `POST` returns `code 13 "Creating a preset in the array context is not
  supported."`, and `PUT`/`DELETE` return `code 6 "Preset does not exist."` The local-context
  short-circuit that makes a `GET` succeed does not apply to mutations.
- With a **member array** name, `POST` returns `code 13 "Invalid context."` Only the bare
  fleet name is accepted, on every verb -- confirming for writes what rev 3 had established
  for reads.
- `GET` with no context is **list-only**: unfiltered returns the replicated preset, while
  `?names=<preset>` returns `code 6`. Name resolution requires fleet context even on a read.
- As the static-model `pureuser`, all of the above return `code 20` instead, with no way to
  tell them apart -- see section 11 and Appendix D.
- Preset bodies require a `storage_class` reference (`name` + `id` + `resource_type`) that
  need not resolve: FB-A reports storage classes unsupported and offers no create verb for
  them at 2.28, yet the preset is accepted, because a preset is a fleet-database template
  rather than a provisioned object.

**Spec vendor extensions, fb2.28, 2026-08-02** -- `x-pure-remote-execution-context-domains-override`
declares `ARRAY|FLEET` for `GET /presets/workload` and `FLEET` for its `PUT`/`POST`/`DELETE`/`PATCH`.
This was found *after* the live testing above and matches it exactly, on all five operations,
including the read/write asymmetry. Two independent derivations of the same fact. Per-version
occurrence counts for all three extensions are in Appendix C.

**FB-A (REST 2.26), fleet `cc-test-fleet`, 2026-08-02 -- `.arrays` through both interfaces.**
Run as a dynamic-model LDAP admin, comparing the CLI against the REST path for the same
context value:

| Call | CLI | REST |
|---|---|---|
| `pureworkload --context cc-test-fleet.arrays` | exit 0 | 200 |
| `pureworkload --context cc-test-fleet` | error | `code 42` "Cannot specify context that is a fleet" |
| `pureworkload --context FB-B` | exit 0 | 200 |
| `purepreset workload list --context cc-test-fleet` | exit 0 | 200 |
| `purepreset workload list --context cc-test-fleet.arrays` | Invalid context | `code 13` |
| `purepreset workload list --context FB-B` | Invalid context | `code 13` |
| `puretgroup` / `GET /topology-groups --context <fleet>` | n/a | 200 |

Three conclusions the design rests on:

- **CLI and REST agree in every case**, so there is no interface-specific behavior to model.
- **`.arrays` is real and shipped**, on array-scoped resources only. It is documented in the
  CLI man page -- including that it is transitive over nested sub-groups -- and in no OpenAPI
  version.
- **The two context kinds are strictly disjoint.** Fleet-scoped endpoints take only the bare
  fleet name; array-scoped endpoints take only array names and `.arrays`. Same parameter,
  mutually exclusive vocabularies, and nothing in the parameter definition distinguishes them
  -- which is what section 12's `contextScope` exists to supply.

The `/workloads` family is the counter-example that fixes the polarity: it is **array-scoped**,
the exact inverse of `/presets/workload`, despite both being Fusion-era additions. Scope does
not follow from a resource being fleet-era.

**FB-A and a second simulator (Purity//FB 4.6.5 / REST 2.22)** -- silent acceptance of
never-supported `context_names` on `/alert-watchers` across a create/patch/delete round trip;
clean wire-400 (`code 24`) for recorded-but-too-old on `/admins` and `/dns`.

**Audit of all 113 never-recorded GET endpoints (REST <= 2.26)** -- 90 silently accept, 2
map gaps at the time of the audit (`GET /audits`, since fixed at 2.28; `GET /snmp-managers/test`,
still open), 21 inconclusive. POST/PATCH/DELETE not audited.

**Static spec analysis and capability-map figures** are tabulated separately, in Appendix C.
The spec-derived figures were independently reproduced 2026-08-01 by a second agent working
from the spec documents directly.

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
| The `context_names` description never documents the `.arrays` suffix (2.17-2.28) | **Open**, and confirmed as a documentation gap rather than an unimplemented feature: the CLI man page documents `.arrays` properly, including its transitivity over nested sub-groups, and the CLI and REST paths behave identically on every probed case (Appendix A). The module's support for the form rests on that evidence, not on the API contract. |
| `GET /audits` processed `context_names` though 2.26/2.27 did not record it | **Fixed** in 2.28: declares `Context_names_get`, `allow_errors` and `207`. Recorded in the map; no workaround needed. |
| `GET /snmp-managers/test` processes `context_names` though no scanned version records it | **Open.** A map gap within the scanned range, not staleness. The predicate falls back to the verb and returns capable on no evidence -- see section 8. |
| The `errors` envelope field is applied by authoring convention to 15 endpoints that cannot return a partial failure | **Cosmetic**, but it makes the field useless as a capability signal. |
| Both `context_names` components describe the value as "the name of an array in the same fleet **or** the name of the fleet itself". On fleet-scoped endpoints only the second branch is legal -- a member array yields `code 13` on every verb | **Open.** Same root cause as the `Context_names_get` row above: a shared component describing a parameter whose legal values are endpoint-scoped. Harmless on array-scoped endpoints; on fleet-scoped ones it documents a value that never works. The module resolves this client-side via kind-vs-scope validation rather than waiting on the contract. |
| Endpoint scope (fleet versus array) is declared on only 5 of the endpoints that need it | **Partially fixed at 2.28.** `x-pure-remote-execution-context-domains-override` declares it correctly for all five `/presets/workload` operations and agrees exactly with live testing; no other operation carries it, including the live-confirmed fleet-scoped topology-group endpoints. Not derivable from `tags` or from cardinality. The module curates the gap -- section 12 -- and retires entries as the override is filled in. |
| `x-pure-block-remote-execution` is `true` on 11 endpoints that also declare `context_names` | **Open**, and self-flagged: all 11 are inside the 28 marked `x-pure-incomplete-gre`, so upstream already records the annotation as unfinished. Consequence for us: `block` cannot be used as a runtime signal without first excluding the flagged set. The 11 are the five presets, three `arrays/ssh-certificate-authority-policies` verbs, `GET /audit-file-systems-policy-operations`, `GET /realms`, and `GET /storage-class-tiering-policies/members`. |
| `info.x-pure-description-ref` points at `../custom_descriptions/FB-api-introduction.md`, which is not in the document | **Open**, and cosmetic for our purposes. The referenced prose ships in neither the JSON nor the public Redoc rendering, so whatever it says about remote execution is unavailable from either source. `info.description` is a 108-character boilerplate line in its place. |

## Appendix C: spec and capability-map figures

Populations are version-specific and move as upstream fills in its annotations, so figures are
given for both scanned spec versions. The design's reliability judgements do not change
between them; only the populations do.

### Cardinality signals, by spec version

| Signal | fb2.27 | fb2.28 |
|---|---|---|
| References `Context_names_get` | 139 | 139 |
| Declares `allow_errors` | 135 | 136 |
| Declares an HTTP `207` response | 124 | 132 |
| Carries an `errors` envelope field | 139 | 139 |
| Satisfies the ratified cardinality rule | 134 | 135 |

At fb2.27, 236 endpoints reference the size-1 `Context_names` component.

The component reference is wrong for **5** endpoints at 2.27 and **4** at 2.28: the four
fleet-scoped GETs (section 8), plus `DELETE /management-access-policies`, which is corrected
to `Context_names` at 2.28. `GET /audits` also becomes fully consistent at 2.28. The four
fleet-scoped GETs are unchanged between the two versions.

### Endpoints of unknown `207` status

The set a `207`-based cardinality rule would exclude on no evidence, which is why `207` is not
the runtime gate (section 8). It is shrinking as `207` coverage grows, but the argument
depends only on its being non-empty.

| Version | Count | Endpoints |
|---|---|---|
| fb2.27 | 11 | `/realms`, `/file-systems/sessions`, `/file-systems/locks`, and the management-authentication-policies family |
| fb2.28 | 4 | `/realms`, `/arrays/ssh-certificate-authority-policies`, `/audit-file-systems-policy-operations`, `/log-targets/file-systems` |

### Endpoints whose component identity changed across versions

All four moved from `Context_names_get` to `Context_names`. None declares `allow_errors` at
any version, so the conjunct absorbs the change and none alters the rule's verdict
(section 8).

| Endpoint | Version of the change |
|---|---|
| `DELETE /management-access-policies` | 2.28 |
| `DELETE /nfs-export-policies/rules` | 2.22 |
| `PATCH /nfs-export-policies/rules` | 2.22 |
| `PATCH /object-store-roles/object-store-trust-policies/upload` | 2.22 |

Endpoints that flipped component *while* declaring `allow_errors`, which is the case the map's
missing version dimension could not survive: **0**.

### Capability map

`Data/PfbCapabilityMap.json`, `generatedFrom` 2.0-2.28, describing 2.28: **376** endpoints
record `context_names`, of which **136** also record `allow_errors`; **139** resolve to
`Context_names_get`, **237** to `Context_names`, and **0** to no component. **135** satisfy the
cardinality rule -- 135 of the 139 referencing the multi-value component, against 134 of 139 at
fb2.27. The map records the request surface only; it holds no response data, so HTTP 207 is not
available at runtime.

### Vendor extensions, by spec version

Occurrences of each `x-pure-*` extension (section 12):

| Extension | 2.22 | 2.24 | 2.26 | 2.27 | 2.28 |
|---|---|---|---|---|---|
| `x-pure-remote-execution-context-domains-override` | 0 | 0 | 0 | 0 | **5** |
| `x-pure-block-remote-execution` | 0 | 2 | 2 | 4 | **266** |
| `x-pure-incomplete-gre` | 0 | 0 | 0 | 0 | **28** |

The public Redoc page at `code.purestorage.com` embeds the same 2.28 document -- identical
extension counts -- and adds nothing beyond it.

## Appendix D: live-testing preconditions

Two properties of the platform make a naive context probe return a confident wrong answer, and
both have already done so. Any live verification of anything in this document has to satisfy
both preconditions before its results mean anything.

### Probe from a remote member, never the local array

The local-context short-circuit resolves a context naming the connected array before any scope
validation runs, so the call executes locally and returns 200 whatever the endpoint's real
context support is. **A self-context test therefore proves nothing** about whether an endpoint
supports a context kind. Use a *remote* fleet member.

The short-circuit is also read-only. A tester who establishes it on `GET`s and generalizes to
writes will conclude the endpoint is broken, since `POST`/`PUT`/`DELETE /presets/workload` fail
with a local or absent context.

### Probe as a dynamic-authorization-model admin

Connected as a static-model admin, **every** call to a fleet-scoped endpoint returns
`code 20 "Operation not permitted."` -- read and write alike, whatever the context value
(section 11). That is indistinguishable from the endpoint being unsupported on the platform,
and it is not hypothetical: during issue #76 testing on 2026-08-02 it produced the confident
and wrong conclusion "presets are unsupported on FB-A." Re-running as a dynamic-model admin
turned the same calls into `code 6` / `code 13` / `code 24` -- real semantic answers, and the
entire basis of the mutation table in "Fleet-scoped mutations have no usable default."

**Never conclude an endpoint is unsupported from a `code 20`.** Establish
`authorization_model: dynamic` before any context probe.

### `GET /topology-groups/arrays` cannot be probed bare

Its own parameter validation runs *before* the context check and returns `code 24`
("`recursive` must be used with `topology_group_names` or `topology_group_ids`") when the fleet
has no topology groups. Passing `topology_group_names=nonexistent` clears it, after which the
endpoint returns `code 15` as expected. **A `code 24` from that endpoint is not evidence either
way** -- it means the context check was never reached.

### Exercise the injection path, not a hand-assembled request

An early live test that "confirmed" the version gate called `Invoke-PfbApiRequest` with
`context_names` *already present* in `-QueryParams`, which is not how injection delivers it, so
it exercised a path the shipped code would not take. Requirement 1 of section 5 -- inject
before `Assert-PfbApiCapability` -- is what makes the real code path match that tested
behavior. A test that supplies the parameter itself cannot detect the ordering bug.

## Appendix E: revision history

Kept so the document's corrections stay traceable without being carried in the body. Nothing
here is a live design statement: where a revision withdrew something, the body already reflects
the withdrawal.

### Rev 1 -> rev 2

Rev 2 fixed rev 1's two central errors -- silent skip-injection became a hard throw, and
ambient context moved from module `$script:` scope onto the connection object. Both survive
unchanged in rev 3.

### Rev 2 -> rev 3

Rev 3 closes gaps rev 2 left open and corrects one claim rev 2 stated as settled:

- **`allow_errors` is specified.** Rev 2 did not mention it at all, though it is one of the
  two parameters this feature exists to inject.
- **`context_names` is a family of context kinds**, not an array name. Rev 2 treated it
  throughout as "a specific fleet member." Established in an architecture discussion with Wes
  Mertes together with live testing against a real 3-array fleet.
- **The verb rule is withdrawn.** Rev 2 proposed treating every `GET` as
  multi-context-capable. Live testing on 2026-08-01 disproved that for four endpoints.
  Cardinality is now data-driven from the capability map (section 8).
- **HTTP 207 and the `errors` response array** are specified as a response-layer requirement
  (section 10).
- **A cross-array authorization precondition** (`authorization_model`) is specified
  (section 11).
- **Fleet-scoped *mutations* are specified.** Rev 2, and rev 3 as first drafted, characterized
  fleet-scoped endpoints from `GET` evidence alone. Live testing of `POST`/`PUT`/`DELETE
  /presets/workload` on 2026-08-02 found the no-context default *fails* on a mutation rather
  than resolving to a local view, so omitting context is not a safe default there. This has a
  consequence for shipped code -- see "Fleet-scoped mutations have no usable default".
- **Context scope is specified, and sourced from the spec** (section 12). Rev 2 and rev 3 both
  promised client-side kind-vs-scope validation without saying where scope comes from. fb2.28
  declares it in `x-pure-remote-execution-context-domains-override` -- on five endpoints,
  agreeing exactly with live testing -- alongside a flag, `x-pure-incomplete-gre`, marking the
  28 operations whose remote-execution annotation upstream knows to be unfinished. The module
  reads the declared value, curates only the flagged gap, and ships the result in the
  capability map. This is also what lets it tell a user *"this command requires a fleet
  context"* instead of relaying `code 13`, which subsumes Open Question 3 and unblocks
  Open Question 7.
- **The capability-map staleness question is decided** rather than left implicit, and the
  dissenting view is recorded -- see "Capability-map staleness".
- **Phasing is corrected.** Rev 2 put `Invoke-PfbInContext` in Phase 2 while relying on it
  in Phase 1 as the documented escape hatch from the Phase 1 hard throw.
- **The durable-context idiom is corrected.** Rev 2 documented
  `$fb = $fb | Set-PfbContext -Context 'b'` as the durable path; that form is withdrawn,
  because the pipeline slot now belongs to `Get-PfbFleetMember | Set-PfbContext` -- see
  "Ergonomics".
- **The single-choke-point claim is qualified.** Rev 2 stated it as settled. Two ordinary write
  cmdlets bypass `Invoke-PfbApiRequest`; both are now closed pending merge (section 1).
- **`.arrays` is specified as a first-class context form, and `FanOut` is renamed.** Rev 3 as
  first drafted modelled it as a `FanOut` boolean. Two changes: the field becomes an
  enum-valued `Form`, because the suffix vocabulary is open and a boolean cannot be extended
  without a breaking change; and the name "fan-out" is reserved for a possible future
  client-side serial loop over N arrays, which differs from `.arrays` in request count,
  failure semantics and mutability. The switch is `-AllArrays`.
- **`Get-PfbTopologyGroupMember | Set-PfbContext` is withdrawn as the whole-group idiom.**
  Rev 3 as first drafted offered it as reaching "the same outcome as `<group>.arrays`". It does
  not: a group's members may themselves be groups, so the member pipeline yields group names
  where array names are required, and it snapshots membership that `.arrays` re-resolves per
  request. The cmdlet remains correct for scoping to specific members. See "Ergonomics".
- **`-AllArrays` validates membership**, a deliberate and bounded exception to the
  no-hidden-network-calls preference, which Open Question 2 previously left as an open choice
  and now settles.
- **The topology-group ownership boundary is stated** rather than left to be inferred from two
  issues -- see "Phasing". Membership resolution is this design's; object management is #38's;
  a binding contract crosses between them.

### Dated decisions and consults

| Date | Record |
|---|---|
| 2026-07-23 | Local context is still a context -- the module does not copy the server's local short-circuit. Settled with Wes Mertes. |
| 2026-08-01 | The verb rule falsified on four fleet-scoped GETs; cardinality becomes data-driven. Spec figures and the rule's verdict independently reproduced by a second agent, on the specs and against a live fleet using a remote member. |
| 2026-08-02 | Fleet-scoped mutations characterized during issue #76 live testing; context scope sourced from the fb2.28 vendor extensions. |
| 2026-08-02 | `.arrays` verified through both the CLI and REST on a 3-array fleet, with the two context kinds shown to be strictly disjoint. Reported back to Wes Mertes, together with the finding that his `purepreset workload list --context myFleet.arrays` example does not work on this build -- `.arrays` landed for array-scoped resources but not for fleet-scoped ones. |
| 2026-08-02 | `Form` stored as an enum rather than a boolean, and "fan-out" reserved for a future client-side serial loop. Settled with the maintainer. |
| 2026-08-02 | `-AllArrays` resolves membership before storing the context; topology-group object management stays with issue #38 under a stated binding contract. Settled with the maintainer. |
