# Writing Pester tests in this repo

## Loading the module

Every test file loads the module through the shared helper, not with
`Import-Module -Force`. Two lines, both **inside `BeforeAll`**:

```powershell
BeforeAll {
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule
}
```

The dot-source has to be inside `BeforeAll` too. File-scope code runs during
Pester's discovery phase, so a function dot-sourced at file scope is not in
scope by the time an `It` runs.

`Import-PfbTestModule` reuses the already-loaded module and resets the volatile
module-scope state instead of paying a fresh import per container; see
`Tests/PfbTestModule.ps1` for the reasoning. `Tests/TestModuleImportGuard.Tests.ps1`
enforces the pattern, and `tools/Update-PfbTestModuleImport.ps1` applies it
mechanically (`-WhatIf` first).

## Calling a private function

Anything under `Private/` that is **not** listed in `FunctionsToExport` in
`PureStorageFlashBladePowerShell.psd1` is a private function. After
`Import-Module -Force`, private functions are not exported into the test
file's scope -- calling one directly at the top level of a `Describe`/`It`
block fails with "command not recognized."

**Fix:** wrap only the actual invocation in
`InModuleScope PureStorageFlashBladePowerShell { <call> }`.

- `Mock -ModuleName PureStorageFlashBladePowerShell <Fn>` calls are fine
  *outside* `InModuleScope` -- only the real (non-mocked) call into a private
  function needs the wrapper.
- Calls to **public** (exported) functions like `Connect-PfbArray` never need
  this.

## `InModuleScope` does not close over outer-scope variables

`InModuleScope`'s script block does **not** close over local variables from
the enclosing `It`/`Context` block. Referencing an outer variable (e.g.
`$array` set earlier in the same `It`) inside
`InModuleScope PureStorageFlashBladePowerShell { Invoke-PfbApiRequest -Array $array ... }`
silently binds `$array` to `$null` inside the block, producing a
`ParameterBindingValidationException` that looks like a correct RED-phase
failure but is actually failing for the wrong reason.

**Fix:** pass the variable in explicitly via `-Parameters`:

```powershell
InModuleScope PureStorageFlashBladePowerShell -Parameters @{ array = $array } {
    Invoke-PfbApiRequest -Array $array ...
}
```

Only needed when the wrapped block references an outer-scope variable --
literal-argument calls don't need it.

## Running Pester non-interactively

Always invoke `pwsh` with **`-NonInteractive`**, not just `-NoProfile`, e.g.
`pwsh -NonInteractive -NoProfile -Command "Invoke-Pester ..."`. A cmdlet with
`[Parameter(Mandatory)]` invoked without that parameter throws immediately in
a non-interactive host, but *prompts and blocks* in an interactive one
(`-NoProfile` alone does not prevent this).

A related symptom worth recognising: a Pester run that stops with "Supply values
for the following parameters" is an unbound mandatory parameter, and the fault
is almost always in the test's invocation rather than in the cmdlet under test.

Destructive cmdlets need `-Confirm:$false` in tests. A `ConfirmImpact = 'High'`
cmdlet throws on `ShouldProcess` under `-NonInteractive` rather than proceeding.

## Run it the way CI does

```powershell
pwsh       -NonInteractive -NoProfile -Command "./scripts/Invoke-PfbCiPester.ps1 -Edition pwsh7"
powershell -NonInteractive -NoProfile -Command "./scripts/Invoke-PfbCiPester.ps1 -Edition winps51"
```

That wrapper is what the workflow calls, and it runs the coverage gate as well
as the tests. `Invoke-Pester` on its own skips the gate, so a run that looks
green locally can still red the build.

**`-Edition` selects the baseline, not the interpreter.** It chooses which
`Tests/coverage-baseline.psd1` block to apply; the interpreter is whichever host
is already running the script (in CI, the job's `shell:` key). Passing
`-Edition winps51` from pwsh 7 measures a 7 run against the 5.1 ceiling, which
is not a 5.1 run.

**Check both editions before pushing.** A test that passes under PowerShell 7
can fail under Windows PowerShell 5.1 for reasons that never surface in a 7-only
run, and CI gates four combinations (Windows 5.1, plus pwsh 7 on Windows, Linux
and macOS). Two editions is what a Windows box can cover; the platform dimension
is CI's job and is not worth simulating.

## The coverage gate: `Tests/coverage-baseline.psd1`

Two independent assertions guard against tests silently vanishing:

- **`ExpectedSkips`** — a per-edition, per-**file** expected skipped-test count.
  These are exact numbers, not ceilings. If a file's count moves in either
  direction the gate reds and names the file; update that file's line in the
  same diff and say why in the commit message. Only files that actually skip
  appear (19 of 199 on 5.1, 2 on pwsh 7), so it is a short list rather than a
  census.
- **`RequiredDescribes`** — names Describes that must appear in the result tree.
  Blocks that skip *gracefully* (their guard evaluates false at `BeforeAll`
  time) contribute neither a pass nor a skip, so a skip count cannot see them
  disappear at all.

Three rails come with the map, in `scripts/Assert-PfbTestCoverage.ps1`: no test
file may run **empty** (contributing neither an executed nor a skipped test), no
**undeclared** file may skip, and a declared file that stops running at all is a
violation rather than a stale entry to delete.

The two editions differ by a wide margin — every Describe in the tooling test
files carries `-Skip:($PSVersionTable.PSVersion.Major -lt 7)`, so the 5.1 leg
skips all of them by design. One shared map would be either a permanent false
red on 5.1 or useless on 7.

**Why exact and not a ceiling.** `ExpectedSkips` replaced a single global
`MaxSkipped` ceiling per edition (issue #132). That ceiling carried deliberate
headroom, and the headroom was the defect rather than the mitigation: it did not
prevent false reds, it converted an *attributable* red on the PR that moved the
number into an *unattributable* red on a later, innocent PR — and it hid a real
coverage regression of up to `ceiling - measured` tests, the issue-#63 failure
shape merely bounded in size. It happened once with exact arithmetic: a 5.1 run
measured 292 against a ceiling of 268, and six of the +40 belonged to #120 two
days earlier, which had slack and passed without touching the baseline. Do not
reintroduce headroom, globally or per file.

One non-obvious way this gate reds without your branch changing: a
`pull_request` run tests the **merge** commit, so a map measured before an
unrelated merge to `main` can go stale on its own. That is worth a red build,
not a suppression — and it is now attributed to the file the merge moved, which
is the whole improvement.

## Tooling tests need the spec cache

The tests under `Tests/` that exercise `tools/` read `tools/specs/` — a
gitignored local cache of the REST spec versions. When it is absent those
Describes skip gracefully, which reads as a healthy green summary while a large
slice of the suite never ran. A fresh clone or a new worktree starts without it,
so check the cache is populated before trusting a local pass.
