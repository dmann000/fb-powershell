# Spec: Fusion context support, Phase 0 (prerequisites)

Status: proposed
Design doc: `docs/design/fusion-context-injection.md` (rev 4)
Tracking: #25 (Fusion `context_names` injection), #74 (component-resolution move)
Coordinates with: #84 (capability-map generator/schema tracker) — see item 2
Branch: `feat/fusion-context-phase-0`

> **Settled:** item 2 needs `Data/PfbCapabilityMap.json`'s `schemaVersion` bumped to 2, and so
> does issue #83. Tracking issue #84 originally planned them as a single bump in a single PR.
> **That pairing is dissolved** — Phase 0 ships `contextScope` and takes `schemaVersion 2`;
> #84's generator work moves to its own PR. See "Coordination with #84."

---

## Purpose

Phase 0 lands the four things that must exist **before** the Fusion `context_names`
injection path can be built, and lands them as one PR that ships no user-visible context
surface at all.

The design doc's Phasing section originally folded all four into Phase 1. They are split out
because each one is independently justifiable, each is reviewable without holding the whole
context design in mind, and two of them are load-bearing for Phase 1 in a way that is easy to
get wrong if built at the same time as the feature that consumes them:

| # | Work item | Why it must precede Phase 1 |
|---|---|---|
| 1 | Move `context_names` component resolution from `tools/lib` into `Private/` | Phase 1 needs resolved component names to call the cardinality predicate at all. Built in the obvious order it will silently reimplement the rule, producing two copies (#74) |
| 2 | `contextScope` per-endpoint field in the capability map, `schemaVersion` 2 | Kind-vs-scope validation and every scope-aware error message are map lookups. They cannot be written before the map carries the field |
| 3 | Connect-time capability-map staleness warning | It is the honesty half of the design's decision to stay permissive beyond the map's scanned range. Not context-specific |
| 4 | `Get-PfbFleetMember` top-level `MemberName` / `FleetName` | Worth doing on its own merits; Phase 1's `Set-PfbContext` pipeline binding depends on it |

Items 3 and 4 are improvements this module wants regardless of Fusion. Fusion is only where
their absence bites hardest.

**Nothing in Phase 0 introduces `-Context`, `Set-PfbContext`, `Invoke-PfbInContext`,
`-AllArrays`, or any injection behaviour.** A user upgrading to this cannot tell the context
work is coming, except that `Get-PfbFleetMember` output is more readable and a warning may
appear at connect time.

---

## Out of scope

Explicitly deferred, listed because a reviewer will reasonably wonder:

- The `PfbContext` object, connection context state, and the injection path — Phase 1.
- Consuming `contextScope` for validation or error messages — Phase 1. Phase 0 **populates
  and ships the field, and nothing reads it at runtime.**
- `allow_errors` surfacing and the HTTP 207 response branch — Phase 2.
- `context_ids`, a multi-value mutating fan-out helper, context display in
  `Get-PfbArrayConnection` — Phase 3.
- Topology-group and fleet/realm object-management cmdlets — #38.
- **Module version bump and CHANGELOG.** Per project convention these are the maintainer's
  own decision and are not part of feature PRs. Note this is unrelated to item 2's
  `schemaVersion` bump, which is a field inside the capability-map data file, not the
  module version.

---

## Item 1 — Move `context_names` component resolution into `Private/`

Closes #74.

### Problem

`Private/Test-PfbContextMultiValueCapable.ps1` shipped in PR #73 as the single declared home
of the cardinality rule. The code producing its `-ContextComponent` input did not ship with
it. `PureStorageFlashBladePowerShell.psm1` dot-sources only `Private/` and `Public/`; `tools/`
is never loaded. So the predicate is loaded into the module and **cannot be fed from inside
it** — it currently has zero runtime callers and is inert.

The resolution logic lives in `Get-PfbContextParameterFact`
(`tools/lib/PfbContextRuleTools.ps1`, the `CapabilityMap` branch), which also does record
shaping and HTTP 207 merging. Those two are maintainer-toolchain concerns and stay in
`tools/`. Untangling the three responsibilities is the actual work; the move is small.

### The contract being moved

Three steps, in order, and the ordering is the whole point:

1. If the endpoint's `parameterComponentOverrides` **contains the key** for the parameter,
   that value is authoritative **even when it is JSON `null`** — `null` means "this
   endpoint's parameter has no component." Do not consult defaults.
2. Otherwise, if top-level `parameterComponentDefaults` contains the parameter name, use it.
3. Otherwise, no known component.

Steps 1-with-`null` and 3 both yield `$null`, so the distinction is **not visible in the
return value** — it is entirely about whether step 2 is allowed to run. That is precisely why
#74 flags it as the part most likely to be reimplemented subtly wrong: both cases look like
"no value" to a casual reading, and a reimplementation that checks
`if ($overrides.$name)` instead of `if ($overrides.PSObject.Properties.Name -contains $name)`
silently falls through to the default for a `null` override and produces a wrong component
name for exactly the endpoints the cardinality rule cares about.

### Change

Add `Private/Resolve-PfbParameterComponent.ps1`:

```powershell
function Resolve-PfbParameterComponent {
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] $EndpointEntry,          # one capability-map endpoints.<key> object
        [Parameter(Mandatory)] [string]$ParameterName,
        [AllowNull()] $ParameterComponentDefaults        # the map's top-level table
    )
    # returns the resolved component name, or $null
}
```

Deliberately parameterised on `-ParameterName` rather than hardcoded to `context_names`: the
three-step contract is a property of the capability map's shape, not of Fusion, and
`allow_errors` will need the same resolution in Phase 2.

Pure, like `Test-PfbContextMultiValueCapable` — no map loading, no file I/O. The caller
supplies the entry and the defaults table.

Then:

- `Get-PfbContextParameterFact` calls it instead of inlining the resolution. Behaviour
  unchanged. It keeps record shaping and 207 merging.
- `tools/lib/PfbContextRuleTools.ps1` gains a dependency on `Private/`. **This direction is
  the fix** — `tools/` may depend on `Private/`, never the reverse. Relocating without
  inverting the dependency would not resolve #74.
- The tools lib currently defines `$script:PfbContextParameterName = 'context_names'` and
  `$script:PfbAllowErrorsParameterName = 'allow_errors'` at lines 51/53. Decide one home for
  these rather than duplicating them; a `Private/` constant that `tools/` consumes matches
  the dependency direction.

`tools/` is not on the module's load path, so it must dot-source the `Private/` file
explicitly. Verify this works from the drift-report entry point and not merely from an
interactive session that already has the module imported.

### Acceptance

- `Resolve-PfbParameterComponent` is reachable inside the module (`internal: True`).
- `Get-PfbContextParameterFact` remains internal to `tools/` and is **not** exported.
- `Tests/PfbContextRuleTools.Tests.ps1` (54 tests) stays green.
- `Tests/Build-PfbApiDriftReport.Tests.ps1` (60 tests) stays green. Note what this does and does
  not prove: its byte-identical assertions (`:351-391`) check **determinism across two runs on
  the same synthetic fixtures**, not that the committed artifacts reproduce. The real-artifact
  checks are a separate `Describe` that **skips gracefully when `tools/specs/` is absent** — and
  `tools/specs/` is gitignored, so in a fresh worktree they silently do not run. Confirm they
  actually executed rather than reading a green result as coverage.
- New unit tests for the resolver covering all three steps, with **key-present-but-`null` and
  key-absent as separate explicit cases**. This is the regression the move exists to prevent;
  a test that only exercises "returns `$null`" does not distinguish them. Assert that a
  `null` override does **not** fall through to a default that would otherwise match.

---

## Item 2 — `contextScope` in the capability map

Implements design doc section 12, "Encoding it in the shipped map."

### Problem

Phase 1's kind-vs-scope validation and all of its scope-aware error messages need to know
whether an endpoint is fleet-scoped or array-scoped. The capability map has no field for it,
and `tools/Build-PfbCapabilityMap.ps1` reads **none** of the `x-pure-*` vendor extensions
(verified: zero occurrences in the generator).

Neither operation `tags` nor cardinality is a usable proxy. Cardinality is close enough to be
a trap: a fleet-scoped endpoint is necessarily size-1, but so is every array-scoped mutation,
so size-1 is implied by fleet scope and does not imply it back.

### Where the signal comes from

Three vendor extensions, measured against `tools/specs/fb2.28.json`:

| Extension | Count at 2.28 | Meaning |
|---|---|---|
| `x-pure-remote-execution-context-domains-override` | **5** | The context domains this operation accepts |
| `x-pure-incomplete-gre` | **28** | Remote-execution annotation is known incomplete here |
| `x-pure-block-remote-execution` | **266** | Remote execution unsupported |

The override covers exactly five operations, all `/presets/workload`, and agrees with live
testing without qualification:

```
GET    /presets/workload  ->  ARRAY, FLEET
PUT    /presets/workload  ->  FLEET
POST   /presets/workload  ->  FLEET
DELETE /presets/workload  ->  FLEET
PATCH  /presets/workload  ->  FLEET
```

Reads legal in either domain, writes fleet-only — precisely what the wire does. The
declaration and the measurement are independent derivations of the same fact.

These are not three independent signals. They are a partially-completed annotation pass plus a
flag marking where it is unfinished. So:

| Endpoint state | Scope source |
|---|---|
| Has an override | **Trust it** |
| No override, not flagged incomplete | Default `array` |
| Flagged `x-pure-incomplete-gre` | **Do not trust the absence of an override.** Curated value where live evidence exists, else `unknown` |

### The curated table is four entries

Of the 28 flagged operations, nine already have evidence: the five preset operations carry the
override and need no curation, and four were established by live testing. Verified that all
four are in fact flagged:

| Entry | `contextScope` | Provenance |
|---|---|---|
| `GET /topology-groups` | `fleet` | live-tested |
| `GET /topology-groups/arrays` | `fleet` | live-tested |
| `GET /topology-groups/members` | `fleet` | live-tested |
| `GET /workloads/tags` | `array` | live-tested |

The remaining 19 flagged operations record `unknown`, which suppresses kind-vs-scope
validation in Phase 1 and leaves today's behaviour. Each curated entry retires as upstream
fills in its override.

**Verified gap worth writing down:** the five topology-group **write** verbs are not flagged
and carry no override, so they fall to the `array` default even though the family's reads are
fleet-scoped. That is the fail-safe direction — it costs guidance rather than blocking a call.
Live testing on 2026-08-04 confirmed those writes do in fact succeed in array context, so the
default is not merely safe here, it is correct. Re-check when #38 lands.

### Change

1. **Generator reads the three extensions.** The map is already built across 2.0-2.28 with
   last-seen-wins, so a value present only in the 2.28 document lands correctly with no change
   to the version-merging logic.
2. **`contextScope` becomes an additive per-endpoint field**, alongside `minVersion`,
   `parameters`, `bodyProperties`, `parameterComponentOverrides`. It records the value and its
   provenance (`declared` / `live-tested` / `unknown`).
3. **Bump `schemaVersion` 1 -> 2** (`tools/Build-PfbCapabilityMap.ps1:317`) — but see
   "Coordination with #84" below, because this bump is **not this spec's to make alone.**

   Two facts about `schemaVersion` that are easy to get wrong in both directions. It is
   **per-artifact, not global**: five generators each write their own independent value, and all
   five artifacts currently read `1`.

   | Artifact | Generator |
   |---|---|
   | `Data/PfbCapabilityMap.json` | `tools/Build-PfbCapabilityMap.ps1:317` |
   | `Data/PfbResponseShapeMap.json` | `tools/Build-PfbResponseShapeMap.ps1:173` |
   | `Reports/PfbApiDriftReport.json` | `tools/Build-PfbApiDriftReport.ps1:637` |
   | `Reports/PfbFieldCmdletMap.json` | `tools/Build-PfbFieldCmdletMap.ps1:98` |
   | `Reports/PfbValueEnumMap.json` | `tools/Build-PfbValueEnumMap.ps1:153` |

   So bumping the capability map's value does **not** implicate the other four. And **nothing
   in `Private/` or `Public/` reads `schemaVersion` at all** (verified) — it is a label for
   maintainers, not a migration gate. The bump is therefore nearly free, which is precisely why
   it must not be spent carelessly: the cost of a bump is not compatibility, it is that two
   pending changes needing "version 2" cannot both claim it independently.
4. **The curated table lives in the generator**, not in `Private/`. Runtime code reads scope
   from the shipped map and nowhere else. A curated list consulted at runtime would be a
   second source of truth for the same fact — the exact failure mode #74 exists to fix.
5. **Default `array`**, the fail-safe direction. Mis-marking a fleet-scoped endpoint as
   array-scoped costs guidance and leaves today's behaviour; the reverse would throw on a call
   that would have worked.
6. **Not version-gated.** A resource does not migrate between the fleet database and an array,
   so last-seen-wins is correct here in a way it is not for component identity. The 2.28
   annotations describe 2.23-era endpoints accurately.
7. **Regenerate `Data/PfbCapabilityMap.json`** and commit it. 632 endpoints today.

This rides the existing `.github/workflows/update-api-capability-map.yml`. One generator
change, one schema bump, one test — no new pipeline.

### Coordination with #84 — `contextScope` does not own `schemaVersion 2`

**This is the part the design doc does not cover, because it is not a Fusion concern.**
`Data/PfbCapabilityMap.json` was reopened as tracking issue **#84**, which coordinates four
pending generator changes that converge on one tracked file and, for two of them, on one
`schemaVersion` bump:

| Issue | Change | Schema impact |
|---|---|---|
| #71 | `MaxDepth=8` truncation records 5 body fields one release too late | none |
| #82 | Schema walk never descends through `items`, so all four array-bodied endpoints record `bodyProperties: {}` — 23 fields invisible | none |
| #83 | Array-body cardinality (`minItems`/`maxItems`/`uniqueItems`) has nowhere to live | **needs `schemaVersion 2`** |
| #25 | `contextScope` (this spec) | **needs `schemaVersion 2`** |

#84's plan is **PR 1** = #71 + #82 (no schema change), then **PR 2** = #83 + `contextScope`,
sharing a single bump. #83's title says "needs schemaVersion 2" outright.

The hard constraint is not the version label — it is that **every one of these regenerates the
same 632-endpoint generated artifact.** Two open PRs both touching `Data/PfbCapabilityMap.json`
conflict on the artifact regardless of whether their generator changes touch the same code.
(They largely do not: #83 lives in `Add-PfbSchemaPropertyNodes` in `tools/lib/PfbSpecTools.ps1`,
walking request-body schemas, while `contextScope` reads operation-level `x-pure-*` extensions.)

**#85 — the phantom-diff blocker — is now CLOSED**, so the sequencing hazard it created is
gone. Previously, report generators emitted in filesystem-enumeration order, and regenerating on
a Linux runner instead of a Windows workstation produced a 10,218-line diff in
`Reports/PfbFieldCmdletMap.json` with zero semantic change. That would have buried this work.
Note the capability map itself was never affected — `Build-PfbCapabilityMap.ps1` never walks
`Public/`/`Private/`, and its spec enumeration is explicitly sorted — but Phase 0 regenerates
the derived reports too, so it would have dragged the phantom diff along.

#### Decision: the pairing is dissolved

**Phase 0 ships `contextScope` and takes `schemaVersion 2`. #84's generator work — #71, #82,
#83 — moves to its own PR, and #83 takes the next `schemaVersion` it finds.**

The test applied was whether Phase 0 could absorb *all* of #84, which would have preserved
#84's one-bump intent. It cannot, for a structural reason rather than a size one: **#71, #82 and
#83 all land in `Add-PfbSchemaPropertyNodes`** (`tools/lib/PfbSpecTools.ps1:191`), a recursive
schema walker whose `MaxDepth` is threaded through five call sites and which feeds **both**
`Data/PfbCapabilityMap.json` and `Data/PfbResponseShapeMap.json`. Changing it perturbs two
runtime artifacts and every derived report at once. It also has a downstream consumer with
nothing to do with Fusion — **#44 (batch cmdlets) is blocked on PR 1**, because its four
endpoints are exactly the ones #82 makes visible.

Folding that into a Fusion prerequisites PR would put a delicate shared refactor in front of a
reviewer who is there to evaluate context plumbing, and would couple Phase 1's timeline to it.
`contextScope`, by contrast, reads operation-level `x-pure-*` extensions and does not touch the
body-schema walk at all — the two changes are genuinely independent in code.

What this costs: two sequential regenerations of `Data/PfbCapabilityMap.json`, and #84's
"one bump" bookkeeping goal. Both are acceptable, because **nothing reads `schemaVersion`** — it
is a label. What it buys is that neither PR gates the other.

Consequences to honour:

- **#84 must be updated** so its PR 2 no longer claims `contextScope`. Leaving that stale
  misleads whoever picks the tracker up.
- **Whichever PR lands second regenerates the artifact** and resolves the conflict on it. That
  is a mechanical regeneration, not a merge — do not hand-resolve a 632-endpoint generated file.
- **#83 increments from whatever it finds**, rather than being pre-assigned 3. If Phase 0 slips
  and #83 lands first, #83 takes 2 and Phase 0 takes 3. The number carries no meaning; only
  "newer than what I read" does.

Also worth re-checking at implementation time: the regeneration path itself has been failing.
`update-api-capability-map.yml` has failed on every run since 2026-07-24 at the final
`Open pull request` step (`GitHub Actions is not permitted to create or approve pull requests`
— a repo setting, not a code fault). Generation and tests pass and the branch is still
force-pushed, so `origin/automated/update-api-capability-map` holds regenerations `main` has
never received. **Check that branch before regenerating by hand**, or Phase 0 may re-derive work
that already exists. Fixing the workflow needs repo-admin access.

### Drift test

A test asserting:

- The five declared overrides still match what the generator emits.
- **Any curated entry whose endpoint has since gained an override is flagged**, so the curated
  set shrinks on its own instead of quietly shadowing better data. This is the part that keeps
  the table honest; without it a curated `fleet` would outlive the upstream fix indefinitely.
- The three extension counts, as a canary on the annotation pass advancing.

### Acceptance

- Every map endpoint has a `contextScope` with a provenance value.
- The five preset operations read `declared`; the four curated entries read `live-tested`; 19
  flagged operations read `unknown`; everything else `array`.
- `schemaVersion` is 2 and `Get-PfbCapabilityMap` still loads the map on both PS editions.
  (Note its 5.1 branch deliberately calls `ConvertFrom-Json` without `-Depth`, which does not
  exist before PS6 — do not "fix" that into a single call.)
- `Tests/Build-PfbCapabilityMap.Tests.ps1` and `Tests/Get-PfbCapabilityMap.Tests.ps1` green.
- `Tests/Build-PfbApiDriftReport.Tests.ps1` green. **There is no byte-identical regeneration
  gate on the committed map** — `update-api-capability-map.yml` regenerates and opens a PR, it
  does not fail on a diff. The actual enforcement is the "nothing vanishes" invariant in this
  test file, and it is guarded on gitignored `tools/specs/`, so it skips in a fresh worktree.
  Verify the specs directory is populated before treating a pass as meaningful.
- If regenerating changes a tracked report, that is still a finding to explain rather than a file
  to quietly re-baseline — but the guard rail is review, not CI.

---

## Item 3 — Connect-time capability-map staleness warning

Implements design doc section "Connect-time staleness warning."

### Why

`Assert-PfbApiCapability`'s founding principle is that a capability check must never be the
reason a call that would otherwise succeed gets blocked. The design keeps a **permissive**
fallback when the connected array's REST version exceeds the map's scanned range: no evidence
either way, so proceed without injecting or throwing.

Wes argued the opposite — that permissiveness trades away safety, since the module cannot
distinguish "never supported" from "supported in a version we have not scanned." The decision
is to stay permissive, for a reason specific to this module: a REST caller names a version in
the URL and can reason about it; a cmdlet caller has not, because the module negotiates the
version for them. Blocking a call because the *bundled map* is older than the array punishes
a packaging lag the user cannot see and did not choose. The remedy is to tell them the map is
behind.

**This warning is what makes that trade honest, and is therefore a required part of the
decision rather than a nicety.** It is not context-specific; `context_names` is only the
sharpest instance, because its lag fails silently rather than with a clean wire 400.

### Change

- **Check once, unconditionally, in `Connect-PfbArray`** — regardless of any context
  parameter. Compare the negotiated version against the maximum of the map's `generatedFrom`
  (29 entries today, `2.0`-`2.28`).
- **Cache the result on the connection object** (e.g. `.ExceedsCapabilityMapCoverage`) rather
  than recomputing per call. The connection is built at
  `Public/Connection/Connect-PfbArray.ps1:373`; note it already exposes the negotiated version
  as **both** `RestApiVersion` and `ApiVersion` (same value), and maintains an explicit
  property list at `:405` that a new property must be added to.
- **One-shot per connection** — fires once for the connection's life however many calls or
  context changes follow.
- Because it fires at connect universally, Phase 1's `Set-PfbContext` /
  `Invoke-PfbInContext` need no trigger of their own. A defensive re-check there is cheap
  insurance for a connection cached from before an upgrade.
- **Message**, naming the sharp case:

  > Connected array is running REST 2.29; this module's capability map only covers through
  > REST 2.28 — capability checks for anything newer, including context scoping, cannot be
  > fully verified and may not error even if unsupported. Check the PowerShell Gallery for a
  > newer release (`Update-Module`).

- **No live Gallery lookup.** `Find-Module` is a network dependency with real latency and
  failure modes, and this module runs against air-gapped lab and customer arrays. Point at the
  mechanism; do not auto-detect whether an update exists.

### Acceptance

- Fires when negotiated version > `max(generatedFrom)`; silent when within range.
- Fires **exactly once** per connection — assert the count, not merely that it appeared.
- Uses `Write-Warning`, so `-WarningAction SilentlyContinue` suppresses it and it never
  contaminates the pipeline. A connection object is still returned.
- No network call is made to determine it.

---

## Item 4 — `Get-PfbFleetMember` top-level `MemberName` / `FleetName`

Implements design doc section "Make `Get-PfbFleetMember | Set-PfbContext` first-class,"
piece (a) only. Pieces (b) and (c) are `Set-PfbContext`'s own parameter shape and belong to
Phase 1.

### Problem

`Get-PfbFleetMember` (`Public/Replication/Get-PfbFleetMember.ps1`) returns the raw
`FleetMember` objects from `fleets/members`, whose top-level properties are `coordinator_of`,
`fleet`, `member`, `status`, `status_details`. The array name is nested at `.member.name`.

`ValueFromPipelineByPropertyName` matches only top-level names, so in Phase 1 the natural
form binds nothing and the pipe **silently no-ops** — the same silent-wrong-scope family the
whole context design exists to fight.

### Change

Decorate each emitted object with top-level:

- `MemberName` = `.member.name`
- `FleetName`  = `.fleet.name`

Worth doing on its own merits: it makes the object readable at the console and gives the
pipeline something to bind. The cmdlet already uses `-AutoPaginate`, so decoration must apply
to every page's items, not just the first.

### Deliberately not added: `IsLocal`

The obvious third property — filter out the local array before scoping a context — is a trap.
`is_local` is relative to **the call's context**, not to the connection: call
`/fleets/members` with context ArrayB and ArrayB reports `is_local = true` while ArrayA
reports `false`. A documented `Where-Object { -not $_.IsLocal }` idiom would therefore select
a different array once a context is active, silently.

Determining the local array should use the connection, not a per-call response field.
`/fleets/members` may not accept `context_names` at all yet, which masks the problem today
but does not fix it.

### Acceptance

- Both properties present on every emitted object, across pagination.
- Raw nested `member` / `fleet` objects still present — this is additive, not a reshape.
  Existing callers reaching `.member.name` keep working.
- Absent or partial API data (a member with no `.member.name`) yields `$null`, not a throw.
- No `IsLocal`.
- New `Tests/Get-PfbFleetMember.Tests.ps1` — the cmdlet has no test file today.

---

## Testing

Per this repo's testing rule: **scope every run, and run both PowerShell editions.** CI gates
on Windows PowerShell 5.1 as well as pwsh 7, and a scoped pwsh-7-only run cannot see a
container failure on 5.1. Use
`.claude/skills/run-pester-tests/scripts/Invoke-ScopedPester.ps1 -Path <files>`, which runs
both concurrently and fails if either does. Read the `Container` column, not the counts — a
healthy skip run and a `#requires`-killed file both read `0 / 0`.

Do **not** run the aggregate suite as a completion check; that is CI's job.

Baseline for this branch, already captured at `ad00aae`: pwsh 7 `135/0/0`, WinPS 5.1
`96/0/39 skipped`, `Container ok` both.

Files in scope:

| File | Items |
|---|---|
| `Tests/PfbContextRuleTools.Tests.ps1` | 1 |
| `Tests/Resolve-PfbParameterComponent.Tests.ps1` (new) | 1 |
| `Tests/Build-PfbApiDriftReport.Tests.ps1` | 1, 2 |
| `Tests/Build-PfbCapabilityMap.Tests.ps1` | 2 |
| `Tests/Get-PfbCapabilityMap.Tests.ps1` | 2 |
| `Tests/Connect-PfbArray.*.Tests.ps1` | 3 |
| `Tests/Get-PfbFleetMember.Tests.ps1` (new) | 4 |
| `Tests/ModuleManifest.Tests.ps1` | 1 (new `Private/` file) |

Two 5.1 traps that have each already broken CI here: adding a `Describe` to an existing file
without matching the guard its siblings carry, and editing anything under `tools/`. Item 1 and
item 2 both touch `tools/`.

Do not test a mandatory parameter by `Should -Throw` alone — `[Parameter(Mandatory)]` prompts
and hangs under `-NonInteractive` instead of throwing. Use an optional parameter with an
explicit throw.

---

## Live verification

Required before this branch opens a PR — mocked unit tests are necessary but not sufficient
sign-off here.

Target FB-A (`cc-test-fleet` coordinator, Purity//FB 4.8.2, REST 2.26), reusing existing lab
resources. Preconditions from the design doc's Appendix D still apply to anything touching
context: probe as a **dynamic**-authorization-model admin, never static `pureuser`, which
returns `code 20` on everything fleet-scoped and produces confident wrong conclusions.

Phase 0 ships no injection, so the surface to verify live is small:

1. **Item 4** — `Get-PfbFleetMember` against the real 3-member fleet emits `MemberName` and
   `FleetName` populated for all three.
2. **Item 3** — the negative case is the one that matters: FB-A at REST 2.26 is **within**
   the map's range, so the warning must **not** fire. Force the positive case by stubbing the
   map's `generatedFrom` maximum below the negotiated version rather than by waiting for a
   newer array.
3. **Item 2** — spot-check that the shipped map's `contextScope` for the four curated entries
   and the five preset operations matches what the array actually does. This is re-confirming
   already-measured facts against the regenerated artifact, not new discovery.

Item 1 has no live surface — it is a refactor with no runtime caller until Phase 1.

---

## Risks

| Risk | Handling |
|---|---|
| Regenerating the map perturbs a tracked `Reports/` artifact | No CI gate catches this byte-for-byte. Diff the regenerated artifacts by hand and explain any change; do not re-baseline silently |
| The drift tests pass without running | They skip on gitignored `tools/specs/`. Confirm the directory is populated — it is in both Fusion worktrees (29 files) |
| The resolver move changes resolution behaviour subtly | Covered by the explicit key-present-`null` vs key-absent tests. Note the `Reports/` reproduction check is **not** an independent witness here, contrary to how it is often cited |
| **`schemaVersion 2` claimed twice** — by this spec and by #83 | Settled: Phase 0 takes 2, #83 increments from what it finds. Not a compatibility problem either way, since nothing reads the field. Requires updating #84 so its PR 2 stops claiming `contextScope` |
| Both PRs regenerate the same 632-endpoint artifact | Expected. Whichever lands second regenerates rather than hand-resolving the conflict |
| Regenerating by hand duplicates work already on `origin/automated/update-api-capability-map` | Check that branch first; its auto-PR step has been failing since 2026-07-24 |
| Curated `contextScope` entries outlive the upstream fix | The drift test flags any curated entry that has gained an override |
| Phase 1 needs a scope value Phase 0 marked `unknown` | `unknown` suppresses validation and leaves today's behaviour, so Phase 1 degrades rather than breaking. Adding an entry later is a generator-table edit plus a regenerate |

---

## Open questions

None blocking. Two carried from the design doc and settled for Phase 0's purposes:

- **Whether `x-pure-incomplete-gre` should become a third signal in the maintainer drift
  report** (design doc section 12, "Consequences for section 8"). It is not a cardinality
  predicate, but it is upstream telling us where two-signal comparison is blind, and all four
  endpoints the withdrawn verb rule got wrong carry it. Phase 0 records the count as a canary;
  promoting it to a full signal is deferred, not rejected.
- **`x-pure-block-remote-execution` contradicts `context_names` on 11 endpoints.** All 11 are
  inside the 28 flagged incomplete, which is self-consistent. It means `block` cannot be used
  as a runtime signal without excluding the flagged set first. Phase 0 reads the extension but
  does not act on it.
