# Design: Fusion context injection (`context_names`)

Status: **Draft / for review** (rev 2, incorporates Justin Emerson's live-tested review of rev 1)
Author: Don Mann
Related: Fusion / fleet support, `Private/Invoke-PfbApiRequest.ps1`, capability map
(`Data/PfbCapabilityMap.json`), `Private/Assert-PfbApiCapability.ps1`

## Problem

Many FlashBlade REST endpoints accept a `context_names` query parameter (Fusion
fleet context) so a single management connection can target a specific fleet
member instead of the local array. Today the module has no first-class way to set
that: a caller would have to drop to raw REST or hand-build query params.

The naive fix -- add a `-Context` parameter to every affected cmdlet -- is a
non-starter:

- The module exports ~520 cmdlets. Threading a new parameter through all of them
  (and keeping it in sync as endpoints change) is a large, error-prone surface.
- Not every endpoint accepts `context_names`. A blanket parameter would let
  callers send it to endpoints that reject it, producing confusing 400s.
- `context_names` arrived at a specific REST version per endpoint. We already have
  that information in the capability map; we should reuse it rather than re-encode
  it by hand.

## Goals

- Let a caller pick a fleet context once and have it apply to subsequent calls.
- Allow a per-call override without a session-wide change.
- **Never let a set context be silently dropped.** If a caller asks for a context
  and it cannot be honored, the call must fail loudly, not silently execute against
  the wrong target. (This is the central lesson from the rev-1 review; see below.)
- Never send `context_names` to an endpoint (or array version) that does not
  support it.
- Zero change to the ~520 public cmdlet signatures.

## Non-goals

- Modelling every Fusion concept (realms, presets, fleet membership management).
  This spec covers only injecting `context_names` into outbound requests.
- `context_ids` (id-based targeting). Names first; ids can follow the same shape
  if there is demand.
- Client-side write fan-out across multiple contexts (see the multi-value section).

## What changed since rev 1

Rev 1 proposed storing the ambient override in module script scope and *silently
skipping* injection when the target endpoint did not support `context_names`.
Justin's review (live-tested against real arrays, including one on Purity//FB
4.6.5 / REST 2.22) showed both of those choices reintroduce the exact
silent-wrong-scope failure this feature exists to prevent:

- A `context_names` sent to an endpoint that never supported it is **silently
  accepted** by the array (HTTP 200, mutation applied), so "let the array reject
  it" does not work as a safety net.
- Script-scoped state does not survive nesting, a second connection, or a
  parallel runspace, and would silently fall back to "no context."

Rev 2 fixes both: **hard-throw instead of silent skip**, and **connection-object
state instead of module scope**.

## Design

Every request funnels through one choke point, `Invoke-PfbApiRequest`, so that is
the one place context is resolved and injected. No public cmdlet changes.

### 1. Context state lives on the connection object

Two properties on the `$Array` connection object, with two different mutation
policies:

- **`.DefaultContext`** -- durable session default. Set at connect time or via
  `Set-PfbContext` / `Clear-PfbContext`, which are **copy-on-write**: they return
  a *new* connection object and never mutate the one the caller passed in. This
  prevents a context change leaking into other code holding the same reference.
- **`.ContextOverride`** -- the ambient, block-scoped value `Invoke-PfbInContext`
  sets. Mutable, but scoped by construction and restored via `try`/`finally`.

Storing this on the object (rather than in `$script:` module scope) is what makes
nesting, multiple connections, and `$using:`-passed parallel work behave correctly
instead of silently falling back to no context. It also matches how the module
already writes `AuthToken`/`TokenExpiresAt` back onto `$Array` during
auto-reconnect. (Distinction: token refresh is a *transparent* mutation; context
is a *targeting* mutation that changes where a write lands -- hence the stricter
copy-on-write policy on the durable default.)

### 2. Setting a context

```powershell
# At connect (durable session default)
$fb = Connect-PfbArray -Endpoint mgmt-fb -ApiToken $t -Context 'member-a'

# Change / clear the durable default later (copy-on-write: capture the return value)
$fb = Set-PfbContext   -Array $fb -Context 'member-b'
$fb = Clear-PfbContext -Array $fb

# Ambient per-call override (auto-restores, nests correctly)
Invoke-PfbInContext -Array $fb -Context 'member-c' {
    Get-PfbFileSystem -Array $fb          # member-c
    Get-PfbNetworkInterface -Array $fb    # member-c
}
Get-PfbFileSystem -Array $fb              # back to the session default
```

`Set-`/`Clear-PfbContext` are **Phase 1** (moved up from rev 1's Phase 3): without
them a session context set at connect can only be changed by reconnecting. They
must also update the module's connection cache (`$script:PfbArrays` /
`$script:PfbDefaultArray`) to point at the new copy, or callers relying on the
implicit default connection would keep hitting the old object.

`Invoke-PfbInContext` needs no explicit stack -- each invocation captures the
prior value in a local and restores it in `finally`, so the PowerShell call stack
provides push/pop discipline and nesting restores the *outer* value (not "none"):

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

### 3. Resolving and injecting context in `Invoke-PfbApiRequest`

Resolve the effective context once, at the top of the choke point:

```
explicit -QueryParams['context_names']  >  $Array.ContextOverride  >  $Array.DefaultContext  >  none
```

**Tri-state "none":** distinguish *unset* (`$null`) from *explicit no-context*
(`[string[]]@()`). Both resolve to "nothing to inject," but the empty-array form is
a deliberate "run this one call locally" (hence `[AllowEmptyCollection()]` and a
`-ne $null` check, not a truthiness check). Only a **non-empty** resolved context
is subject to the hard-throw gate below -- so `Invoke-PfbInContext -Context @()`
is the escape hatch for running one call locally even on an endpoint that does not
support `context_names`.

Then, **before the existing `Assert-PfbApiCapability` call and before the
`-AutoPaginate` loop** (ordering matters -- see below), and only when the resolved
context is non-empty:

1. If the endpoint's capability-map entry **lists `context_names`** (any version):
   inject it into `$QueryParams` and let the existing `Assert-PfbApiCapability`
   version check do its job (unchanged -- it already throws a clean, readable
   error when the array's version predates `context_names` for that endpoint).
2. If the map has **no entry for `Method Endpoint`, or the entry does not list
   `context_names`**, AND the connected array's version is **within the map's
   scanned range** (`generatedFrom`): **throw**, naming the endpoint and telling
   the caller their context could not be honored. Do not send the request. This
   absence is *confirmed* -- we scanned that version's spec and the param is not
   there.
3. Same as (2) but the array's version **exceeds** anything the map scanned:
   proceed permissively (no inject, no throw). We have no evidence either way, and
   the module's founding rule is "a capability check must never block a call that
   would otherwise succeed." Backed by the connect-time staleness warning below.
4. No context set -> unchanged; no injection, no check.

Apply the throw **uniformly across all verbs, including `GET`**. A silently
wrong-scoped read is not safer than a blocked write: warnings are routinely
suppressed in automation, a wrong-scope read inside a fleet-wide loop corrupts a
result set invisibly, and a `GET`'s output routinely feeds a later mutating call.
`Invoke-PfbInContext -Context @()` (or `Clear-PfbContext`) is the explicit opt-out.

**Implementation ordering (two non-obvious details):**

- Inject **before** the existing `Assert-PfbApiCapability` call, not "immediately
  before the request is built." If `context_names` lands in `$QueryParams` after
  Assert runs, Assert never sees it and the version check in step 1 never fires.
- Inject by **mutating the `$QueryParams` hashtable**, not the built query string.
  `-AutoPaginate` rebuilds the query string from `$QueryParams` on every page, so
  mutating the hashtable carries `context_names` forward for free on every page;
  appending to the first page's URI would drop it from page 2 on. (`Get-PfbArraySpace`
  is a live example of a paginated read that would be affected.)

### 4. Connect-time capability-map staleness warning

Independent of `context_names`, the module's capability knowledge can lag a
customer's actual firmware. Surface it once, at `Connect-PfbArray`,
unconditionally (not gated on `-Context`): compare the negotiated `$Array.ApiVersion`
against the map's `generatedFrom` maximum; if the array is newer, cache a flag on
the connection and emit a one-shot warning naming the concrete case, e.g.:

> Connected array is running REST 2.28; this module's capability map only covers
> through REST 2.27 -- capability checks for anything newer, including context
> scoping, cannot be fully verified and may not error even if unsupported. Check
> the PowerShell Gallery for a newer release (`Update-Module`).

No live `Find-Module` lookup (this module runs against air-gapped arrays); just
point at `Update-Module`.

### Precedence

```
explicit -QueryParams['context_names']  >  $Array.ContextOverride  >  $Array.DefaultContext  >  (none)
```

## Multi-value `context_names`: a real API split, not a free choice

The OpenAPI spec defines two components that both surface as `context_names`:

- **`Context_names_get`** (`GET`, plus one `DELETE`): true multi-target fan-out,
  comma-separated names, resolved atomically server-side.
- **`Context_names`** (`POST`, `PATCH`, and almost every `DELETE`): "must be an
  array of size 1." The size-1 limit is free-text only, not a structured
  `maxItems`, so it is not mechanically detectable from the schema.

The split tracks verb almost perfectly. The one exception is
`DELETE /management-access-policies`, which uses the multi-value variant and was
also added at exactly REST 2.26 -- possibly a spec/doc error. **Open question for
Don (below).**

Interim design pending confirmation: treat `GET` as multi-context-capable and
`POST`/`PATCH`/`DELETE` as single-context-only, uniformly, with the one known
`DELETE` exception called out in code comments. This also exposes a gap in the
capability map: it records only `paramName: introducedVersion`, with no cardinality
concept -- closing it properly means teaching `tools/Build-PfbCapabilityMap.ps1`
which of the two spec components an endpoint references (or hardcoding the
verb heuristic with the documented exception).

## Open questions for Don / Justin to settle

1. **Multi-value on a size-1 write endpoint: throw or client-side fan-out?**
   Leaning **throw** (Justin's recommendation, and mine): client-side fan-out
   silently changes the return shape (scalar -> N objects) based on session state
   the calling code may not see, has no clean partial-failure story, and is not
   equivalent to the server's atomic read-side fan-out. If ergonomics later
   demand it, add a separate, explicitly-named opt-in cmdlet that returns
   per-context-annotated results and surfaces partial failure loudly -- not
   automatic behavior triggered by cmdlet-plus-context-shape.

2. **Is `DELETE /management-access-policies`'s multi-value `context_names` real
   or a spec bug?** Cannot be safely settled by testing (can't tell "honored 2
   names" from "silently used the first"). Needs a direct confirmation.

3. **"Explicit `-QueryParams['context_names']` wins" -- wins over what,
   concretely?** Today nothing in the public API can populate that top precedence
   tier: every public cmdlet builds its own fixed `QueryParams`, and
   `Invoke-PfbApiRequest` is private. Is this reserved for a specific future
   fleet-aware cmdlet, or is it defensive layering? If the latter, the doc should
   say so rather than imply a path that does not exist yet.

## Notes for a later pass (non-blocking)

- **Annotate fleet-membership failures with the active context name.** A bad
  context name returns `code 42 "Cannot find array in fleet"`, which currently
  surfaces bare -- no indication of which context (possibly a session default set
  and forgotten) caused it. The injection layer should annotate it.
- **State the security model explicitly.** `context_names` is not itself an auth
  boundary; any valid management connection can *attempt* to target any fleet
  member, and enforcement is entirely server-side (RBAC). The client enforces
  nothing about which contexts a caller may target -- say so, so no reader assumes
  otherwise.
- **Pipeline caveat.** `Invoke-PfbInContext`'s scriptblock form is not
  pipeline-friendly by nature; the durable path is
  (`$fb = $fb | Set-PfbContext -Context 'b'`).

## Test plan

- Three-level precedence resolution, including the empty-array "explicit none" case.
- Capability-gated injection on both the allow path and the hard-throw path.
- `Assert-PfbApiCapability`'s version check for `context_names` specifically.
- Nested `Invoke-PfbInContext` restoring the *outer* value, including when the
  inner block throws (exception safety, not just the happy path).
- Cross-connection isolation: an override set via `$fb1` must not affect calls
  made with `$fb2` in the same block.
- `Set-PfbContext` leaving the original object's `.DefaultContext` untouched while
  the cache/default pointer moves to the new copy.
- Staleness warning fires once per connection when the array outranges the map.

## Phasing

- **Phase 1**: connection-object state (`.DefaultContext` / `.ContextOverride`),
  `Connect-PfbArray -Context`, `Set-`/`Clear-PfbContext` (copy-on-write),
  capability-gated **hard-throw** injection in `Invoke-PfbApiRequest`, and the
  connect-time staleness warning.
- **Phase 2**: `Invoke-PfbInContext` ambient override.
- **Phase 3**: `context_ids`, and -- only if confirmed wanted -- an explicit
  multi-context write fan-out cmdlet.
