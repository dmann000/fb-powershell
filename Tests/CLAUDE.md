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
