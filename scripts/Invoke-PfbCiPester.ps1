<#
.SYNOPSIS
    Runs the full Pester suite and the issue-#63 coverage gate.
.DESCRIPTION
    Extracted from YAML so this logic is not maintained in triplicate across
    cross-platform-tests.yml (twice) and update-api-capability-map.yml (once). Follows the
    pattern already established by scripts/Publish-Gallery.ps1, which publish-to-gallery.yml
    calls the same way.

    Why a repo script rather than a composite action: this is lintable by PSScriptAnalyzer,
    diffable, testable, free of ${{ }} escaping hazards, and runnable outside GitHub Actions.
    A composite action would add a second indirection layer and buy only the `shell:`
    selection, which is one YAML line per leg regardless.

    Why update-api-capability-map.yml cannot simply `workflow_call` cross-platform-tests.yml
    instead: a reusable workflow runs on a FRESH runner with a FRESH checkout, so it would
    test the committed Data/ and Reports/, not the ones that job just regenerated -- which is
    the entire reason its test step is inline. A script runs in the caller's workspace.

    RUNS ANYWHERE, deliberately. This is the full aggregate suite, and running it as a task's
    own completion check is a known failure mode for an AGENT specifically: the suite exceeds
    the 600s tool-call cap, and a backgrounded run is indistinguishable from a dead one. But
    "run exactly what CI runs before I push" is a legitimate human use, so that restriction is
    enforced by a PreToolUse hook -- which gates agent tool calls and never sees a human's
    terminal -- rather than baked in here, where it would tax the legitimate caller in order
    to constrain a different one. Agents: use the run-pester-tests skill's
    Invoke-ScopedPester.ps1 instead.

    5.1 CONSTRAINT: this runs under Windows PowerShell 5.1 as well as pwsh 7. No ternaries,
    no ??, no ConvertFrom-Json -Depth.
.PARAMETER Edition
    Which Tests/coverage-baseline.psd1 block to apply: 'pwsh7' or 'winps51'. This selects the
    BASELINE, not the interpreter -- the interpreter is whichever host is already running this
    script, chosen by the workflow's `shell:` key.
.EXAMPLE
    ./scripts/Invoke-PfbCiPester.ps1 -Edition pwsh7
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('pwsh7', 'winps51')][string]$Edition
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot
try {
    Import-Module Pester -MinimumVersion 5.0 -Force
    # Posh-SSH is imported because Pester can only mock a resolvable command -- see
    # .github/actions/install-test-modules/action.yml for why it is a test dependency.
    Import-Module Posh-SSH -Force

    $cfg = New-PesterConfiguration
    $cfg.Run.Path = 'Tests'
    # Run.Exit stays $false deliberately: it terminates the process on failure, which would
    # skip the coverage gate below. The explicit exit at the end preserves the same red build.
    $cfg.Run.Exit = $false
    $cfg.Run.PassThru = $true
    $cfg.Output.Verbosity = 'Detailed'

    $result = Invoke-Pester -Configuration $cfg

    # Import-PfbTestModule (Tests/PfbTestModule.ps1) counts every call it receives and every
    # time it had to fall back to a real force-import. Both counters are globals set in THIS
    # process: Run.Exit is $false above, so nothing has terminated yet and they are in scope
    # here. Emitted unconditionally so the numbers appear in every CI job log whether or not
    # the gate below trips -- they are the only visibility into whether the shared-import
    # optimisation is actually working.
    #
    # Why the gate is a RATIO and not a small absolute number: the healthy force count is an
    # enumeration of legitimate contributors -- one cold import at the start of the run, about
    # four from Tests/PfbTestModule.Tests.ps1, which force-imports deliberately because the
    # force path IS its subject, and one recovery per selector-harness container that installs
    # an unmarked module instance. That total moves whenever such a file is added, so a tight
    # absolute pin would red on ordinary maintenance. Meanwhile the failure this exists to
    # catch is not a small drift: the helper's module-identity check fails CLOSED, so if the
    # ModuleBase path spelling ever stops matching, every container force-imports and FORCE
    # rises to roughly equal CALLS while the suite stays green. An order-of-magnitude gate
    # separates those two regimes cleanly and still tolerates a new harness file.
    $forceCount = 0
    $callCount = 0
    if (Test-Path variable:global:PfbTestModuleForceCount) {
        $forceCount = [int]$global:PfbTestModuleForceCount
    }
    if (Test-Path variable:global:PfbTestModuleCallCount) {
        $callCount = [int]$global:PfbTestModuleCallCount
    }
    Write-Host ("Import-PfbTestModule: calls={0} force-imports={1}" -f $callCount, $forceCount)

    $importGateFailed = $false
    if ($callCount -le 0) {
        # Zero calls is not a quiet pass. In a full-suite run it means no test file loaded the
        # module through the helper at all, so the ratio would be vacuously satisfied rather
        # than met -- and it also guards the division below.
        $importGateFailed = $true
        Write-Host ('Import-PfbTestModule force-import gate FAILED: the helper was never ' +
            'called in this run, so the force-import ratio cannot be evaluated. Either the ' +
            'suite no longer loads the module through Tests/PfbTestModule.ps1, or the run ' +
            'did not execute the tests it was supposed to.')
    }
    elseif ($forceCount -ge ($callCount / 10)) {
        $importGateFailed = $true
        $importGateMessage = 'Import-PfbTestModule force-import gate FAILED: {0} force-imports ' +
            'out of {1} calls; the limit is fewer than {2}. Force-imports at that scale mean ' +
            "the helper's module-identity check is failing closed and the suite is paying the " +
            'full per-container import cost. Check the ModuleBase path spelling the helper ' +
            'compares against.'
        Write-Host ($importGateMessage -f $forceCount, $callCount, ($callCount / 10))
    }

    # Ordering is load-bearing: the coverage gate runs BEFORE the failure exit, so a run that
    # both fails tests and lost coverage reports both problems rather than only the first.
    $gateFailed = $false
    try {
        & (Join-Path $PSScriptRoot 'Assert-PfbTestCoverage.ps1') -Result $result -Edition $Edition
    }
    catch {
        $gateFailed = $true
        Write-Host $_.Exception.Message
    }

    if ($result.FailedCount -gt 0 -or $gateFailed -or $importGateFailed) { exit 1 }
    exit 0
}
finally {
    Pop-Location
}
