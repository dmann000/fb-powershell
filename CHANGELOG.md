# Changelog

All notable changes to `PureStorageFlashBladePowerShell` are documented in this file.

## [2.2.0] - 2026-07-22

API version-awareness plus seven documented-but-unexposed query-parameter enums.

### Added

- API capability check. A generated capability map (`Data/PfbCapabilityMap.json`)
  records the REST API version that introduced every endpoint, query parameter, and
  field; a REST-to-Purity//FB version map (`Data/PfbVersionMap.json`) makes the errors
  readable. `Invoke-PfbApiRequest` now runs a fail-fast check (`Assert-PfbApiCapability`)
  that rejects a call **before any HTTP request** when the connected array's version
  cannot support what is being asked, with a clear "upgrade the array or omit the
  unsupported option(s)" message. The check **fails safe**: a missing map, an unmatched
  endpoint, or an unresolvable version is a graceful no-op, never a false rejection.
- Seven query-parameter enums the REST API documents but the cmdlets never exposed
  (all additive, default to "not sent"): `Get-PfbArrayConnectionPerformanceReplication -Type`,
  `Get-PfbArrayPerformanceReplication -Type`, `Test-PfbSupport -TestType`,
  `Invoke-PfbNetworkTrace -Method`, `Get-PfbFileSystemSession -Protocol`,
  `Remove-PfbFileSystemSession -Protocol`, and `Get-PfbPolicyAllMember -MemberType`
  (an `ArgumentCompleter` rather than a `ValidateSet`, because that value set grew from
  4 to 5 at REST v2.17 and a hard set would block a value the array accepts).
- A reporting-only maintainer toolchain under `tools/` (value-enum extraction,
  field-to-cmdlet validation recommendations, and a combined API drift report). Nothing
  is wired into cmdlet validation yet; that is a deliberate follow-on decision.

### Fixed

- `Get-`/`Remove-PfbFileSystemSession`: removed the `-Id` parameter (the endpoint has no
  `ids` query parameter in any spec version, so it never worked), corrected `-Name` help
  (it filters by the session's own generated name, not a file system name), and made
  `-Protocol` its own mutually-exclusive parameter set. On `Remove-PfbFileSystemSession`,
  `-Protocol` is a genuine array-wide bulk-terminate mode and now requires an explicit
  `-Force` switch.

### Changed

- `scripts/build.ps1` and `scripts/Publish-Gallery.ps1` now bundle `Data/` into the
  built and branded packages, so the capability check is live for installed copies.

## [2.1.2] - 2026-07-20

API-drift cleanup: parameter-validation fixes and removal of three cmdlets that
never worked. Surfaced by the automated API drift report (module cross-checked
against the FlashBlade OpenAPI specs, REST 2.0-2.27).

### Removed

- Three cmdlets that modeled REST endpoints that **never existed** in any FlashBlade
  API version (2.0-2.27) and always returned HTTP 405: `Remove-PfbSession`,
  `New-PfbNetworkAccessPolicy`, `Remove-PfbNetworkAccessPolicy`. FlashBlade sessions
  are read-only (`puresession` is list-only) and network-access policies are a fixed
  built-in set (no create/delete) - only their *rules* are mutable, which is already
  covered by `New-`/`Remove-PfbNetworkAccessRule`. Because these cmdlets never
  succeeded, no working script depended on them.

### Fixed

- `Get-PfbArrayPerformance -Protocol`: added the documented `all` value (was missing
  from the ValidateSet, so a valid call was rejected client-side).
- `New-PfbAlertWatcher -MinimumSeverity`: removed the invalid `error` value (not a
  valid severity; the array would reject it).
- `New-PfbQuotaUser`: fixed a test that could hang on an interactive prompt when
  neither `-UserName` nor `-UserId` was supplied.

### Added

- `Get-PfbArraySpace -Type`: added a ValidateSet (`array`, `file-system`,
  `object-store`) matching the spec.

## [2.1.1] - 2026-07-15

Cross-platform and Windows PowerShell 5.1 fixes.

### Fixed

- SecureString password truncation on Linux/macOS: `Marshal.PtrToStringAuto` reads a
  BSTR with ANSI semantics on non-Windows platforms, truncating the password to its
  first character. Switched to `Marshal.PtrToStringBSTR` (correct and UTF-16 on every
  platform) in `New-PfbJwtToken` (encrypted-key JWT signing) and `Connect-PfbArray`
  (native username/password `/api/login`). Windows was never affected.
- Windows PowerShell 5.1 test crash: the encrypted-PKCS#8 test fixtures used
  `RSA.ExportEncryptedPkcs8PrivateKeyPem` / `PbeParameters`, which don't exist on .NET
  Framework 4.x. Those tests are now guarded on 5.1 (with a 5.1 regression test added);
  production code already surfaces a clear "requires PowerShell 7+" error.

### Changed

- Documented that `-PrivateKeyPassword` (encrypted private keys) requires PowerShell 7+
  (README and `New-PfbJwtToken` help).

## [2.1.0] - 2026-07-07

<!-- Pending merge via PR #9 (integration/justin-prs) at the time this entry was written;
     content sourced from that branch's PureStorageFlashBladePowerShell.psd1 ReleaseNotes.
     Date is PR #9's ModuleVersion-bump commit date, not a merge date. -->

Auth resilience + cmdlet correctness (integrates PRs #4-8), plus file-system
export and local directory-services fixes from field testing.

### Removed

- Four public cmdlets that never functioned (they POSTed to endpoints that
  reject POST, confirmed live as HTTP 400/405): `New-PfbFileSystemSnapshotPolicy`,
  `Get-PfbPolicyMember`, `New-PfbPolicyMember`, `Remove-PfbPolicyMember`. Because they
  were non-functional, no working script could have depended on them. Use the new
  `New-PfbPolicyFileSystem` / `Remove-PfbPolicyFileSystem` instead.

### Added

- `Connect-PfbArray`: username/password login now works on arrays below REST API 2.26
  via a Posh-SSH fallback (version-gated; native `/api/login` is used on 2.26+).
- `Connect-PfbArray`: automatic OAuth2 access-token refresh for the Certificate flow,
  so those sessions auto-reconnect like the other auth methods.
- `New-PfbPolicyFileSystem` / `Remove-PfbPolicyFileSystem` (attach/detach a policy to a
  file system via the correct `policies/file-systems` endpoint).
- `New-PfbQuotaUser`: `-UserId` as an alternative to `-UserName`.
- Local directory-services management (8 cmdlets under `directory-services/local/*`):
  `Get-`/`New-PfbLocalDirectoryService`, `Get-`/`New-`/`Remove-PfbLocalGroup`, and
  `Get-`/`New-`/`Remove-PfbLocalGroupMember`. `New-PfbLocalGroupMember` maps external
  (e.g. Active Directory) users into a local group, the supported path for granting
  those users SMB NTFS access.

### Fixed

- Auto-reconnect now triggers on HTTP 403 as well as 401 for every auth method
  (real FlashBlade arrays return 403, not 401, for a missing/invalid token).
- Pipeline-binding gaps across relationship/membership cmdlets (piped items were
  dropped or silently no-op'd); one API call per piped source. Affects, among others,
  `New-PfbFileSystemSnapshot`, `Remove-PfbFileSystemSnapshotPolicy`, `Test-PfbSaml2Idp`,
  `Test-PfbActiveDirectory`, and the `New-`/`Remove-`/`Get-PfbObjectStoreAccessPolicy{Role,User}`
  / `PfbObjectStoreUserAccessPolicy` cmdlets.
- `New-PfbQuotaUser` request shape; `Get-`/`Remove-`/`Update-PfbQuotaUser` query-param keys.
- `Connect-PfbArray` now forces TLS 1.2 on Windows PowerShell 5.1 (via new private helper
  `Set-PfbTlsProtocol`), which doesn't always default to it depending on OS/registry state,
  causing connections to a FlashBlade (which requires TLS 1.2+) to fail.
- `New-PfbFileSystemExport`: creation was broken — it sent an invalid `names` query
  parameter with an arbitrary body, which the array rejected. Now sends `member_names`
  (file system) and `policy_names` (export policy) as query parameters plus a proper
  `{ export_name, server, share_policy }` request body.

### Verified

- 139/139 Pester tests pass under pwsh 7 (1 skipped), plus live testing
  against real FlashBlade arrays on both sides of the REST 2.26 threshold.

## [2.0.5] - 2026-07-02

File-system demote support.

### Changed

- `Update-PfbFileSystem`: added `-DiscardNonSnapshottedData` switch (sends the
  `discard_non_snapshotted_data=true` query param) and a typed `-RequestedPromotionState`
  (`'promoted'` | `'demoted'`) parameter to support demoting a file system to a read-only
  replication target without dropping to raw REST. `-RequestedPromotionState` is mutually
  exclusive with `-Attributes` (throws if both supplied). Promote was already supported.

## [2.0.4] - 2026-06-17

Workloads + Presets + Data Eviction (+22 cmdlets, 93.3% API coverage).

Closes the three remaining 0%-coverage tags in the FlashBlade 2.26 REST API.

### Added

- Workloads (9): `Get/New/Update/Remove-PfbWorkload`, placement-recommendation
  read/create, and tag list/upsert/delete.
- Presets (5): `Get/New/Set/Update/Remove-PfbPresetWorkload`.
- Data Eviction (8): `Get/New/Update/Remove-PfbDataEvictionPolicy` plus file-system
  attach/detach/list and generic member listing.

### Changed

- API coverage 89.8% -> 93.3% (587 / 629 endpoint-method pairs). Cmdlet count 498 -> 520.

### Verified

- Live against Purity//FB 4.8.2: full Data Eviction CRUD lifecycle exercised end-to-end;
  read paths for all three tag groups confirmed.

## [2.0.3] - 2026-06-04

Real-AD test suite + HTML report generator.

### Added

- `Tests/SmbShareScript.AD.Tests.ps1`: 8 live tests with a real AD identity as
  lockdown principal; verifies NTFS via icacls actually lands on the share.
- `Tests/Generate-Reports.ps1`: produces a self-contained HTML bundle
  (index + per-suite HTML + NUnit XML + every markdown doc rendered).

### Verified

- Live: 29/29 Pester tests pass in ~32s.

## [2.0.2]

<!-- Date not recoverable from git history; no commit or tag references this version. -->


SMB share lockdown script + Update-PfbFileSystem expansion.

### Added

- `examples/New-LockdownFlashBladeShare.ps1` (lockdown -> NTFS -> production-flip)
- `Tests/SmbShareScript.Tests.ps1` (8 live tests against the lab)
- `Tests/API_COVERAGE.md` (spec gap analysis, ~84% coverage)
- `Tests/TEST_REPORT.md`

### Changed

- `Update-PfbFileSystem`: typed `-SmbSharePolicy`, `-SmbClientPolicy`, `-NfsExportPolicy`
  parameters (no more hashtable-only flipping for the lockdown workflow).

### Fixed

- Compound filter idempotency check on `/smb-share-policies/rules`: FB returns
  a count-only stub for `policy.name='x' and principal='y'`. Single-clause
  filter + client-side narrow is the workaround.

### Verified

- 21/21 Pester tests pass live against Purity//FB 4.8.2 / API 2.26 in ~28s.

## [2.0.1] - 2026-03-31

Posh-SSH dependency removed.

### Removed

- Posh-SSH dependency entirely. Username/password auth now uses native REST 2.x `/api/login`.

### Fixed

- `New-PfbNetworkInterface`: removed read-only `subnet` field from POST body (was returning
  "Invalid body parameter").
- `New-PfbFileSystem`: switch parameter name collision (`$smb`/`$Smb`) caused SwitchParameter
  cast errors.
- `New-PfbFileSystemSnapshot`: `-Suffix` was sent as query param, now correctly in request body.

### Added

- `New-PfbFileSystemReplicaLink` / `Remove-PfbFileSystemReplicaLink` (gap in v2.0.0).
- `New-PfbFileSystemSnapshot -Send` / `-Targets` for one-shot manual replication.
- `Tests/SmbWorkflow.E2E.Tests.ps1`: end-to-end SMB workflow suite including cross-array
  replication.
- `Tests/SMB_SHARE_WORKFLOW.md`: per-operation cmdlet mapping reference.

### Changed

- `Connect-PfbArray` default display hides `ApiToken` / `AuthToken` / `BearerToken`.
- `Invoke-PfbApiRequest` emits `Write-Verbose` for every endpoint hit.
- `New-PfbFileSystem` / `New-PfbServer` / `Update-PfbServer` / `New-PfbNetworkInterface`:
  typed parameters with mutually exclusive `-Attributes` parameter set.
- `Remove-PfbFileSystem`: added `-DeleteLinkOnEradication` for FSes that participate in a
  replica link.
- `Remove-Pfb{FileSystem,Bucket,Server,ObjectStoreUser,ObjectStoreAccount,Policy}`: reject
  `-Name '*'` / `'?'` / empty at parameter binding.

## [2.0.0] - 2026-03-31

Complete rewrite targeting FlashBlade REST API 2.x.

### Breaking changes from v1.x (PureFBModule)

- New module name: `PureStorageFlashBladePowerShell` (was `PureFBModule`)
- Session-based connection model: `Connect-PfbArray` / `Disconnect-PfbArray`
- REST API 2.x only (1.x is no longer targeted)
- Cmdlet naming follows `Verb-PfbNoun` pattern with `Get`/`New`/`Update`/`Remove` verbs

### Added

- 493 cmdlets covering 218 FlashBlade REST API 2.x endpoints
- `Connect-PfbArray` mirrors the FlashArray `Connect-Pfa2Array` experience
- Four authentication methods: ApiToken, Username/Password, PSCredential, Certificate
  (OAuth2/JWT)
- Native REST 2.x `/api/login` for username/password (no external SSH module required)
- Connection object exposes `.HttpEndpoint`, `.Username`, `.ApiToken`, `.RestApiVersion`
  (Pfa2-compatible)
- Modular architecture: `Public/` and `Private/` function layout
- PowerShell 5.1+ compatible
