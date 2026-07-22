# Design: Fusion context injection (`context_names`)

Status: **Draft / for review**
Author: Don Mann
Related: Fusion / fleet support, `Private/Invoke-PfbApiRequest.ps1`, capability map (`Data/PfbCapabilityMap.json`)

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
- Never send `context_names` to an endpoint (or array version) that does not
  support it.
- Zero change to the ~520 public cmdlet signatures.

## Non-goals

- Modelling every Fusion concept (realms, presets, fleet membership management).
  This spec covers only injecting `context_names` into outbound requests.
- `context_ids` (id-based targeting). Names first; ids can follow the same shape
  if there is demand.

## Design

The module already funnels every request through a single choke point,
`Invoke-PfbApiRequest`. That is the one place to inject context, so no public
cmdlet needs to change.

### 1. Connection-level default

`Connect-PfbArray` gains an optional `-Context <string[]>` parameter. When
supplied, the resolved value is stored on the connection object as
`.DefaultContext`. This is the "target this fleet member for the whole session"
case.

```powershell
$fb = Connect-PfbArray -Endpoint mgmt-fb -ApiToken $t -Context 'member-a'
Get-PfbFileSystem -Array $fb     # implicitly scoped to member-a
```

### 2. Per-call override (ambient scope)

Rather than a parameter on every cmdlet, an ambient scope helper sets the context
for a block of calls and restores it on exit:

```powershell
Invoke-PfbInContext -Array $fb -Context 'member-b' {
    Get-PfbFileSystem -Array $fb          # scoped to member-b
    Get-PfbNetworkInterface -Array $fb    # also member-b
}
Get-PfbFileSystem -Array $fb              # back to the session default
```

Internally this sets a script-scoped override that `Invoke-PfbApiRequest` reads.
The scriptblock form guarantees the override is always cleared, even on error.
(A `Set-PfbContext` / `Clear-PfbContext` pair could be offered too, but the
scriptblock is the safe default and should ship first.)

### 3. Central injection, gated by the capability map

In `Invoke-PfbApiRequest`, immediately before the request is built:

1. Resolve the effective context: per-call override, else connection
   `.DefaultContext`, else none. If none -> do nothing.
2. If the caller already set `context_names` explicitly in `-QueryParams`, leave
   it untouched (explicit wins).
3. Look up the target `Method` + `Endpoint` in the capability map. Inject
   `context_names` **only if** the map says this endpoint accepts it. If the map
   has no entry for the endpoint, or the endpoint does not list `context_names`,
   skip injection silently -- fail safe, same philosophy as
   `Assert-PfbApiCapability`.
4. `Assert-PfbApiCapability` (already wired in from the capability-map work) then
   catches the case where the connected array's version predates `context_names`
   for that endpoint, so we do not need a second version check here.

### Precedence

```
explicit -QueryParams['context_names']  >  Invoke-PfbInContext override  >  connection .DefaultContext  >  (none)
```

## Why this is the right shape

- One insertion point (`Invoke-PfbApiRequest`), not ~520 edits.
- Reuses the capability map as the single source of truth for which endpoints
  accept `context_names`, so it stays correct as the map regenerates.
- Fail-safe: unknown endpoint or unsupported version -> no injection / clear error,
  never a silently-wrong request.
- Backwards compatible: callers who never set a context see identical behaviour.

## Open questions

1. Parameter name: `-Context` vs `-ContextNames` vs `-FleetMember`. Leaning
   `-Context` (short, matches the REST concept) with `-ContextNames` alias.
2. Does the capability map already record `context_names` per endpoint, or do we
   need to add that field when it regenerates? (This design assumes it can.)
3. Multiple contexts: the REST param is plural. Do we support fan-out to several
   members in one call, or constrain to one for now?
4. Should `Get-PfbArrayConnection` / display surface the active default context?

## Phasing

- **Phase 1**: `-Context` on `Connect-PfbArray` + central capability-gated
  injection in `Invoke-PfbApiRequest`. Covers the common session-default case.
- **Phase 2**: `Invoke-PfbInContext` ambient override.
- **Phase 3**: optional `Set-PfbContext`/`Clear-PfbContext`, `context_ids`,
  and display surfacing -- only if asked for.
