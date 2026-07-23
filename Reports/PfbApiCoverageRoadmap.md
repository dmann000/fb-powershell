# FlashBlade Cmdlet Coverage Roadmap

*A prioritized development guide for closing API-coverage gaps in the toolkit.*

Derived from `Reports/PfbApiDriftReport.{md,json}` (28 REST versions, 2.0 → 2.27) cross-referenced
against the current `Public/` cmdlet set (523 cmdlets across 24 functional folders). This is a
**planning artifact** — it groups the raw drift findings into functional *cmdlet families*, ranks
them, and records the rationale so future work can be picked up in priority order.

> **Scope boundary — only Fusion *context-switching* is out of scope.** A separate project owns
> exactly one thing: **how a cmdlet executes against a specific array in a Fusion fleet without adding
> a `-Context`/`context_names` parameter to every cmdlet's surface** (i.e. centralized context
> switching). Two parameters follow that boundary and are excluded here:
>
> - **`context_names`** (197 endpoints) — the fleet-context targeting parameter itself.
> - **`allow_errors`** (134 read endpoints) — partial-result tolerance whose real value is fleet
>   fan-out; being handled as a separate item within that same workstream.
>
> Everything else is **in scope for this roadmap**, explicitly including the **Fleet / Realm object
> management cmdlets (Family A)** — building and managing the fleet is this effort's job; only the
> *context-execution plumbing* is the other project's. Excluding the two params above removes the two
> largest line items in the raw drift report and materially shrinks the remaining param-gap work
> (see below).

## How to read this

The drift report surfaces three kinds of gap. They are **not** equally important, and they call for
very different work:

| Gap class | Count | Nature | Where it lives here |
|---|---|---|---|
| **Uncovered endpoints** | 117 | No cmdlet exists at all — genuinely missing capability | Families A–L below |
| **Substantive parameter gaps** | ~48 write cmdlets | Cmdlet *exists and ships*, but silently cannot set important body fields | Folded into each family + Sweep S4 |
| **Fusion `context_names` gap** | 197 endpoints | Fleet-context execution parameter | **Out of scope** — owned by the separate Fusion context-switching project |
| **`allow_errors` gap** | 134 read endpoints | Partial-result tolerance (fleet fan-out) | **Out of scope** — separate item in the Fusion workstream |
| **Other cross-cutting parameter gaps** | ~45 endpoints (after both external params removed) | Repetitive query params (`sort`, `limit`, `total_only`, …) | Sweep S3 (mechanical, not per-family) |
| **Not-verified endpoints** | 164 | Cmdlet already exists; the drift tool just couldn't confirm surface | **Out of scope** — verification, not new work |

Key insight: the raw report lists 282 "parameter gaps," but the two params owned by the Fusion
workstream — **`context_names` (197 endpoints)** and **`allow_errors` (134)** — account for most of
them. Excluding both **fully resolves 97 endpoints** (their only gap was one or both of those) and
shrinks the remaining work to **185 endpoints with a residual gap: 45 entirely cross-cutting query
params, and 140 with a substantive gap**. Of those, the ~48 write cmdlets that can't set real body
fields (e.g. `Update-PfbCertificate` is missing 25) are the ones that matter — treat them as bugs,
not enhancements.

---

## Priority summary (TL;DR)

| Rank | Item | Type | Effort | Why |
|---|---|---|---|---|
| **P0-1** | **Fix half-built writers** (Sweep S4) | Param fix | Low | Shipping cmdlets silently drop critical fields (WORM retention, cert body, NFS-rule semantics). Correctness bug, cheapest win. |
| **P0-2** | **User/Group Quota Policies** (Family B) | New family | High | Core NAS task, **0 cmdlets today**, entire 2.25 quota-policy subsystem missing. |
| **P1-3** | **Object-store / bucket-replication writes** (Family E) | New + param | Med | S3 is a primary FB workload; bucket replication is GET-only since 2.0 (can see, can't create). |
| **P1-4** | **Local directory services — users/groups** (Family C) | New family | Med | SMB/NFS-without-AD identity mgmt; users side has no create/read/delete. |
| **P2-5** | **RBAC / management-access-policies / admin lifecycle** (Family D) | New family | Med-High | Modern RBAC (2.26) + `POST/DELETE /admins` (can't create/delete admins today). ⚠ lab-test blocker. |
| **P2-6** | **Pagination / query-ergonomics sweep** (Sweep S3) | Param sweep | Low-Med | ~45 straggler GET cmdlets; brings them in line with the 160+ that already expose `-Limit`/`-Sort`/`-Filter`/`-TotalOnly`. |
| **P2-7** | **Fusion / Fleet / Realm net-new** (Family A) | New family | High | **In scope.** Strategic platform direction (2.25–2.27); realm-connections + topology-groups build the fleet. Only context-execution plumbing is external. |
| **P3-8** | Software / upgrade / support mgmt (Family F) | New family | Med | Upgrade & diagnostics automation (2.24/2.26). |
| **P3-9** | Certificates / KMIP writes (Family J) | New + param | Med | KMIP = data-at-rest encryption enrollment; `Update-PfbCertificate` overhaul. |
| **P3-10** | Data-eviction attach + FS junctions (Family G) | New family | Low-Med | Completes existing DataEviction folder; junction/nested mounts (2.25). |
| **P4-11** | TLS ↔ network-interface binding (Family H) | New family | Low | Bind TLS policies to interfaces (2.17). |
| **P4-12** | PATCH `/test` config-validation endpoints (Family I) | New | Low | Test-before-save for AD/SAML/dir-services. |
| **P5-13** | Batch operations (Family K) | New | Low | Perf optimizations of existing single-item ops. |
| **P5-14** | Misc singletons (Family L) | New | Low | login-banner, smtp PATCH, fs performance, etc. |

> **Removed vs. prior revision:** two cross-cutting param sweeps left this roadmap because the Fusion
> workstream owns them — `context_names` (formerly P1-5, 197 cmdlets) and `allow_errors` (formerly
> bundled into the P2-6 sweep, 134 cmdlets). Family A (Fleet/Realm object management) is **confirmed
> in scope** — the earlier "confirm ownership" gate is resolved.

**Recommended sequencing:** knock out **P0-1** first (pure correctness, low risk, no new plumbing),
then lead with the pure-capability families **B → E → C → D**, with **Family A** (Fleet/Realm) picked
up in the same P2 band. The remaining sweep (S3) is mechanical and can be interleaved / scripted
between family work.

---

## Cross-cutting parameter sweeps

These are **not** cmdlet families — they are repetitive parameter additions best done as coordinated,
scriptable batches.

### ~~Sweep S1 — `context_names` (Fusion fleet context)~~ — **OUT OF SCOPE (Fusion workstream)**
`context_names` scopes a request to a specific array within a Fusion fleet. It was formerly the
single largest line item in this report (197 endpoints), but **context-switching is owned by the
separate Fusion project** (whose sole charter is centralizing context execution *without* bolting a
`-Context` parameter onto every cmdlet). A validated hybrid design already exists on that side
(send-and-trust vs. local hard-throw — see the `fusion_context_names` design conclusion). Recorded
only for coordination.

### ~~Sweep S2 — `allow_errors`~~ — **OUT OF SCOPE (Fusion workstream)**
Partial-result tolerance on **read** queries (134 GET endpoints + 1 test-PATCH; **not available on
any bulk POST/PATCH/DELETE**, so it does *not* harden mutating cmdlets). Its real value is fleet
fan-out — return the reachable members' data plus an `errors` array instead of failing wholesale —
so it is being handled as a **separate item inside the Fusion workstream**, alongside `context_names`.
The thin single-array benefit (aggregation reads where a subset of sub-resources error) does not
justify sweeping it independently here.

### Sweep S3 — pagination / query ergonomics — `sort`, `limit`, `total_only`, `total_item_count` — **~45 straggler cmdlets**
A **consistency sweep**, not a new design direction: **~163 of 206 `Get-*` cmdlets already expose
`-Sort`, ~183 `-Limit`, ~185 `-Filter`, ~30 `-TotalOnly`.** S3 just brings the stragglers in line so
the surface is uniform. Per-parameter merit (see the design discussion) is uneven — prioritize
accordingly rather than treating all four equally:

| Param | Keep? | Why |
|---|---|---|
| **`-Limit`** | **Yes — load-bearing** | Cmdlets auto-paginate by default (fetch the *entire* collection); `Select-Object -First N` can't stop that. `-Limit` is the only lever to cap server work + wire transfer. |
| **`-TotalOnly`** | **Yes** | Server-side aggregation; no client-side equivalent (can't count without fetching everything). |
| **`-Sort`** | Consistency-only | Redundant with `Sort-Object` for a materialized set; earns its place *only* paired with `-Limit` for a cheap server-side top-N. Fill gaps for uniformity, no urgency. |
| **`-Filter`** | Consistency-only | Cheaper than pull-all + `Where-Object` on large collections; already on 185 cmdlets. |
| **`-TotalItemCount`** | Opportunistic | Net-new (0 cmdlets today); only where "how many, without the data" matters. |

> **Central vs. per-cmdlet — where the work actually lives.** A user-facing parameter *must* be
> declared in each cmdlet's `param()` block (PowerShell can't inject one from the choke point), so the
> parameter *surface* is an irreducible — but scriptable/generated — per-cmdlet sweep. The *value*,
> however, is central:
> - **Fix `-Limit` in `Invoke-PfbApiRequest` first (pure central, zero cmdlet edits).** The paginator
>   loops while a `continuation_token` exists with **no running-total guard against `$Limit`**, so
>   `-Limit 10` likely just sets page size and re-pages the whole collection. Add a
>   `$allItems.Count -ge $Limit` stop — one region, fixes every cmdlet that passes `limit` at once.
>   **Verify the fix live on FB-A** (page-size vs hard-cap server semantics).
> - **Optionally add a shared `$PSBoundParameters` → query-hashtable helper** (the existing
>   `ConvertTo-PfbQueryString` only stringifies an *already-built* hashtable). That collapses the
>   repeated `if ($Sort) { $q['sort'] = $Sort }` blocks into one call, so this sweep and every future
>   one touch one convention instead of N cmdlet bodies. The `param()` declarations still remain
>   per-cmdlet.

### Sweep S4 — substantive write-cmdlet body params (**~48 cmdlets — treat as bugs, P0**)
Existing `New-*`/`Update-*` cmdlets that cannot set real functional fields. Worst offenders:

| Cmdlet | Missing (real) | Impact |
|---|---|---|
| `Update-PfbCertificate` | 25 | Can barely update a certificate. |
| `New-PfbNfsExportRule` | 19 | Can't set access/anon/security/transport semantics of an NFS rule. |
| `Update-PfbArrayConnection` / `New-PfbArrayConnection` | 14 / 10 | Can't set encryption, throttle, CA cert group, replication addresses on array connections. |
| `Update-PfbTlsPolicy` | 14 | Can't set cipher lists, min TLS version, client-cert trust. |
| `Update-PfbWormPolicy` | 13 | Can't set retention (min/max/default), mode, retention-lock — **WORM is compliance-critical**. |
| `Update-PfbNode` | 12 | Node capacity/addressing fields. |
| `Update-PfbManagementAccessPolicy` / `Update-PfbQosPolicy` / `Update-PfbSshCaPolicy` / `Update-PfbSaml2Idp` | 10–11 each | Policy bodies largely unsettable. |
| `Update-PfbActiveDirectory` (9), `Update-PfbLifecycleRule` (9), `New-PfbNetworkAccessRule` (9), `New-PfbSmbClientRule` (9), `Update-PfbApiClient` (9), `Update-PfbStorageClassTieringPolicy` (9) | 9 each | Various. |

Full list of 48 in `PfbApiDriftReport.md` → "Parameter gaps" (filter to PATCH/POST rows). Fold each
row into its owning family when that family is worked, **or** do the whole sweep first as P0 since
these are correctness defects in shipping cmdlets.

> **Known related bugs (already recorded, still open):** `New-PfbQuotaUser` has the wrong body shape
> and no `-UserId` fallback; `New-PfbFileSystemSnapshotPolicy` POSTs a nonexistent endpoint. Address
> `New-PfbQuotaUser` alongside Family B.

---

## Cmdlet families (net-new capability)

Each family = a group of uncovered endpoints around one functional area. Ordered by priority tier.

### Family B — User & Group Quota Policies *(P0-2 · 19 endpoints · all 2.25 · new folder or extend `Quota/`)*
An entirely uncovered, self-contained subsystem — the modern policy-based quota model layered over
the legacy per-filesystem `Quota/` cmdlets. **Zero coverage today.** Quotas are a daily NAS-admin task.

- Policy CRUD: `user-group-quota-policies` GET/POST/PATCH/DELETE (+ `/rules` CRUD, `/file-systems`, `/members`)
- Attachment: `file-systems/user-group-quota-policies` GET/POST/DELETE
- Reporting reads: `file-system-group-quotas`, `file-system-user-quotas`, `file-systems/groups`, `file-systems/users` (GET)

Proposed cmdlets: `Get/New/Set/Remove-PfbUserGroupQuotaPolicy`, `*-PfbUserGroupQuotaPolicyRule`,
`Get-PfbFileSystemUserQuota`, `Get-PfbFileSystemGroupQuota`, plus attach/detach verbs.
**Also fix `New-PfbQuotaUser` here.**

### Family A — Fusion / Fleet / Realm management *(P2-7 · 18 endpoints · 2.25–2.27 · new `Fleet/` + `Realm/`)*
The platform's strategic direction, and **in scope for this effort**. Partially seeded
(`Get-PfbFleet`, `Get-PfbFleetMember`, `Get-PfbRealm` exist) but the connective tissue is missing.

> ✅ **Scope confirmed — in scope.** These endpoints *manage fleet/realm objects* (building the
> fleet), which is this effort's job. The separate Fusion project owns *only* the context-execution
> plumbing — how any cmdlet runs against a chosen array without a `-Context` parameter on its surface
> — not the object-management cmdlets here. The two overlap only at runtime (these cmdlets will
> inherit that centralized context mechanism once it ships); they do not overlap in ownership.

- `realm-connections` GET/POST/DELETE (+ `/connection-key`) — join realms across arrays
- `remote-realms` GET
- `topology-groups` GET/POST/PATCH/DELETE (+ `/arrays`, `/members`) — fleet topology
- `PATCH /remote-arrays`, `POST /fleets/members/batch`, `GET /storage-classes/members`

⚠ **Test note:** management-access-policies RBAC operations 403 in the lab regardless of account —
this previously blocked fleet/context testing. Confirm a working test path before committing.

### Family C — Local Directory Services (local users & groups) *(P1-4 · 10 endpoints · 2.24 · extend `DirectoryService/`)*
Identity management for SMB/NFS environments without AD. Partially covered (`Get-PfbLocalGroup`
exists); the **users** side has no create/read/delete at all.

- `directory-services/local/users` GET/POST/DELETE/PATCH (+ `/members` GET/POST/DELETE)
- `directory-services/local/groups` PATCH; `directory-services/local/directory-services` DELETE/PATCH

Proposed: `Get/New/Set/Remove-PfbLocalUser`, `*-PfbLocalUserMember`, `Set-PfbLocalGroup`,
`Set/Remove-PfbLocalDirectoryService`.

### Family D — RBAC / Management Access & Authentication Policies + admin lifecycle *(P2-5 · 27 endpoints · 2.15–2.26 · extend `Admin/`)*
Two related auth subsystems plus a notable gap:

- **`POST /admins` + `DELETE /admins` (2.15)** — you currently **cannot create or delete admin
  accounts** via cmdlet. Security-relevant, oldest gap in this family.
- **management-access-policies roles/permissions/rules (2.26)** — modern RBAC CRUD.
- **management-authentication-policies (2.22)** — full CRUD + members + admins/arrays scoping.

⚠ Same RBAC 403 lab blocker as Family A applies to the management-access-policies subset.

### Family E — Object-store / bucket write operations *(P1-3 · 8 endpoints · 2.0–2.17 · extend `Bucket/` + `ObjectStore/`)*
S3/object is a primary FlashBlade workload and these are long-standing holes:

- **`bucket-replica-links` POST/PATCH/DELETE (2.0)** — GET-only since 2.0: you can *see* object
  replication but not *create* it. Highest-value item in this family.
- `PATCH object-store-access-keys` (2.0), `PATCH object-store-accounts` (2.8),
  `PATCH object-store-access-policies` (2.2) — can create but not modify.
- `object-store-roles/object-store-trust-policies` upload/download (2.17) — trust-policy doc transfer.

### Family F — Software / Upgrade / Support management *(P3-8 · 7 endpoints · 2.24–2.26 · extend `Support/`)*
API-driven upgrade orchestration and diagnostics — useful for fleet automation.

- `software-bundle` GET/POST, `software-patches` GET/POST (2.24)
- `support-diagnostics/settings` GET/PATCH (2.24), `support/system-manifest` GET (2.26)

### Family J — Certificates / KMIP *(P3-9 · 4 endpoints · 2.0–2.1 · extend `Certificate/`)*
- `certificate-groups/certificates` POST/DELETE (2.0) — attach/detach certs to a group.
- `POST/DELETE /kmip` (2.1) — register/remove KMIP servers (data-at-rest encryption enrollment).
- Pair with the `Update-PfbCertificate` 25-param fix from Sweep S4.

### Family G — Data-eviction attachment & File-system junctions *(P3-10 · 6 endpoints · 2.21/2.25 · extend `DataEviction/` + `FileSystem/`)*
- `file-systems/data-eviction-policies` GET/POST/DELETE (2.21) — completes the existing DataEviction folder (attach policies to filesystems).
- `file-system-junctions` GET/POST/DELETE (2.25) — nested/junction mount points.

### Family H — TLS ↔ network-interface binding *(P4-11 · 4 endpoints · 2.17 · extend `Network/`)*
- `tls-policies/network-interfaces` GET/POST/DELETE — bind TLS policies to interfaces.
- `PATCH /file-system-replica-links` — modify replica-link config (currently create/delete only).

### Family I — Config-validation (`/test`) PATCH endpoints *(P4-12 · 3 endpoints · 2.0–2.27)*
Test-a-config-before-saving variants. GET `/test` cmdlets exist; these PATCH variants are uncovered.
- `PATCH directory-services/test` (2.0), `PATCH sso/saml2/idps/test` (2.16), `PATCH active-directory/test` (2.27)

### Family K — Batch operations *(P5-13 · 4 endpoints · 2.18–2.27)*
Throughput optimizations of existing single-item ops; build only if bulk workflows demand it.
- `POST nodes/batch`, `POST resource-accesses/batch`, `PUT workloads/tags/batch`, `POST fleets/members/batch`

### Family L — Misc singletons *(P5-14 · 8 endpoints · 2.0–2.23)*
No shared theme; pick up opportunistically.
- `GET /login-banner` (2.0), `PATCH /smtp-servers` (2.0), `GET /file-systems/performance` (2.0),
  `DELETE /policies/file-system-snapshots` (2.0), `GET /policies/members` (2.0),
  `GET /file-systems/policies-all` (2.3), `PUT /presets/workload` (2.23),
  `GET /resiliency-groups/members` (2.23)

---

## Notes & caveats

- **Currency signal:** endpoint introduction version is used as a relevance proxy — 2.25–2.27 items
  map to current Purity//FB 4.8.x and are most likely to be requested by current users. But a few
  *old* gaps (bucket-replica-link writes, `POST/DELETE admins`, both 2.0/2.15) are high-value despite
  their age precisely because they've been missing for so long.
- **Not-verified (164):** these already have cmdlets; the drift tool just couldn't resolve their
  surface. They are a **verification/testing** task, not new development, and are intentionally
  excluded from this roadmap.
- **Fusion workstream boundary:** the separate Fusion project owns exactly one thing — centralized
  context switching (running a cmdlet against a chosen fleet array without a `-Context` parameter on
  every surface). Two params follow it and are excluded here: **`context_names`** (197 endpoints) and
  **`allow_errors`** (134 read endpoints; being handled as a separate item in that workstream).
  Excluding both resolves 97 param-gap endpoints outright. **Family A (fleet/realm object management)
  is in scope for this roadmap** — only the context-execution plumbing is external.
- **Testing blocker:** management-access-policies POST/PATCH/DELETE return 403 in the lab regardless
  of account/params — factor this into any Family A/D estimate.
- **Live-test discipline:** every branch should be live-tested against a lab array (FB-A) before
  PR, and any PR against the upstream fork should be summarized to the maintainer per standing
  process. New quota/policy cmdlets especially warrant live verification given the two known
  pre-existing body-shape bugs.
- **Regenerate the source data** with `./tools/Build-PfbApiDriftReport.ps1` (see `Reports/README.md`).
  Pass `-SinceVersion` to isolate a single release's additions.
