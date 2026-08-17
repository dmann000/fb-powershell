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

   The manifest carries a top-level `schemaVersion`, currently **2** (raised from 1 when
   `contextScope` was added). It is a maintainer label only — nothing in `Private/` or
   `Public/` reads it, and each generated artifact versions itself independently, so
   bumping one does not implicate the others.

   Besides `minVersion`/`parameters`/`bodyProperties` (each `{ name: introducedInVersion }`,
   monotonic first-sight), each endpoint also carries, where non-empty:
   - `readOnlyBodyProperties` / `deprecatedBodyProperties` (string arrays) — **last-seen-wins**,
     not first-sight: unlike "introduced in version X", `readOnly` is not monotonic (a
     field can go from read-only to writable across versions, and about half of the flips
     in fb2.0-2.27 do exactly that), so these always reflect the newest spec that mentions
     the endpoint, never the oldest.
   - `parameterComponentOverrides` (`{ paramName: componentName }`, sorted by key) — see
     below.

   And **unconditionally on every endpoint** (unlike the list above, this key is never
   omitted):
   - `contextScope` — the Fusion remote-execution scope, `{ scope, provenance }`. `scope`
     is `array`, `fleet`, or `unknown`; `provenance` is `default`, `declared`,
     `live-tested`, or `unknown`. Also **last-seen-wins**, for the same reason as
     `readOnlyBodyProperties`: it is a property of the current API surface, not of when
     something was introduced. Derived by `Get-PfbSpecContextScope` from three
     operation-level extensions — `x-pure-remote-execution-context-domains-override`
     (authoritative when present → `declared`), `x-pure-incomplete-gre`, and
     `x-pure-block-remote-execution` — overlaid with a small curated table in
     `Build-PfbCapabilityMap.ps1` for endpoints flagged incomplete upstream but verified
     on the wire (→ `live-tested`). An endpoint flagged incomplete with neither an
     override nor a curated entry resolves to `unknown`/`unknown`, which is a **designed
     degradation**: consumers are expected to treat it as "no opinion" and fall back to
     existing behaviour rather than failing.

   **`parameterComponentDefaults`/`parameterComponentOverrides` resolution contract:**
   which named OpenAPI `components/parameters/*` component backs a given
   `(endpoint, parameter)` pair is recorded across two places instead of once per
   endpoint. **The prose below describes the contract; the single implementation of it is
   `Private/Resolve-PfbParameterComponent.ps1`** — call that rather than reimplementing
   the three steps, and update it and this section together. The split exists because the
   vast majority of parameters share one of a small set of common
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

5. **`Build-PfbResponseShapeMap.ps1`** — builds `Data/PfbResponseShapeMap.json`, the
   *response*-side counterpart to the capability map (see "Response-shape drift" below).
   Loads the same cached specs and diffs each endpoint's response body across versions.
   Must run **before** `Build-PfbApiDriftReport.ps1`, which reads the file it writes (and
   which degrades to an explicit "Not analysed" banner, never a silent empty section, if
   it is missing).

   ```powershell
   ./tools/Build-PfbResponseShapeMap.ps1
   ```

6. **`Build-PfbApiDriftReport.ps1`** — the newest addition (see `Reports/README.md`): composes
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

   **`analysedVersions` / `availableSpecVersions` / `versionDivergenceWarning` -- the
   `generatedFrom` split.** The manifest never emits one ambiguous `generatedFrom` key.
   `analysedVersions` is `Data/PfbCapabilityMap.json`'s own `generatedFrom` -- the version set
   every gap/phantom-field/systemic-gap/convention-strength category below is actually scoped
   against. `availableSpecVersions` is whatever `tools/specs/` has cached on disk right now,
   which Task 5's enum join and category 3 (ValidateSet drift) DO read fresher-than-analysed
   data from (see `Get-PfbValueEnumHistory`'s `$historyResult`). These two normally move
   together, which is why keeping them as one key was invisible as a problem for a long time --
   but they are independent inputs that drift the moment specs are refreshed
   (`Update-PfbApiSpecs.ps1`) without also rebuilding the capability map
   (`Build-PfbCapabilityMap.ps1`): as of this writing, `tools/specs/` is cached through 2.28 while
   `Data/PfbCapabilityMap.json` is deliberately still pinned at 2.27 (see item 2's `-MaxVersion`
   note above for why that pin is deliberate). `versionDivergenceWarning` is a non-`$null` string
   exactly when the two sets disagree, never silently absent -- read it before trusting any other
   category in the manifest at face value. (This is the same "validated against whatever spec
   happens to be on disk, not against the analysed set" root cause behind the one known,
   persistent failure in `Tests/Build-PfbValueEnumMap.Tests.ps1` -- see "Tests" below.)

   **`confidence` and the norm reversal it represents (decision 5).** Every endpoint's gap
   lists are *always* computed now -- there is no longer an all-or-nothing gate that discards an
   endpoint's real gaps just because one parameter on it has an unresolved surface. This reverses
   an earlier, more conservative design, and the reversal is deliberate, not an oversight:
   - **The old design.** A `$fullyMapped` gate suppressed an endpoint's entire gap computation
     the moment any cmdlet calling it had a parameter whose `Surface` was `AttributesOnly` or
     `TypedUnresolved` (i.e. not cleanly `Typed`), routing the endpoint into a `notVerified`
     bucket instead -- a bare count in the report's summary, with no detail table anywhere. The
     reasoning was sound on its face: such a parameter *might* already cover the apparent gap
     through a path this AST-only inventory cannot see, so reporting it outright risked a false
     positive.
   - **Why it was reversed.** Measured against the real module, roughly 70% of the endpoints
     landing in `notVerified` turned out to be tool blindness -- real, fixable parser gaps, not
     genuine ambiguity -- and the failure mode was silence: a reader had no way to know what, or
     even which endpoints, might be missing something, because `notVerified` carried no detail.
   - **The new design.** `notVerified`/`$fullyMapped` no longer exist anywhere in the output
     shape. Every endpoint's `MissingQueryParameters`/`MissingBodyProperties`/`ReadOnlyFields` are
     always populated. The uncertainty an `AttributesOnly`/`TypedUnresolved` parameter introduces
     is instead carried per-endpoint as `confidence`: `{ level: 'high'|'partial',
     unresolvedParameters: [{parameter, surface, file, line}], escapeHatchOnly: [...], caveat }`.
     `level` is `'high'` iff `unresolvedParameters` is empty. A `'partial'` endpoint's gap lists
     can still contain false positives from this same mechanism -- that risk did not go away --
     but they are never silently emptied because of it. The reader gets the field name **and** a
     `file:line` to check it themselves (see the false-positive procedure immediately below).
   - **What did NOT change.** `Build-PfbFieldCmdletMap.ps1`'s own `attributesOnly`/
     `typedUnresolved` report buckets (see "Field-to-cmdlet mapping" below) are a different norm
     answering a different question -- "should this parameter become a `ValidateSet` or
     `ArgumentCompleter`" is a categorically different judgment call than "does this endpoint have
     an addable gap" -- and remain genuinely "reported, not resolved, requires a human decision."
     That norm is not reversed by this change.

   **The false-positive resolution procedure (decision 6).** This report accepts **false
   positives in order to eliminate false negatives**. A field is listed as missing even though
   the module can already set it, when a parameter covering it could not be traced to a wire
   name. Detection is only possible where `confidence.level` is `'partial'`; a `'high'`-confidence
   row carries no false-positive risk from this mechanism. Reproduced here verbatim from the
   generated Markdown's own "How to read this report" section (see
   `tools/Build-PfbApiDriftReport.ps1`) because `tools/README.md` is a standalone reference a
   maintainer may read without a generated report open:
   1. Open the named parameter at the given `file:line` and follow where its value goes.
   2. If it reaches the wire under the same name as the reported gap -> the gap is a false
      positive AND a tooling bug: the parser does not recognise that idiom. File it as a parser
      gap and fix the parser.
   3. If it reaches the wire under a different name -> the reported gap may still be real; check
      that field against the spec.
   4. If it never reaches the wire -> the gap is real.

   A false positive here costs a reader one `file:line` lookup; a false negative costs an
   undetected gap indefinitely. Every false positive is a parser-gap detector -- it either fixes
   the tool permanently for every endpoint, or confirms a real gap.

   **`systemicGaps` / `conventionStrength` (decisions 7-8).** `systemicGaps` collapses every
   *high*-confidence gap into one finding per distinct wire field name (never `'partial'` --
   folding a partial-confidence endpoint's possibly-false-positive gap into a systemic FINDING
   would overstate a confidence the endpoint's own row already warns against). Each finding is
   `{ name, endpointCount, queryEndpointCount, bodyEndpointCount, endpoints, annotations }` --
   turning hundreds of per-endpoint rows into a handful of real, actionable decisions: e.g.
   `context_names` and `allow_errors` are each one decision, not one finding per affected
   endpoint. `conventionStrength` then ranks each systemic-gap name by how many existing `Public/`
   cmdlets already expose it as a `Typed` parameter somewhere in the module (`Get-PfbConventionStrength`),
   sorted by that count descending: a high count (`names` at 306 cmdlets) means closing the
   remaining gaps for that name is a mechanical batch fix; a count of zero (`context_names`, 0 --
   no cmdlet anywhere in the module has ever exposed this name as a `Typed` parameter) means no
   established convention exists to extend at all, and closing it is an architectural decision,
   not a mechanical one. Both keys read `docs/drift-annotations.json` (via
   `Get-PfbDriftAnnotations`/`Find-PfbDriftAnnotation`) for recorded design decisions, prior
   conclusions, or live-testing hazards matched by field name (`systemicGaps[].annotations`) or by
   endpoint (`parameterGaps[].annotations`) -- the file is optional; its absence degrades every
   lookup to "no annotations" rather than failing report generation.

   **Known limitation: `systemicGaps`/`conventionStrength` only aggregate over high-confidence
   endpoints, silently omitting field names that appear ONLY on `'partial'`-confidence rows.**
   This is a deliberate choice, not an oversight -- a partial-confidence endpoint's gap list can
   contain false positives (see the false-positive procedure above), so folding it into a systemic
   FINDING would overstate a confidence the endpoint's own row already warns against. But the
   consequence is real: as of this writing, **54 distinct wire field names appear only on
   partial-confidence rows and are therefore absent from both `systemicGaps` and
   `conventionStrength` entirely** (e.g. `base_dn`, `bind_password`, `domain`, `nameservers`,
   `qos_policy`, `storage_class`, `owner`, ...), and a name that DOES appear can still undercount:
   `context_names`'s high-confidence-only `systemicGaps` figure is smaller than its true
   cross-confidence total across every endpoint, by design (that's the limitation described
   above, not a discrepancy worth investigating). No individual endpoint's own
   `missingQueryParameters`/`missingBodyProperties` row is affected -- this is purely a gap in the
   *aggregated triage view*, not in the underlying per-endpoint data. A future revisit should
   aggregate `systemicGaps`/`conventionStrength` across ALL confidence levels, carrying the current
   high-confidence-only count as `endpointCount` alongside a separate `partialEndpointCount`, rather
   than silently dropping names or re-baselining `endpointCount` itself. Not fixed here because
   doing so would change what `context_names`/`allow_errors`/etc. mean, which is a larger, separate
   design decision from the invariant-based tests that verify today's high-confidence-only
   aggregation (`Tests/PfbApiDriftTools.Tests.ps1`, `Tests/Build-PfbApiDriftReport.Tests.ps1`) --
   those tests recount/bound rather than pin to an exact figure, specifically so this kind of
   real-data number does not need to stay in sync with prose like this.

   **`phantomFieldCount` -- two correct, differently-scoped numbers.** How many `(endpoint,
   field)` pairs were silently dropped from every gap/read-only list because the field is
   accumulated in the capability map's `parameters`/`bodyProperties` dictionaries but absent from
   the newest ANALYSED spec (i.e. withdrawn from the real API after the version that first added
   it)? Two numbers are simultaneously correct, because they answer different-population
   questions:
   - Measured across the FULL population of endpoints an existing cmdlet calls, regardless of
     confidence level -- this is what `phantomFieldCount` in `Reports/PfbApiDriftReport.json`
     actually reports. (Deliberately not pinned to an exact figure in this prose -- it changes
     with the real API surface; `Tests/Build-PfbApiDriftReport.Tests.ps1` verifies it via a
     self-consistency check instead of an exact number.)
   - Measured over ONLY the high-confidence-endpoint subset -- this is the number in
     `Get-PfbParameterCoverageGaps`'s own doc comment (illustrative example text, not a contract)
     and in this task's real-data invariant tests (verified non-vacuous, likewise not pinned to
     an exact figure).
   Do not treat a mismatch between the two as a bug; check which population a given historical
   reference is scoped to first. Computed by calling `Get-PfbParameterCoverageGaps` a second time
   without `-CurrentSpecCapabilities` (its documented no-op default -- no phantom filtering) and
   diffing the resulting `(endpoint, list, field)` triples against the real, phantom-filtered run
   -- never a re-derivation of the phantom-detection logic itself.

   **The phantom-field limitation, and why it's documented-only.** `Build-PfbCapabilityMap.ps1`
   is first-sight-only for *additions* and never records *removal* -- `parameters`/
   `bodyProperties` accumulate forever across every ingested spec version. A field withdrawn from
   the API in a later spec (e.g. `PATCH /certificates|id` and `PATCH /certificates|name`:
   read-only in every version 2.0-2.19, removed outright from 2.20 onward -- never writable, so
   they are phantoms, not settable fields) still lingers in `Data/PfbCapabilityMap.json`'s own
   `bodyProperties` dictionary indefinitely. The drift report's phantom-field filtering (this
   section, and `Get-PfbParameterCoverageGaps -CurrentSpecCapabilities`) excludes these from every
   gap/read-only list in the REPORT by cross-checking against the single newest analysed spec, but
   the capability map itself never gets this correction -- it is a fundamentally different kind of
   claim ("this field was ever seen" vs. "this field currently exists") and rebuilding the map to
   track removal is out of scope for this effort. There is deliberately no `removedFields`
   category anywhere in this toolchain.

   **`readOnlyFields` reflects the newest ANALYSED spec, not the accumulated/historical one --
   same reason as `Data/PfbCapabilityMap.json`'s own `readOnlyBodyProperties` (item 2 above).**
   `readOnly` is not monotonic: a field can go from read-only to writable across versions (roughly
   half the real flips in fb2.0-2.27 do exactly that), so first-sight semantics would wrongly
   suppress a field that is genuinely settable today. Both the capability map's own
   `readOnlyBodyProperties` and this report's `readOnlyFields` are last-seen-wins for the same
   reason: spec text moves, and treating a field's *oldest* seen annotation as authoritative would
   misreport its *current* state.

   **The REST 2.17 cliff -- a spec-authoring event, not API evolution.** Naively grepping every
   cached spec for raw `"readOnly": true` annotation counts shows an apparent cliff at 2.17: 1091
   sites at 2.16, 408 at 2.17 -- a 63% drop that would lead a careless reader to conclude the API
   lost read-only enforcement on hundreds of fields in one release. **It did not.** The real cause
   is a `$ref` consolidation: named component (`$ref`) sites jump 10.5x in the same release (385 at
   2.16 -> 4038 at 2.17) -- duplicated inline `readOnly` annotations were consolidated into shared,
   referenced components, so one annotation site now serves many endpoints instead of being
   repeated inline at each one. Measured on *resolved* (endpoint, field) pairs -- the number that
   actually matters -- read-only coverage did not fall across this transition, it **rose**: 219
   pairs at 2.16 to 262 at 2.17. Nothing was un-read-onlied. **This is a trap for whoever later
   builds a `-SinceVersion`-style "since version X" delta feature over `readOnly`/`deprecated`
   transitions**: a transition-count metric computed from raw annotation sites, or from anything
   upstream of `$ref` resolution, will misread this release as instability that never happened.
   Use resolved (endpoint, field) pairs (`Get-PfbSchemaPropertyDetails`'s own single resolving
   walker, decision 3) for any future metric here, never a raw annotation-site count.

7. **`Build-PfbDeadKeyReport.ps1`** — builds `Reports/PfbDeadKeyReport.json`, the committed
   inventory of query keys emitted by `Public/` cmdlets that their endpoint does not declare
   for that HTTP verb. It pins analysis to the capability map's last `generatedFrom` version,
   skips body and unresolved parameters, and identifies destructive dead keys plus groups with
   no surviving selector. This is reporting only -- it does not edit any cmdlet.
   The `noSurvivingSelector` list deliberately under-reports in three specific ways -- read
   `Reports/README.md` before consuming it as a complete list.

   ```powershell
   ./tools/Build-PfbDeadKeyReport.ps1
   ```

## Response-shape drift (`Build-PfbResponseShapeMap.ps1`)

Everything above tracks the **request** side — which endpoints, query parameters, and
request-body fields exist in which REST version. `Data/PfbResponseShapeMap.json` is the
**response** side: for every endpoint (496 of them, across the 29 analysed REST versions
2.0-2.28), the set of fields the spec says its response returns, each with the version it
was first seen in — plus, for fields that have since disappeared, the version they were
last seen in — and each endpoint's own first/last-seen version. (Present fields carry a
scalar `introducedVersion` only: `responseEnvelope`/`responseItemProperties` are
`{field: version}`, and their last-seen version is implicitly the endpoint's own
`lastSeenVersion`. An explicit `lastSeenVersion` appears only on `removedResponseFields`
entries.) `Get-PfbResponseShapeFindings` (`tools/lib/PfbApiDriftTools.ps1`) turns that
history into the drift report's response-side categories: field **removals**, **rename
candidates** (a removal paired with a still-present field on the same endpoint and in the
same location that first appears in the version *immediately after* the removed field's
last-seen version — adjacency, not co-occurrence, and reported as a candidate rather than
asserted), and unhandled envelope fields such as `errors`.

**It is a separate file from `Data/PfbCapabilityMap.json`, deliberately, because it has no
runtime consumer.** `Private/Get-PfbCapabilityMap.ps1` loads the 298,841-byte capability
map into *every* user session; merging the response axis into it would add 242,917 bytes,
**+81%**, to that load — paid by every user of the module, forever, to serve an analysis
that only the drift report reads. And nothing may ever gate an API call on response data:
the capability check runs *before* the HTTP call, so response shape is not information it
could act on even in principle. The two artifacts answer different questions for different
audiences, so they stay in different files.

**The monotonicity rule.** Presence is tracked at both ends: `introducedVersion` is
**first-seen** (once a field has appeared, the version it appeared in never changes), and
presence is **last-seen** (the newest analysed version whose spec still declares it). A
field is a **removal** when its last-seen version is older than its endpoint's own
`lastSeenVersion` — i.e. the field is absent from the newest analysed spec *in which its
endpoint still appears*. Note the comparison is against the endpoint's **own** last-seen
version, which is not necessarily the newest analysed version overall: a retired endpoint,
last seen at some older version, would still have its own field removals reported. Today
that distinction is invisible — all 496 endpoints have `lastSeenVersion` 2.28, so the two
coincide — but it is the rule as implemented, and "the endpoint is still in the newest
analysed spec" is not part of it. This is deliberately *not* the same rule as
`readOnly`/`deprecated`, which are **last-seen-wins** (see item 2 above): `readOnly` is an attribute that flips back and forth
and only its *current* value is meaningful, whereas presence is a monotonic timeline whose
endpoints are both meaningful — when a field first appeared and whether it is still there.
Applying last-seen-wins to presence would lose the introduction history; applying
first-sight to `readOnly` would report a stale annotation as current.

**Known blind spot: transient fields are not reported at all.** There are 11 field-removal
*transition events* in the history but only **7** true removals. The other four are fields
that vanish for exactly one release and come back, all caused by upstream spec-authoring
defects, and all four are present again in fb2.28. The rule above — absent from the newest
analysed version in which the endpoint still exists — correctly excludes them, at the cost
of never surfacing a transient wobble as a finding. The two known cases:
`GET /active-directory`'s `continuation_token` and `total_item_count` (broken in 2.12,
fixed in 2.13 — the response schema dropped its `allOf` composition), and
`GET /buckets/performance`'s `max_total_bytes_per_sec` and `max_total_ops_per_sec` (broken
in 2.20, fixed in 2.21 — fb2.20 drops the `BucketPerformanceItems` component from the
document **entirely** (it is defined in both 2.19 and 2.21) and repoints the response's
`items[]` at the sibling `BucketPerformance` component, which has never carried those two
fields; this is a dropped component, not a mistyped `$ref`). Accepted: a
one-release wobble that the vendor has already fixed is not actionable for this module,
and reporting it would put four known-false rows in front of every reader of the 7 real
ones.

**The depth trap — read this before changing any `MaxDepth`.** `Get-PfbSpecResponseShapes`
(`tools/lib/PfbSpecTools.ps1`) defaults to **`MaxDepth 32`**, not the `8` used by the other
walkers in that same file. This is not a stylistic inconsistency and must not be
"normalised". fb2.12-2.16 contain deep `allOf` composition chains; at depth 8 those chains
truncate, whole field sets go unseen in the middle of the history, and the presence
accumulator then reports them as vanished — **184 false removals against a true total of
7**. Worse, the failure is invisible from the newest spec: on fb2.28 every depth from 8 to
32 produces identical results, so any check written against current data will look
perfectly correct while the historical middle of the map is silently wrong. 184 removals is
the depth-8 signature — if that number (or anything near it) ever appears, suspect the
depth before suspecting the API.

**Granularity: envelope plus `items[]`, one level deep.** Each endpoint records its
top-level response envelope fields and the fields of one level of `items[]`. Depth 3 was
measured and rejected: it produced 13 findings, of which 11 were duplicates of a level-1
parent already reported and the remaining 2 were a spec-authoring false positive — zero new
real signal, at **2.2x** the artifact size.

**Why additions are not findings.** The module reshapes almost nothing on the way out.
Measured over `Public/` on 2026-08-01 (542 `.ps1` files, one function each): **533 call
`Invoke-PfbApiRequest` at all** — the 9 that never do are session/credential helpers
(`Connect-PfbArray`, `Disconnect-PfbArray`, `Get-PfbConnection`, `Get-PfbApiVersion`, the
three `*-PfbCredential` cmdlets) plus two cmdlets that deliberately bypass
`Invoke-PfbApiRequest` and issue their REST call directly, because its `-Method`
`ValidateSet`/hashtable-only `-Body` cannot express what they need
(`Set-PfbPresetWorkload`, `Set-PfbWorkloadTag`) — and in
**526 of those 533, every one of those calls is a statement-level pipeline whose result is
emitted directly**, never captured into a variable or piped onward. (Only 7 capture or
post-process it, e.g. `Test-PfbConnection`, `Remove-PfbFileSystem`, `Get-PfbQuotaUser`.)
State the counting rule whenever you quote these: "calls it at all" and "emits its result
directly" are different questions with different answers, and an unqualified figure is what
made an earlier version of this paragraph wrong. Consequently a field the API *adds* to a
response reaches the caller automatically with no code change at all. There is nothing
to fix and therefore nothing to report. Only removals (a property callers may already
depend on that has gone away), renames, and unread envelope fields represent work.

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

**The one known, persistent failure.** When `tools/specs/` is locally cached past the
version `Data/PfbCapabilityMap.json` is pinned to, one real-manifest check in
`Tests/Build-PfbValueEnumMap.Tests.ps1` fails: it validates the value-enum map against
whatever spec version is newest on disk (`fb2.28`, as of this writing), not against the
2.27 version the capability map is deliberately pinned to (see item 2's `-MaxVersion` note
above). This is a pre-existing condition of the local dev environment, not a regression
from any task in this plan -- none of this plan's tasks touched value-enum extraction --
and it does not reproduce in CI, which always fetches specs fresh rather than relying on a
locally-cached, possibly-ahead-of-pin `tools/specs/`.

## CI

`.github/workflows/update-api-capability-map.yml` runs this pipeline weekly (and on
manual dispatch): re-fetches the full spec history into an ephemeral (non-committed)
cache, rebuilds `Data/PfbCapabilityMap.json`, and opens a PR if it changed — i.e. the
swagger index published a new REST version, or an existing endpoint gained new
parameters/fields. Requires the repository's Actions settings to permit workflow-created
pull requests. The `SSOT_API_KEY`/`SSOT_BASE_URI`/`SSOT_TOPIC_ID` secrets are optional —
when any are absent, the version-map step is skipped gracefully and only the capability
map updates (see item 3 above).

`Build-PfbValueEnumMap.ps1`, `Build-PfbFieldCmdletMap.ps1`, `Build-PfbResponseShapeMap.ps1`,
and `Build-PfbApiDriftReport.ps1` all run as part of the same weekly/dispatch job, right
after the capability map is rebuilt, so `Reports/PfbValueEnumMap.json`,
`Reports/PfbFieldCmdletMap.json`, `Reports/PfbApiDriftReport.json` (+ their Markdown
companions) and `Data/PfbResponseShapeMap.json` stay fresh alongside
`Data/PfbCapabilityMap.json`.

`Build-PfbResponseShapeMap.ps1` sits between `Build-PfbFieldCmdletMap.ps1` and
`Build-PfbApiDriftReport.ps1`, and that position is required in both directions. It must
come **after** the spec-fetch step, because the generator only walks `tools/specs/` and
never fetches anything itself — run before the fetch, it would build the map from whatever
the restored cache happened to hold. It must come **before** the drift-report step, because
the report reads `Data/PfbResponseShapeMap.json`; run after, CI would emit a report derived
from the stale committed map and then overwrite that map, leaving a report and a map that
disagree with no error to signal it. (If the file were ever absent entirely the report emits
an explicit "Not analysed" banner rather than a silently empty section, so a missing map is
at least visible — but a *stale* one is not, which is why the ordering rather than the
presence check is what protects the report.) The drift report's three response-shape counts
are also surfaced in the workflow's PR body via the `drift_summary` output.
