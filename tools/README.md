# API Capability Map Toolchain

Generates `Data/PfbCapabilityMap.json` — a manifest mapping every FlashBlade REST API
endpoint (and its parameters and request-body fields) to the REST version it was
introduced in — plus everything built on top of it: `Data/PfbVersionMap.json` (the
REST-version to Purity//FB-version pairing), prose-extracted value enumerations, a
field-to-cmdlet recommendation join, and a combined drift report (see the sections
below). The one runtime consumer is `Private/Assert-PfbApiCapability.ps1`, called from
`Invoke-PfbApiRequest.ps1`: it fails fast, before any HTTP call, when the connected
array's REST version can't satisfy an endpoint/parameter/field this toolchain has
recorded a later minimum version for.

## Scripts

Run in this order:

1. **`Update-PfbApiSpecs.ps1`** — fetches every published REST version's OpenAPI spec
   from `https://code.purestorage.com/swagger/` and caches it as pretty-printed JSON
   under `tools/specs/fb<version>.json`. Skips versions already cached unless `-Force`.
   The spec isn't a plain downloadable file — see `lib/PfbSpecTools.ps1` for why, and how
   it's extracted from the ReDoc reference page.

   `tools/specs/` is **gitignored, not committed**. It's a build-time input only — never
   read at runtime — and at ~1-3MB per REST version (~48MB across the full history as of
   2026-07), committing it would bloat every clone of this repo. That matters here more
   than in a typical repo: today, cloning this repo and copying the checkout straight into
   `$env:PSModulePath` *is* the documented "from source" install method (see the root
   README), so anything committed at repo root ships to every user, not just contributors.
   Locally, just run the fetcher once and the cache persists on disk for reuse; CI
   re-fetches the full set fresh on every run (a few minutes, and it only runs weekly).

   ```powershell
   ./tools/Update-PfbApiSpecs.ps1                       # fetch anything new
   ./tools/Update-PfbApiSpecs.ps1 -Versions 2.26,2.27 -Force   # re-fetch specific versions
   ```

2. **`Build-PfbCapabilityMap.ps1`** — loads all cached specs in ascending version order
   and diffs them into `Data/PfbCapabilityMap.json`. Runs entirely offline once specs are
   cached.

   ```powershell
   ./tools/Build-PfbCapabilityMap.ps1
   ```

   Accepts `-MaxVersion '2.27'` to cap ingestion at a numerically-compared REST version
   (`Major`/`Minor` as integers, never a string compare — `'2.9'` sorts above `'2.27'` as
   a string) even if `tools/specs/` has newer cached files on disk. Defaults to `$null`
   (no cap, ingest everything cached). Use this when a newer spec has been fetched but not
   yet deliberately adopted — every acceptance number this toolchain's plan work is
   calibrated against assumes a specific version ceiling, and an uncapped rebuild would
   silently move those numbers.

   Besides `minVersion`/`parameters`/`bodyProperties` (each `{ name: introducedInVersion }`,
   monotonic first-sight), each endpoint also carries, where non-empty:
   - `readOnlyBodyProperties` / `deprecatedBodyProperties` (string arrays) — **last-seen-wins**,
     not first-sight: unlike "introduced in version X", `readOnly` is not monotonic (a
     field can go from read-only to writable across versions, and about half of the flips
     in fb2.0-2.27 do exactly that), so these always reflect the newest spec that mentions
     the endpoint, never the oldest.
   - `parameterComponentOverrides` (`{ paramName: componentName }`, sorted by key) — see
     below.

   **`parameterComponentDefaults`/`parameterComponentOverrides` resolution contract:**
   which named OpenAPI `components/parameters/*` component backs a given
   `(endpoint, parameter)` pair is recorded across two places instead of once per
   endpoint, because the vast majority of parameters share one of a small set of common
   components (`Filter`, `Limit`, `Sort`, …) — measured on fb2.0-2.27: 4102 total
   `(endpoint, parameter) -> component` pairs, but only 224 distinct pairs and 179
   distinct parameter names, so a naive full per-endpoint map is ~90% duplication. To
   resolve the component for a given `(endpoint, parameter)`:
   1. If the endpoint's `parameterComponentOverrides` contains the parameter name, use
      that value — which **may be a JSON `null`**, meaning "this endpoint's parameter has
      no component" (see below). An override, `null` or not, always wins over the default.
   2. Otherwise, if the manifest's top-level `parameterComponentDefaults` contains the
      parameter name, use that value.
   3. Otherwise, the parameter has no known component at all.

   `parameterComponentDefaults` is built once, globally: for each parameter name, the
   most frequently associated component name across every endpoint's current mapping,
   ties broken **alphabetically** by component name (deterministic regardless of endpoint
   processing order — required, since the weekly CI job opens a PR on any diff and an
   unstable tie-break would spuriously fire it). `parameterComponentOverrides` then holds
   only the endpoints where the current component differs from that default.

   The explicit-`null`-override case is the one to know about: a parameter declared
   **inline** (no `$ref`) has no component at all — rare (7 of 4109 parameter
   declarations in fb2.27), but if that parameter's *name* happens to also be a `$ref`'d
   component elsewhere (and so has a global default), silently omitting it from
   `parameterComponentOverrides` would make it wrongly inherit that default under the
   resolution contract above. The builder emits an explicit `null` override for exactly
   this case so "absent" (→ check the default) and "explicitly none" (→ `null`) stay
   distinguishable.

3. **`Update-PfbVersionMap.ps1`** — builds `Data/PfbVersionMap.json`, the REST-version to
   Purity//FB-version pairing, from a single internal SSOT (Single Source of Truth) API
   call that returns the full REST<->Purity//FB mapping table for every version in one
   HTML response. This is an internal endpoint, so its base URI, topic ID, and API key
   are all required inputs with no default or hardcoded value in this repo — sourced
   from `$env:SSOT_BASE_URI`,
   `$env:SSOT_TOPIC_ID`, and `$env:SSOT_API_KEY` (sent as an `x-api-key` header)
   respectively. Without all three configured, this script just reports which versions
   need lookup and exits without failing.

   ```powershell
   $env:SSOT_BASE_URI = '...'
   $env:SSOT_TOPIC_ID = '...'
   $env:SSOT_API_KEY = '...'
   ./tools/Update-PfbVersionMap.ps1
   ```

4. **`Build-PfbValueEnumMap.ps1`** — a separate analysis built on top of the capability
   map (see "Value-enum extraction" below): loads the same cached specs and extracts
   prose-documented value enumerations
   (e.g. `Bucket.versioning`'s "Valid values are `none`, `enabled`, and `suspended`.")
   into `Reports/PfbValueEnumMap.json`. Also runs entirely offline once specs are cached.

   ```powershell
   ./tools/Build-PfbValueEnumMap.ps1
   ```

5. **`Build-PfbApiDriftReport.ps1`** — the newest addition (see `Reports/README.md`): composes
   the capability map, cmdlet inventory, and value-enum data above into one combined
   "what's changed that we haven't caught up to" report, covering uncovered endpoints, new
   parameters on endpoints we already call, drift on existing `ValidateSet`s, and new
   `ValidateSet` candidates (reusing `Build-PfbFieldCmdletMap.ps1`'s `matched` output
   directly). See `tools/lib/PfbApiDriftTools.ps1` for the underlying functions.

   ```powershell
   ./tools/Build-PfbApiDriftReport.ps1
   ```

   Pass `-SinceVersion` to isolate what a single new REST release actually added instead
   of the full accumulated backlog -- e.g. after 2.27 ships, `-SinceVersion '2.26'` filters
   `uncoveredEndpoints`/`parameterGaps` down to just the items introduced by 2.27. Only
   those two categories support it: `validateSetDrift`/`newValidateSetCandidates` don't
   carry a per-value introduced-version in the capability map to filter on.

   ```powershell
   ./tools/Build-PfbApiDriftReport.ps1 -SinceVersion '2.26'
   ```

   `parameterGaps` also never reports a small set of non-actionable fields
   (`$script:PfbNonActionableParameters` in `tools/lib/PfbApiDriftTools.ps1`:
   `X-Request-ID`, `continuation_token`, `offset`) -- these are declared on nearly every
   endpoint and would otherwise drown out real gaps.

   **`missingBodyProperties` enrichment (addable body-property gaps only).** On an
   endpoint whose `confidence.level` is `'high'`, each `missingBodyProperties` entry is a
   record, not a bare string:

   ```jsonc
   { "name": "certificate_type", "type": "string", "format": null, "specRequired": false,
     "synopsis": "The type of the certificate.",
     "suggestedPowerShellType": "[string]",
     "enumValues": ["appliance", "external"], "enumStatus": "matched",
     "target": { "file": "Public/Certificate/Update-PfbCertificate.ps1",
                 "paramBlockLine": 37, "payloadVariable": "Attributes",
                 "assignmentStyle": "attributesOnly", "hasAttributes": true } }
   ```

   - **`missingQueryParameters` and `readOnlyFields` are NEVER enriched this way, and
     never will be for the same reason on both** -- `readOnlyFields` are not addable at
     all (nothing to build type/target coordinates FOR), and query-parameter gaps stay
     bare name strings on purpose: ~896 enriched query-gap records would roughly double
     this artifact's size for no consumer today (nothing downstream reads enriched
     query-gap detail). Deliberate, documented asymmetry -- not an inconsistency.
   - **Enrichment itself is gated on `confidence.level -eq 'high'`.** A
     `'partial'`-confidence endpoint's `missingBodyProperties` stays bare strings, exactly
     like before this feature existed. This is NOT a suppression -- every field name still
     appears, unchanged -- it only withholds the extra metadata layer. Reason: a
     partial-confidence endpoint's gap list can contain false positives (an unresolved
     parameter may already cover the field through a path the AST-only inventory can't
     see), and handing a human a fully-worked-out type/synopsis/enum/target for a field
     that might not even be a real gap would overstate a confidence the endpoint's own
     `confidence.caveat` is explicitly telling them not to have. Measured against the real
     capability map + specs (2026-07-26): 402 addable gaps on high-confidence endpoints vs.
     605 across both confidence levels combined -- the two populations produce genuinely
     different enum-join results (see below), confirming the gate is intentional scope,
     not an oversight.
   - **`suggestedPowerShellType`** comes from a fixed table: `integer`+`int64` -> `[long]`;
     `integer`+`int32`/`uint32`/no format -> `[int]`; `number` (any format) -> `[double]`;
     `string` -> `[string]`; `boolean` -> `[bool]`; `array` -> `[<element>[]]` (element
     mapped recursively, falling back to `[object[]]` when the element type can't be
     resolved); anything else -> `[object]`. This branches on `format`, not just `type`,
     because the failure mode is silent: **37 of the 402** real high-confidence addable
     fields are `type: integer, format: int64` (measured 2026-07-26 -- NOT the 230 once
     speculated for this figure; that number was investigated and could not be reproduced
     against any of six candidate populations tried). Mapping bare `"type": "integer"` to
     `[int]` without checking `format` would silently truncate every one of those 37
     fields. The raw `type`/`format` are always emitted alongside so a human can override.
   - **`specRequired` is the OpenAPI spec's own `required:` flag for that field -- it must
     NEVER be read as "make this a `[Parameter(Mandatory)]`".** This module has a recorded
     hazard: a `Mandatory` parameter tested via `Should -Throw` hangs the terminal on
     PowerShell's own "Supply values for parameters" interactive prompt; the convention
     here is an optional parameter with an explicit `throw`. Keep it that way even for a
     `specRequired: true` field.
   - **`enumValues`/`enumStatus`** come from `Resolve-PfbFieldValueEnum`
     (`tools/lib/PfbValueEnumTools.ps1`), never a bare wire-name lookup, keyed by the
     field's `OwnerSchema` (from `Get-PfbSchemaPropertyDetails`,
     `tools/lib/PfbSpecTools.ps1`) as `-ResourceHint` -- not the older cmdlet-name-derived
     `Get-PfbResourceHint`, which only reaches 14 of the 33 real matches (e.g.
     `Update-PfbNfsExportRule`'s derived hint `NfsExportRule` does not prefix-match the
     real owning schema `NfsExportPolicyRuleBase` at all). `enumStatus` is always one of
     that function's own literal values (`matched`/`collision`/`not-found-in-resource`/
     `no-spec-enum-found`), passed through verbatim. Measured over the 402 real
     high-confidence addable gaps: **33 matched / 43 not-found-in-resource / 326
     no-spec-enum-found** (0 real `collision` results in this dataset, though the status
     itself is never hardcoded away).
   - **`target`** carries insertion-point COORDINATES ONLY -- `{ file, paramBlockLine,
     payloadVariable, assignmentStyle, hasAttributes }` -- never a diff/patch: a patch goes
     stale the moment the file is next touched and cannot see mutual-exclusivity/
     parameter-set constraints a human editing by hand must respect.
     `payloadVariable`/`assignmentStyle`/`hasAttributes` describe what the target cmdlet's
     OWN function body already does for its other body fields (see
     `Get-PfbCmdletBodyInsertionTarget` in `tools/lib/PfbCmdletParamTools.ps1`), so a human
     adding one more field matches the file's existing convention: `assignmentStyle` is
     `'index'` for `$body['x'] = ...`, `'literal'` for a hashtable-literal initializer that
     declares at least one key, `'attributesOnly'` when the request body is fed directly
     by the cmdlet's own `-Attributes` parameter (there is no per-field line to imitate --
     adding a typed parameter here means introducing the first one), or `'unknown'` when
     the payload variable resolves but this AST-only inspector can't find any assignment
     into it at all (e.g. built by a private helper). When more than one cmdlet already
     calls the same endpoint (5 real cases today), the alphabetically first cmdlet name is
     picked as the one target, deterministically -- a human should still check for sibling
     cmdlets on the same endpoint.

## What's deliberately NOT in the capability map

The FlashBlade OpenAPI spec has no structural JSON Schema `enum` anywhere — verified
empty across every schema and parameter in both the oldest (fb2.10) and newest (fb2.27)
cached specs. Allowed values for fields like `Bucket.versioning` exist only as free-text
prose in `description` fields ("Valid values are `none`, `enabled`, and `suspended`."),
not as machine-readable constraints, so `Data/PfbCapabilityMap.json`
tracks endpoint, parameter, and request-body top-level property *existence* only — not
their legal values. That prose *is* now extracted, but into a separate file by a separate
generator — see "Value-enum extraction" below — precisely because it's a different kind
of claim with a different reliability bar (see that section for why per-*value*
"introduced in version X" tracking specifically remains out of scope even there).

Also out of scope: hardware-model capability (//S vs //E — what the module's existing
~12 `-match`-based "not supported on this model" warnings actually gate on). That's a
separate axis from REST version, handled from a different data source and not part of
this toolchain.

Also deliberately not built: version-aware `ArgumentCompleter`/`DynamicParam`s that would
hide a parameter an array's version doesn't support. Evaluated and shelved — completers
only complete a parameter's *value*, not its *name*, so they can't hide a parameter at
all; only `DynamicParam` can, and that would require editing every `Public/` cmdlet
individually for marginal benefit over the capability check above.

## Value-enum extraction (`Build-PfbValueEnumMap.ps1`)

A later, separate phase from the capability map above. `tools/lib/PfbValueEnumTools.ps1`
parses the "Valid/Possible values are/include ..." prose sentence out of a schema
property's or parameter's `description` — the only place these specs record a field's
legal value set, since (as above) there is no structural `enum` to read instead — and
`tools/Build-PfbValueEnumMap.ps1` diffs that across every cached spec version into
`Reports/PfbValueEnumMap.json`:

```powershell
./tools/Build-PfbValueEnumMap.ps1
```

Key correctness rules (each has a dedicated regression test in
`Tests/PfbValueEnumTools.Tests.ps1`):
- Entries are keyed by **`(SchemaName, PropertyName)`**, never by bare property name.
  Two different schemas can share a property name with different legal values (e.g.
  `NfsExportPolicyRuleBase.access` is `root-squash`/`all-squash`/`no-squash`, while the
  presets-only `_presetWorkloadExportConfigurationNfsRule.access` is
  `root-squash`/`all-squash`/`no-root-squash`) — collapsing by bare name would silently
  merge them.
- The extractor also covers a parameter defined **inline** directly on a
  `spec.paths.<path>.<method>` operation — not just `components.schemas` properties and
  named `components.parameters` entries. This matters because a field can be inline for
  years before a later spec refactor turns it into a `$ref`: `GET /arrays/space`'s `type`
  query parameter was inline (full "Valid values are `array`, `file-system`,
  `object-store`." description) from REST 2.0 through 2.16, only becoming
  `$ref: '#/components/parameters/Type'` at 2.17 — a pure documentation refactor, not an
  API change. Without this pass, the field's true `minVersion` (2.0) would be invisible
  and its earlier, inline-only history would be lost entirely. Keyed by
  `"<METHOD> <path>#<paramName>"` (`Kind = 'inline-parameter'`), never the bare parameter
  name, for the same never-collapse reason as above.
- Value extraction is scoped to the matched trigger *sentence* only, not the whole
  description, since some descriptions repeat the same backtick-quoted values again in
  explanatory prose that follows the enum sentence.
- A description that matches the trigger phrase but isn't actually a real enumeration
  (a numeric range, or free-text prose that happens to contain the words "valid values")
  is recorded as **unparsed**, not force-parsed and not silently dropped — surfaced in the
  manifest's `unparsedCount`/`unparsed` fields, same "never silently over-claim coverage"
  norm as the capability map's own coverage reporting.

The builder also writes `Reports/PfbValueEnumReconciliation.md`, comparing every existing
hand-written cmdlet `ValidateSet` that encodes a spec-documented enum against this newly
extracted data (exact match / stale / not-found / collision with an unrelated same-named
field elsewhere in the spec). That report is informational only — it does not edit any
`Public/` cmdlet.

**`Reports/PfbValueEnumMap.json`'s output is not consumed anywhere at runtime yet** — no
`ArgumentCompleter`, no `Assert-PfbApiCapability` enforcement. Whether/how to consume it
is a deliberate follow-on decision once real coverage/accuracy numbers exist from this
data, same as how the capability map above sat idle until `Assert-PfbApiCapability` was
built to consume it.

Per-enum-*value* "introduced in version X" tracking (e.g. knowing that `suspended` was
added to `Bucket.versioning` at some later REST version, as opposed to the field's own
overall `minVersion`) is intentionally not attempted — no reliable way was found to diff
individual values across versions given how often the same prose gets reworded without
the value set itself changing. The manifest tracks each field's current legal value set
and the field's own earliest-seen version only.

## Field-to-cmdlet mapping (`Build-PfbFieldCmdletMap.ps1`)

Joins the cmdlet parameter inventory (from `PfbCmdletParamTools.ps1`, which reads `Public/`
cmdlet ASTs) against the prose value-enum data extracted above to recommend, per typed
`Public/` parameter that lacks a `ValidateSet` today, whether it should become a
`ValidateSet` or an `ArgumentCompleter`:

```powershell
./tools/Build-PfbFieldCmdletMap.ps1
```

Key correctness rules:
- A parameter is recommended `ValidateSet` only if: the parameter's wire field appears in
  the spec, it has a documented value enumeration, that enumeration is present unchanged in
  every REST version from the field's introduction onward, and the field was present since
  the oldest cached version.
- A parameter is recommended `ArgumentCompleter` if the field exists but the value set
  changed at any point in the history, or the field was introduced in a newer version.
- A parameter is classified `collision` if its wire name matches multiple schema keys with
  different value sets, or `not-found-in-resource` if the wire name exists in the spec but
  not under any schema the cmdlet's resource hint suggests. Both require manual follow-up
  to ensure the intent is captured.
- An **`inline-parameter`**-kind value-enum record (see "Value-enum extraction" above) is
  keyed by exact endpoint identity (`"<METHOD> <path>#<paramName>"`), so when
  `PfbCmdletParamTools.ps1`'s AST inventory can determine exactly which endpoint a given
  cmdlet parameter calls, an exact match there overrides an otherwise-ambiguous
  `parameter`-kind wire name — this is precisely how `Get-PfbArraySpace -Type` resolves to
  `matched`/`ValidateSet` instead of `collision`, even though its wire name `type` also
  matches two disagreeing `components.parameters` definitions (`Type` and
  `Type_for_performance`) elsewhere in the spec.
- `attributesOnly` and `typedUnresolved` entries are *reported*, not resolved — they list
  parameters that either have no typed field to attach validation to (attributes-only),
  or have a wire name that couldn't be resolved to a spec key. These require human
  decisions (add a new typed parameter, or leave as-is); the script does not edit any
  `Public/` cmdlet.

The builder also writes `Reports/PfbFieldCmdletMapping.md`, a Markdown table summarizing
every candidate and its recommendation — informational only, not consumed at runtime.

**`Reports/PfbFieldCmdletMap.json`'s output is not consumed anywhere at runtime yet** — no
`ValidateSet` or `ArgumentCompleter` is added to any `Public/` cmdlet by this script.
Whether/how to consume it is a deliberate follow-on decision.

## Tests

`Tests/PfbSpecTools.Tests.ps1` and `Tests/Build-PfbCapabilityMap.Tests.ps1` cover the
capability-map extraction/diffing logic against small synthetic fixtures — no network
access required. One additional test in `Build-PfbCapabilityMap.Tests.ps1` checks the
real committed manifest for coverage gaps against the newest locally-cached spec, and
skips gracefully if `tools/specs/` (gitignored — run `Update-PfbApiSpecs.ps1` first) or
`Data/PfbCapabilityMap.json` aren't present.

`Tests/PfbVersionMapTools.Tests.ps1` covers the SSOT URL builder and HTML table parser
the same way — no network access, and no real base URI/topic ID/key needed, since those
are just parameters to a pure, synthetic-fixture-driven function.

`Tests/PfbValueEnumTools.Tests.ps1` and `Tests/Build-PfbValueEnumMap.Tests.ps1` cover the
value-enum extraction/diffing logic the same way, plus a `Bucket.versioning` regression
fixture and a squash-mode-gotcha fixture (see "Value-enum extraction" above). Their real-
manifest checks skip gracefully if `tools/specs/` or `Reports/PfbValueEnumMap.json` aren't
present.

## CI

`.github/workflows/update-api-capability-map.yml` runs this pipeline weekly (and on
manual dispatch): re-fetches the full spec history into an ephemeral (non-committed)
cache, rebuilds `Data/PfbCapabilityMap.json`, and opens a PR if it changed — i.e. the
swagger index published a new REST version, or an existing endpoint gained new
parameters/fields. Requires the repository's Actions settings to permit workflow-created
pull requests. The `SSOT_API_KEY`/`SSOT_BASE_URI`/`SSOT_TOPIC_ID` secrets are optional —
when any are absent, the version-map step is skipped gracefully and only the capability
map updates (see item 3 above).

`Build-PfbValueEnumMap.ps1`, `Build-PfbFieldCmdletMap.ps1`, and `Build-PfbApiDriftReport.ps1`
all run as part of the same weekly/dispatch job, right after the capability map is rebuilt,
so `Reports/PfbValueEnumMap.json`, `Reports/PfbFieldCmdletMap.json`, and
`Reports/PfbApiDriftReport.json` (+ their Markdown companions) stay fresh alongside
`Data/PfbCapabilityMap.json`.
