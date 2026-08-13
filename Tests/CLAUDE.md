# Writing Pester tests in this repo

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

- **`MaxSkipped`** — a per-edition ceiling on skipped tests, catching a Describe
  that starts skipping. It is a ceiling *with headroom*, not a pin. Raise it
  deliberately, in a reviewed diff, and say why in the commit message.
- **`RequiredDescribes`** — names Describes that must appear in the result tree.
  Blocks that skip *gracefully* (their guard evaluates false at `BeforeAll`
  time) contribute neither a pass nor a skip, so a skip ceiling cannot see them
  disappear at all.

The two editions differ by a wide margin — every Describe in the tooling test
files carries `-Skip:($PSVersionTable.PSVersion.Major -lt 7)`, so the 5.1 leg
skips all of them by design. One shared ceiling would be either a permanent
false red on 5.1 or useless on 7.

One non-obvious way this gate reds without your branch changing: a
`pull_request` run tests the **merge** commit, so a ceiling measured before an
unrelated merge to `main` can go stale on its own. That is worth a red build,
not a suppression.

## Tooling tests need the spec cache

The tests under `Tests/` that exercise `tools/` read `tools/specs/` — a
gitignored local cache of the REST spec versions. When it is absent those
Describes skip gracefully, which reads as a healthy green summary while a large
slice of the suite never ran. A fresh clone or a new worktree starts without it,
so check the cache is populated before trusting a local pass.
