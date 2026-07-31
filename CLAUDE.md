# fb-powershell

`dmann000/fb-powershell` (public GitHub repo, default branch `main`) -- a
PowerShell module ("PureStorage FlashBlade PowerShell Toolkit") for managing
Everpure (formerly Pure Storage) FlashBlade arrays via the REST API 2.x.
~526 cmdlets covering all FlashBlade REST 2.x endpoints, with a
`Connect-PfbArray` experience mirroring the FlashArray `PureStoragePowerShellSDK2`
module.

**Two names, on purpose:** the source module's own name is
`PureStorageFlashBladePowerShell` (repo/build/`Import-Module`-from-source
identity -- what the README's `Install-Module` instructions currently
reference). The package actually published to the PowerShell Gallery is
named **`EverpureFBModule`** (per `scripts/Publish-Gallery.ps1`): a separate
build step copies the built module, renames the `.psd1`/`.psm1`, assigns a
stable GUID (`dae38a9b-9885-40ea-a3e5-f7405038ab99`), and rebrands
Author/Company to "Don Mann, Justin Emerson, Mike Nelson" / "Everpure, Inc."
before publishing. Don't assume these are interchangeable names for the same
Gallery listing.

## Regenerate derived reports when cmdlet coverage changes

Any commit that changes which REST query/body parameters or endpoints a
`Public/` cmdlet covers must regenerate the derived `Reports/` artifacts in
the same commit -- otherwise they go stale relative to your own change, and
the drift-report invariant tests (`Tests/Build-PfbApiDriftReport.Tests.ps1`,
Task 8) will catch it later for whoever next merges `main`, instead of now:

```powershell
./tools/Build-PfbFieldCmdletMap.ps1   # must run first -- Build-PfbApiDriftReport.ps1 reads its output
./tools/Build-PfbApiDriftReport.ps1
```

Merge/rebase onto an up-to-date `main` *before* regenerating. `Build-PfbApiDriftReport.ps1`
reads most categories from the committed `Data/PfbCapabilityMap.json`, but one
category re-scans REST-version history straight from `tools/specs/` (gitignored,
a shared local cache) -- if that cache has picked up a newer spec version than
your branch's own committed capability-map baseline, regenerating against a
stale branch silently mixes an unrelated spec-version bump into your diff
instead of just your own change.
