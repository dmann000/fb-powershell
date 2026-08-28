# Static analysis (PSScriptAnalyzer)

How PSScriptAnalyzer is configured in this repo, what CI enforces, and — more
importantly — what it deliberately does *not* enforce and why. If you have hit a red
`analyze` job, the rule that failed is gated on purpose and the reason is below.

Two files carry the policy:

| File | Holds |
|---|---|
| `PSScriptAnalyzerSettings.psd1` | the rule allowlist, and the per-rule rationale as comments |
| `.github/workflows/cross-platform-tests.yml` (`analyze` job) | what actually blocks a PR |

Per-rule reasoning lives beside the rule in the `.psd1`, not here, so it cannot drift
away from the thing it explains. This document covers the architecture: the shape of
the configuration and the decisions that are not attached to any single rule.

## An allowlist, never exclusions

`PSScriptAnalyzerSettings.psd1` names the rules that run (`IncludeRules`) and never
uses `ExcludeRules`.

That is not a style preference. The two settings are asymmetric:

- A caller's `-IncludeRule` is **unioned** with the settings file's `IncludeRules`.
  Both sets run.
- `ExcludeRules` **vetoes** a caller's `-IncludeRule` outright. A rule excluded in the
  settings file cannot be re-enabled from the command line.

So an exclusion-based configuration silently breaks ad-hoc checks: someone
investigating a specific rule gets a clean result and concludes the code is fine. An
allowlist has the opposite failure mode — it can only under-report, and it never lies
about a rule you explicitly asked for.

The consequence to know about, because it bites: **the union means a scoped check gets
the whole allowlist too.** A step that runs `-IncludeRule PSProvideCommentHelp` over
`Public/` also runs every allowlisted rule over `Public/`. Every gate in the `analyze`
job therefore filters its results by `RuleName` before counting. That filtering is
load-bearing, not tidiness — without it a gate expecting 0 sees 22 unrelated
records and fails for the wrong reason.

## CI, not a git hook

The analyzer's value here is repo-wide and low-frequency. A per-edit hook only ever
sees the file just written, so it would rescan single files and never observe the other
800-odd. Whole-repo coverage against one held baseline is the useful thing, and that is
a CI job.

There is a separate `PostToolUse` parse-check hook in the agent tooling; it does a
different job (syntax, per edit) and is not part of this regime.

## The gate is specific rules, not a severity

The obvious gate — fail if any `Error` appears — is **vacuous under this allowlist**.
The `Error` count is already zero, so such a gate would pass from day one and could
never catch anything. Severity is a property of the rule, not a measure of whether the
repo regressed.

Instead the job gates a small set of named rules that measure exactly zero, and
requires them to stay there:

| Guard | Scope | Note |
|---|---|---|
| `PSUseCompatibleSyntax` | all | targets 5.1 and 7.0 |
| `PSUseBOMForUnicodeEncodedFile` | all | the mojibake defect; see below |
| `PSAvoidAssignmentToAutomaticVariable` | all | |
| `PSUseApprovedVerbs` | all | the three `Sort-*` helpers are suppressed at the site, not excluded |
| `PSUseDeclaredVarsMoreThanAssignments` | all | gateable only because the 127 dead `$manifest` assignments were deleted first |
| `PSUseCompatibleCommands` | `Public/` only | see "Scoped, not repo-wide" |
| `PSProvideCommentHelp` | `Public/` only | needs `ExportedOnly = $false` to evaluate anything here |

Pre-existing warnings from the PSGallery preset rules are **reported but
non-blocking**. Nothing gates the warning count, so it can grow. That is a deliberate
choice to keep the gate meaningful rather than to freeze a number nobody has agreed
to; do not read a green build as evidence the warning count is holding.

### Every gate carries a control

A rule reporting zero because it is *inert* is indistinguishable from a rule reporting
zero because the code is clean. Each scoped gate therefore runs the same rule against
a directory where the finding count is known to be non-zero, in the same job, and
fails if that control comes back empty.

This is not hypothetical caution. Two rules in this configuration were originally
adopted on a zero that turned out to be vacuous: one because the sweep never reached
the files the rule applies to, one because the measurement was scoped to a directory
that happens to be clean. The controls exist because both mistakes were made.

## Two traps that make a sweep silently measure nothing

Both were found in this repo's own tooling. If you write a new analyzer invocation,
these are the two ways it will appear to work while checking nothing.

**1. `-Settings` must be passed explicitly.** Implicit discovery of
`PSScriptAnalyzerSettings.psd1` only looks in the immediate directory of `-Path`. A
sweep that loops over `Public/`, `Private/`, `Tests/`, `tools/`, `scripts/` never sees
a root-level settings file — no warning, no error, the file simply has no effect.

**2. The repo root must be scanned, as an explicit file list.**
`PureStorageFlashBladePowerShell.psd1` and `.psm1` live at the root, so a
five-directory loop never analyses them. That silently disables every manifest and
module rule, including `PSMissingModuleManifestField` — the one rule here that bears
directly on publication. Pass the root files individually rather than the root
directory, or add the root non-recursively: a recursive root scan re-analyses all five
directories and doubles every count.

A third, if you use `-EnableExit`: the exit code is the *count* of records, and it
truncates mod 256. Pair it with a rule or severity filter, or a sweep finding 276
issues exits 20 -- a number small enough to look like a real count. (276 is this
repo's own figure from before the dead-variable cleanup, not a hypothetical.)

## Rules deliberately not enabled

### Scoped, not repo-wide: `PSUseCompatibleCommands`

Configured, but gated on `Public/` only. Repo-wide it reports **21,889** findings, of
which `Tests/` accounts for 21,870 — the rule compares against profiles of *built-in*
commands, so it reports every Pester assertion (`The parameter 'Throw' is not
available for command 'Should'`). `Private/`'s handful are `ConvertFrom-Json -Depth`
calls inside a `$PSVersionTable.PSVersion.Major -ge 6` guard.

That last point generalises: **the compatibility rules cannot see guards.** Neither
`$PSVersionTable` branching nor `#Requires` is honoured, so correctly fenced
version-specific code is reported as incompatible. `PSUseCompatibleTypes` is excluded
for exactly this reason — its findings are all false positives, and adopting it would
penalise the fencing that supporting both 5.1 and 7 requires.

### The default-disabled rules stay off

PSScriptAnalyzer ships ten rules disabled by default. None is in the PSGallery list.
Force-enabling all ten across the five source directories produces **13,826** findings
(**9,001** excluding `PSUseConstrainedLanguageMode`). They are recorded with counts in
`PSScriptAnalyzerSettings.psd1` so their absence is not mistaken for an oversight.

Their zero in a default run means *never evaluated*, not *clean*. One is worth reading
twice: `PSUseConstrainedLanguageMode` at 4,825 is the largest single rule group
anywhere in this codebase, and it is not a formatting rule — it checks whether code
would run under PowerShell's Constrained Language Mode, which is irrelevant unless the
module is expected to work under an application-allowlisting policy such as
WDAC/AppLocker. Nothing here claims that.

If formatting enforcement is ever wanted, it should be an `Invoke-Formatter` run on a
deliberate commit, not a gate that reports thousands of findings against code nobody
is about to reformat.

### `PSUseSingularNouns` is kept, and it is noisy

It stays in the allowlist because it is part of the PSGallery preset, and dropping it
would make a file that claims to target that preset diverge from it. The cost is
accepted signal-to-noise on every run. The findings split into internal helpers and
exported cmdlets; renaming the internal ones would clear the rule but is a separate
sweep with call-site churn and is not planned.

## Adding a suppression

Suppress at the narrowest scope that works, with a `Justification`, and **always pass
two arguments**:

```powershell
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'Test fixture credential built from a literal; no other idiom exists.')]
param()
```

The empty second argument is load-bearing. `SuppressMessageAttribute` has **no
one-argument constructor**. PSScriptAnalyzer walks the AST and never constructs the
attribute, so the one-argument form suppresses cleanly in analysis — and then throws
`Cannot find an overload for ".ctor" and the argument count: "1"` the moment the file
is executed. An analyzer check is not sufficient evidence that a suppression is
correct; the file has to load.

Two more things, if you are suppressing in a `Tests/` file:

- A file-scope `param()` block in a Pester file can change discovery. Confirm the file
  still discovers and runs the same number of tests, not merely that Pester exits
  zero — `Invoke-Pester` reporting `total=0` is a pass-shaped result, because zero
  discovered means zero failed.
- Prefer a suppression at the site over an `ExcludeRules` entry. See the top of this
  document for why exclusions are worse than they look.

## Re-measuring

Deliberately no counts are quoted here except where the *magnitude* is the decision
(the 13,826 and the 21,889 above). Baselines move with every cleanup commit, and a
document asserting last month's totals is worse than one asserting none.

Even those two moved within a day of first being written down — 20,966 to 21,889 and
13,188 to 13,826 — which is why `PSScriptAnalyzerSettings.psd1` no longer carries any
count as a literal. Its generator measures each one at generation time and stamps the
file with the date and commit it measured against. Treat the figures in this document
the same way: they are the magnitude behind a decision, not a baseline to hold.

To re-measure, run the analyzer with the settings file passed explicitly and the root
included:

```powershell
$repo = <path to checkout>
$paths  = 'Public','Private','Tests','tools','scripts' | ForEach-Object { Join-Path $repo $_ }
$paths += Get-ChildItem -LiteralPath $repo -File |
          Where-Object Extension -in '.ps1','.psm1','.psd1' | ForEach-Object FullName

$all = foreach ($p in $paths) {
    Invoke-ScriptAnalyzer -Path $p -Recurse:(Test-Path -PathType Container $p) `
        -Settings (Join-Path $repo 'PSScriptAnalyzerSettings.psd1')
}
$all | Group-Object RuleName | Sort-Object Count -Descending | Format-Table Count, Name
```

`build/` is gitignored generated output and stays out of the sweep.

Before believing any zero from a run of your own, prove the analyzer is live in that
session — analyse a snippet with a known defect and confirm it reports:

```powershell
Invoke-ScriptAnalyzer -ScriptDefinition 'function Test-Probe { $x = 1 }' `
    -IncludeRule PSUseDeclaredVarsMoreThanAssignments -WhatIf:$false
```

`-WhatIf:$false` is not decoration. `Invoke-ScriptAnalyzer` declares
`SupportsShouldProcess`, so a `$WhatIfPreference` set by a *calling* script propagates
into it: it analyses nothing and returns an empty result with no error. Reading is not
a side effect, and a read must never be suppressed by `-WhatIf`.

## Why `PSUseDeclaredVarsMoreThanAssignments` is a gate at all

It is worth recording, because the rule spent a long time reporting 127 findings and
being useless. All 127 were the same dead `$manifest` / `$moduleRoot` boilerplate in
`Tests/`, left behind deliberately by `tools/Update-PfbTestModuleImport.ps1`. While
they stood, a genuinely dead variable in a *new* test file arrived as finding 128 of
127 known ones and was invisible, and no gate could be written at any threshold.

Deleting them is what converted the rule from noise into a signal, which is the
argument for having done it. Note also that this is the rule the job's liveness probe
uses, so its own guard is the one that cannot pass vacuously.

Two of the 127 needed hands rather than the script, and both are the interesting kind
of exception: one file assigns `$moduleRoot` twice, only one of which is dead; the
other's right-hand side is a call that creates the fixture the test depends on, so the
assignment went and the call stayed.
