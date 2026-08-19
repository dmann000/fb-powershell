#Requires -Version 5.1
<#
.SYNOPSIS
    Shared, idempotent module loader for the test suite.
.DESCRIPTION
    Dot-source this INSIDE a BeforeAll, then call Import-PfbTestModule. Do not
    dot-source at file scope: file-scope code runs during Pester's DISCOVERY phase,
    and a function left there is not in scope when the run phase executes an It.

    Why this exists: 162 of 187 containers used to call `Import-Module <manifest> -Force`
    in their BeforeAll, inside ONE host process. -Force discards and rebuilds the module,
    re-dot-sourcing 544 .ps1 files, so 161 of those rebuilds were of an already loaded,
    byte-identical module -- ~420-450 s of the Windows pwsh leg.

    Why -Force cannot simply be deleted: it was doing two pieces of real isolation work.
    (1) Module-scoped connection state and the redirectable $script:PfbModuleRoot must not
    leak between files -- so this helper resets them on every call. (2) The selector probe
    harness (tools/lib/PfbSelectorProbeHarness.ps1) shims Invoke-PfbApiRequest and
    Assert-PfbConnection inside module scope and NEVER restores them; it relies entirely on
    the next caller discarding the module. If a shimmed instance survived into later files,
    every later file would exercise a capture shim and still pass green.

    Containment for (2) is detection-based, not call-site-based, because the harness does
    its own `Import-Module -Force -PassThru` and thereby INSTALLS the instance later files
    inherit. A -Force import produces a NEW instance with no $script:PfbTestModulePrepared,
    so the next plain call here pays one rebuild and gets a clean module. That is
    order-independent and fail-closed.

    NOT Pester-dependent, on purpose: no InModuleScope, which exists only inside a Pester
    run and does not close over caller locals. Module scope is reached with
    `& $module { param($x) ... } $value`, passing values as arguments.

    5.1 CONSTRAINT: dot-sourced by files that run on the winps51 leg. No ternaries, no ??,
    no pipeline chain operators.

    -ManifestPath is almost never needed. $PSScriptRoot inside Import-PfbTestModule resolves
    to the DEFINING file's directory (Tests/), not the caller's -- measured by dot-sourcing
    this file from a script in %TEMP% on both editions, where the default manifest path still
    resolved and the import succeeded. So a call site in a Tests/ subdirectory can omit it.
#>

function ConvertTo-PfbTestPathKey {
    <#
        A comparison key for two paths that should name the same directory. Both sides are
        always built by this same function, so consistency is all that is required of it --
        it does not need to be a canonical filesystem identity.
    #>
    [CmdletBinding()]
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    $full = $Path
    try { $full = [System.IO.Path]::GetFullPath($Path) } catch { $full = $Path }
    return $full.TrimEnd([char]'\', [char]'/')
}

function Test-PfbTestModulePristine {
    <#
        $true when neither shimmable function carries the harness's capture markers.

        A POSITIVE match on the harness's own markers, mirroring the harness's reasoning at
        tools/lib/PfbSelectorProbeHarness.ps1:72 -- a reworded message in the REAL function
        cannot make this pass vacuously.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Module)

    $definitions = & $Module {
        $request = Get-Command -Name 'Invoke-PfbApiRequest' -ErrorAction SilentlyContinue
        $assert = Get-Command -Name 'Assert-PfbConnection' -ErrorAction SilentlyContinue
        $requestText = ''
        $assertText = ''
        if ($null -ne $request) { $requestText = [string]$request.Definition }
        if ($null -ne $assert) { $assertText = [string]$assert.Definition }
        return [PSCustomObject]@{ Request = $requestText; Assert = $assertText }
    }

    if ($definitions.Request -match 'PfbSelectorProbeCapture') { return $false }
    if ($definitions.Assert -match 'PfbSelectorProbeCaptureAssert') { return $false }
    return $true
}

function Import-PfbTestModule {
    [CmdletBinding()]
    param(
        [switch]$Fresh,
        [string]$ManifestPath
    )

    # StrictMode is inherited dynamically into a callee, so the first call in a process
    # would throw on `[int]$global:PfbTestModuleForceCount` if a caller has
    # `Set-StrictMode -Version Latest` in force. Initialise here rather than at
    # dot-source time: a bare assignment at dot-source time would ZERO the counters in
    # every one of the ~165 BeforeAll blocks that dot-sources this file, destroying the
    # instrument below.
    if (-not (Test-Path variable:global:PfbTestModuleForceCount)) { $global:PfbTestModuleForceCount = 0 }
    if (-not (Test-Path variable:global:PfbTestModuleCallCount)) { $global:PfbTestModuleCallCount = 0 }

    if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
        $ManifestPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'PureStorageFlashBladePowerShell.psd1'
    }
    $expectedBase = ConvertTo-PfbTestPathKey (Split-Path -Parent $ManifestPath)

    # Get-Module returns a COLLECTION, and returns more than one element whenever a
    # same-named module is also reachable from PSModulePath. `& $module { }` against a
    # two-element array fails, so filter then index -- never assign Get-Module bare.
    # $loaded is kept unfiltered so the log line below can report the base(s) that ARE
    # loaded, which is the one fact needed to diagnose a path-spelling mismatch.
    $loaded = @(Get-Module -Name 'PureStorageFlashBladePowerShell')
    $candidates = @($loaded |
        Where-Object { (ConvertTo-PfbTestPathKey $_.ModuleBase) -ieq $expectedBase })
    $module = $null
    if ($candidates.Count -gt 0) { $module = $candidates[0] }

    $loadedBases = 'none'
    if ($loaded.Count -gt 0) {
        $loadedBases = (@($loaded | ForEach-Object { "'" + $_.ModuleBase + "'" }) -join ', ')
    }

    $reason = $null
    if ($Fresh) {
        $reason = '-Fresh requested'
    }
    elseif ($null -eq $module) {
        # Two very different situations, and they MUST NOT share a reason string. The
        # first is healthy and happens exactly once per process. The second is the
        # fail-closed catastrophe this whole instrument exists to detect: the module IS
        # loaded, but at a spelling the key comparison rejects, so all ~165 containers
        # take the force path, every test stays green, and the entire saving is gone.
        # No path normalisation can rescue that case -- measured on this box, neither
        # [System.IO.Path]::GetFullPath nor (Get-Item ...).FullName resolves the
        # C:\Users\Justin junction to its real C:\Users\Justin Emerson spelling. Do NOT
        # "harden" the comparison with a resolution call and assume the risk is handled;
        # this log line is the only detector there is.
        if ($loaded.Count -gt 0) {
            $reason = 'loaded instance(s) exist but NONE at the expected base -- path spelling mismatch'
        }
        else {
            $reason = 'no loaded instance of that name'
        }
    }
    elseif (-not (& $module { $script:PfbTestModulePrepared })) {
        $reason = 'instance was force-imported by something other than this helper'
    }
    elseif (-not (Test-PfbTestModulePristine -Module $module)) {
        $reason = 'selector-probe shim detected in module scope'
    }

    if ($null -ne $reason) {
        $module = Import-Module -Name $ManifestPath -Force -PassThru -ErrorAction Stop
        # -Fresh deliberately withholds the marker: "I want a virgin module and I do not
        # promise to leave it clean", so the NEXT caller rebuilds. That is what makes
        # -Fresh safe downstream, not just for its own caller.
        if (-not $Fresh) { & $module { $script:PfbTestModulePrepared = $true } }

        # GLOBAL, not module scope: a counter kept in module scope is wiped by the very
        # -Force import it is counting, so it would read 1 forever and always look
        # perfect -- a broken instrument that reports success.
        $global:PfbTestModuleForceCount = 1 + [int]$global:PfbTestModuleForceCount

        # Write-Host, not Write-Verbose: this must appear in the CI job log. No assertion
        # over test OUTCOMES can detect the failure this instrument exists for, because
        # that failure fails closed and everything stays green.
        #
        # What a HEALTHY run looks like -- an enumeration of contributors, not a small
        # absolute number:
        #   1  the first container in the process to call the helper (the cold import);
        #   4  Tests/PfbTestModule.Tests.ps1 itself, which force-imports deliberately
        #      because it is the subject under test (-Fresh, the unmarked instance -Fresh
        #      leaves behind, the explicit external Import-Module -Force case, and the
        #      shim case);
        #   1  one recovery rebuild after each container that calls
        #      Initialize-PfbSelectorHarness -- today Tests/PfbSelectorProbeHarness.Tests.ps1
        #      and Tests/PfbPipelineSelectorRail.Tests.ps1, so 2 on pwsh7 and 0 on
        #      Windows PowerShell 5.1 where both are edition-gated;
        #   +1 per container the rewrite cannot convert.
        # That is roughly 7 on pwsh7 and 5 on 5.1 today.
        #
        # Every -Fresh call site costs TWO force imports, not one: its own, plus the next
        # plain caller's, because -Fresh deliberately withholds the prepared marker.
        # There are ZERO -Fresh call sites today (only this file's own test uses it).
        #
        # The GATE is therefore `FORCE < CALLS / 10`, not any small absolute number. The
        # exact healthy figure gets measured and pinned as a literal once the tree-wide
        # rewrite has landed; until then, a ratio is the only honest assertion.
        Write-Host ("PfbTestModule: full import #{0} ({1}); expected base '{2}'; loaded base(s) {3}" -f
            $global:PfbTestModuleForceCount, $reason, $expectedBase, $loadedBases)
    }

    $global:PfbTestModuleCallCount = 1 + [int]$global:PfbTestModuleCallCount

    # Reset on EVERY call, including straight after a fresh import, so there is exactly
    # one code path. $script:PfbModuleRoot is NOT a constant: 12 lines across 4 test files
    # redirect it at TestDrive:\ so the cache getters load synthetic JSON, and a dead
    # TestDrive: path left here silently nulls both caches for every later file.
    # The two JSON caches are deliberately NOT reset -- keeping them warm is part of the
    # speedup, and they are lazy read-only reads of committed data.
    # $script:PfbCachedCredential is NOT declared in the .psm1 preamble -- it is created on
    # first write by Set-PfbCredential / Get-PfbCredential and cleared by
    # Clear-PfbCredential. No test exercises those three cmdlets today, so the leak is
    # latent rather than active; reset it anyway. Without this, the first test that calls
    # Set-PfbCredential leaves a credential cached for every later file, and
    # Get-PfbCredential silently returns it instead of prompting.
    #
    # ...with ONE fail-safe exception. Dropping -Force means a synthetic JSON cache loaded
    # under a redirected $script:PfbModuleRoot now outlives its container. Four test files
    # redirect that root and all four restore it in an AfterEach today, but none of those
    # restores is asserted anywhere, so "the caches are real" would rest entirely on other
    # files' teardown remaining correct forever. Instead: invalidate the two caches only
    # when the INCOMING root proves they may be synthetic. On any happy path -- a plain
    # reuse, or the instant after a fresh import -- the incoming root already equals
    # $module.ModuleBase, this branch is not taken, and the caches stay warm exactly as
    # the design requires. If this comparison is ever mis-typed into always-true it would
    # silently clear the caches on every call and give back part of the speedup, so there
    # is a test asserting the branch is NOT taken on a plain reuse.
    $incomingRoot = & $module { $script:PfbModuleRoot }
    if ((ConvertTo-PfbTestPathKey $incomingRoot) -ine (ConvertTo-PfbTestPathKey $module.ModuleBase)) {
        & $module {
            $script:PfbCapabilityMap = $null
            $script:PfbVersionMap = $null
        }
    }

    & $module {
        param($root)
        $script:PfbDefaultArray = $null
        $script:PfbArrays = @{}
        $script:PfbCachedCredential = $null
        $script:PfbModuleRoot = $root
    } $module.ModuleBase

    return $module
}
