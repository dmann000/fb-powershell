@{
    # Issue #63: CI reported success while roughly 23% of the suite silently skipped, because
    # the tooling tests gate themselves on the gitignored tools/specs/ build cache. Restoring
    # the cache fixes today's hole; this file is what makes the NEXT one a red build.
    #
    # Two independent assertions, because either alone has a gap:
    #
    #   ExpectedSkips     an EXACT skipped-test count per test file. Catches a file that starts
    #                     or stops reporting skips, and says which file.
    #   RequiredDescribes catches a Describe that vanishes from the result tree entirely.
    #                     These blocks skip GRACEFULLY: when their guard evaluates false at
    #                     BeforeAll time, or the file is filtered out of a run, they contribute
    #                     NEITHER a skip NOR a pass. A skip count cannot see that, and a
    #                     green summary is then indistinguishable from a silently-absent
    #                     assertion -- the same failure shape as #63, one level down.
    #
    # ExpectedSkips REPLACED a single global MaxSkipped ceiling per edition (issue #132). The
    # ceiling carried deliberate headroom, and that headroom was the defect rather than the
    # mitigation. It did not prevent false reds; it converted an ATTRIBUTABLE red on the PR
    # that moved the number into an UNATTRIBUTABLE red on a later, innocent PR, and it hid a
    # real coverage regression of up to (ceiling - measured) tests -- the #63 failure shape,
    # merely bounded in size.
    #
    # That is not hypothetical and the arithmetic was exact. A 5.1 run measured 292 against a
    # ceiling of 268. Of the +40, six belonged to #120 two days EARLIER, which had slack and
    # passed without touching this file; the next branch across the line was billed for all
    # forty, including those six. The history of raises left in the winps51 block below is the
    # audit trail of the same mechanism firing repeatedly.
    #
    # So these numbers are PINS, not ceilings. Any movement -- up or down -- reds the build,
    # names the file, and is fixed by editing that file's line in the same diff that moved it.
    # Do not reintroduce headroom, per-file or global; a per-file ceiling would be the same
    # defect wearing a smaller hat.
    #
    # Three rails come with the map, in scripts/Assert-PfbTestCoverage.ps1: no test file may
    # run EMPTY (contributing neither an executed nor a skipped test -- the #63 shape below
    # the granularity RequiredDescribes can reach), no UNDECLARED file may skip, and a declared
    # file that stops running at all is a violation rather than a stale entry to delete.
    #
    # Only files that actually skip appear here -- 19 of 199 on 5.1, 2 on pwsh 7 -- so this is
    # a short list, not a per-file census. Attribution is by leaf file name, which is sound
    # because Tests/ is flat and no two *.Tests.ps1 files share a leaf; the gate fails loudly
    # if that ever stops being true.
    #
    # The two editions differ by design and by a wide margin: every Describe in the tooling
    # test files carries -Skip:($PSVersionTable.PSVersion.Major -lt 7), so the 5.1 leg skips
    # all of them. A single shared map would be either a permanent false red on 5.1 or
    # useless on 7.
    pwsh7   = @{
        # Seeded from run 32392093324 on main@98c7a16 (2026-08-20): 3328 passed / 0 failed /
        # 2 skipped, and the same two files on all three pwsh legs -- ubuntu-latest,
        # windows-latest and macos-latest agreed exactly, which is what makes one shared pwsh7
        # map correct rather than a windows-only measurement generalised.
        #
        # These two are ordinary per-test -Skip: guards on platform-specific behaviour, not
        # the PS7 gating that dominates the winps51 block. Total: 2.
        ExpectedSkips     = @{
            'New-PfbJwtToken.Tests.ps1'    = 1
            'Set-PfbTlsProtocol.Tests.ps1' = 1
        }
        RequiredDescribes = @(
            # Ungated -- these run on every leg and are the #63 regression guards themselves.
            'Committed drift report (REGRESSION guard, no spec cache required)'
            'Committed drift report: annotations and summary fields survived generation'
            'ConvertTo-PfbRepoRelativePath (REGRESSION guard for issue #63: runs with no spec cache, on every edition)'
            # Spec-cache dependent -- these are the blocks that silently skipped in CI before
            # the prepare-specs job existed. Listing them here is what proves the cache
            # actually arrived, rather than inferring it from a healthy-looking skip count.
            'Build-PfbApiDriftReport (real generated artifacts, skips gracefully if absent)'
            'Build-PfbApiDriftReport (Task 8: regression canaries + spot-checks against the real generated report, skips gracefully if absent)'
            'Build-PfbFieldCmdletMap (real generated artifacts, skips gracefully if absent)'
            'Real committed capability map (skips gracefully if not yet generated)'
            'Real committed value-enum map (skips gracefully if not yet generated)'
            'Task 6 real-data invariants (systemic gaps + convention strength, skips gracefully if the real capability map is absent)'
            # Issue #102 -- ungated capability guards over the committed map. They read
            # Data/PfbCapabilityMap.json (tracked, not the gitignored spec cache) and have no
            # skip path by design, so they must contribute executed tests on every leg.
            '-TotalOnly is exposed only where the published spec declares total_only (#102)'
            'the 26 cmdlets corrected by #102 no longer expose -TotalOnly'
            'the 12 cmdlets whose endpoints do declare total_only keep the switch (#102 is not a blanket removal)'
            # Ungated for the same reason: it parses tracked .ps1 files via the AST, so it needs
            # neither the spec cache nor the generated manifest and has no skip path.
            'Build-PfbValueEnumMap: hand-written ValidateSet citations'
            # Test-module import guard. Ungated -- pure AST over tracked .ps1 files, so it
            # needs neither the spec cache nor PowerShell 7 and has no skip path. Listed
            # under winps51 too, for that reason.
            'Test-module import guard (AST, no spec cache required, every edition)'
            # Issue #90 pipeline-selector rails. Both are PS7-gated, so they belong to this
            # block and not to winps51. Rail B is the one this list exists for: it skips
            # GRACEFULLY when tools/specs is absent, the exact #63 shape a skip ceiling cannot
            # see, since a cacheless runner leaves it contributing neither a pass nor a skip.
            'Rail A - no unwaived selector coercion'
            'Rail B - committed map matches regeneration'
            # Dead-key gate. The COMMITTED guard is ungated and so is listed under winps51
            # too; the two halves of the generator gate are PS7-only (the generator carries
            # `#Requires -Version 7.0`), so like the issue-#90 rails above they belong to this
            # block alone -- requiring them on 5.1 would be a permanent false red. They are
            # split on a dependency boundary: the first needs the real tools/specs cache, the
            # second builds its own fixture and reads no cache at all, so a broken fixture
            # cannot make the real generator look broken.
            'Committed dead-key report (REGRESSION guard, no spec cache required)'
            'Build-PfbDeadKeyReport regeneration (real spec cache required, PS7 only)'
            'Build-PfbDeadKeyReport classification (synthetic fixture, no spec cache, PS7 only)'
            # Issue #121 empty-pipeline guards. Listed under BOTH editions: neither block
            # carries a PS7 gate, neither reads the spec cache, and the generator deliberately
            # declares `#Requires -Version 5.1` rather than 7.0 so its real-tree check runs on
            # either leg. Both therefore contribute executed tests everywhere.
            #
            # These two are the reason this list matters more than MaxSkipped for #121. The
            # coverage block re-derives the qualifying population from the AST of the tracked
            # Public/*.ps1 files and asserts all 130 carry a guard; the real-tree block asserts
            # the generator is at a fixed point. Both are pure gain-nothing-lose-everything
            # rails: break a guard and they go red, but DELETE either file and a skip ceiling
            # sees nothing, because a file that never runs contributes neither a skip nor a
            # pass. That is the issue-#63 shape one level down, which is what this list exists
            # to catch.
            'Empty-pipeline guard coverage'
            'Update-PfbEmptyPipelineGuards - real tree'
            # Issue #112 contextScope version tripwire. PS7-gated (it parses every cached spec
            # with ConvertFrom-Json -Depth), so it belongs to this block alone. It is exactly
            # what this list exists for: it is VACUOUSLY green today -- every endpoint declaring
            # a domains override declares it in one version only -- so a skip ceiling could never
            # tell it from a block that stopped running. Its synthetic sibling is listed under
            # both editions.
            'contextScope stability across every cached REST version (issue #112)'
            'Get-PfbContextScopeVersionFinding, against synthetic declarations'
        )
    }
    winps51 = @{
        # ---------------------------------------------------------------------------------
        # RETAINED HISTORY of the MaxSkipped ceiling this block used to carry, kept verbatim
        # because it is the evidence for issue #132 rather than a record of how to maintain
        # anything. Read it as an audit trail: five deliberate raises, and by the last one the
        # raise notes are visibly diagnosing the mechanism instead of the branches -- "268 was
        # already stale against main before either branch existed". The numbers below are dead;
        # nothing reads MaxSkipped any more. The live gate is the ExpectedSkips map after it.
        # ---------------------------------------------------------------------------------
        #
        # Re-measured 190 on run 31670025630 (windows-latest, Windows PowerShell 5.1): 1818
        # passed / 0 failed / 190 skipped. The gap versus pwsh7's 2 is the PS7-gated tooling
        # Describes, skipping exactly as designed -- not a defect.
        #
        # RAISED 185 -> 206, deliberately, for the reason this file says to raise it for. The
        # original 185 was measured against a main that predated PR #98 (Fusion context Phase
        # 0). #98 added 21 PS7-gated It blocks -- 8 in
        # Build-PfbCapabilityMap.ContextScopeDrift.Tests.ps1, 9 in Build-PfbCapabilityMap.Tests.ps1,
        # 4 in PfbSpecTools.ContextScope.Tests.ps1 -- and the observed 5.1 skip count moved
        # 169 -> 190, exactly +21. They RUN on 7 (pwsh7 stayed at 2 skipped, 2006 passed), so
        # this is the PS7 gate working, not lost coverage.
        #
        # This is also the gate catching a real hazard rather than misfiring: a pull_request
        # run tests the MERGE commit, so a ceiling measured before an unrelated merge to main
        # goes stale without anything in this branch changing. That is worth a red build.
        #
        # 206 keeps the same +16 headroom over measured that 185 had over 169.
        #
        # RAISED 206 -> 268 for the issue #90 selector audit branch. Measured 252 on run
        # 31830362870 (windows-latest, Windows PowerShell 5.1): 2601 passed / 0 failed / 252
        # skipped, against 192 on the main run it branched from (31755862501). The +60 is
        # exactly the three PS7-gated files this branch adds -- 33 in
        # PfbPipelineSelectorTools.Tests.ps1, 16 in PfbSelectorProbeHarness.Tests.ps1, 11 in
        # PfbPipelineSelectorRail.Tests.ps1. They RUN on 7 (that leg still skips 2), so this is
        # the PS7 gate working, not lost coverage. The fourth new file,
        # Build-PfbPipelineSelectorMap.Tests.ps1, reads the committed report rather than the
        # spec cache and so runs on both editions -- it adds no skips.
        #
        # 268 keeps the same +16 headroom over measured.
        #
        # RAISED 268 -> 273 for the issue #112 contextScope version tripwire. It adds one
        # PS7-gated Describe of 5 It blocks to
        # Build-PfbCapabilityMap.ContextScopeDrift.Tests.ps1, taking that file's 5.1 skips from
        # 8 to 13 (measured locally under both editions: pwsh 7 20 passed / 0 skipped, 5.1
        # 7 passed / 13 skipped, container ok on both). They RUN on 7, so this is the PS7 gate
        # working, not lost coverage. The file's other new Describe -- the synthetic-input tests
        # for Get-PfbContextScopeVersionFinding -- is deliberately UNGATED: it needs neither the
        # spec cache nor ConvertFrom-Json -Depth, so it executes on both legs and adds no skips.
        #
        # 273 keeps the same +16 headroom over an expected measured 257.
        #
        # RAISED 273 -> 313 for the test-module import branch. This is a REBASE RESOLUTION: that
        # branch was cut before #112 landed and raised 268 -> 308 against its own measurement of
        # 292, so the two raises collided in exactly the way the top of this block warns about.
        # They are additive rather than competing, because they gate different files:
        #
        #   252  the figure that justified 268, from run 31830362870.
        #   +5   Build-PfbCapabilityMap.ContextScopeDrift.Tests.ps1, from #112 (above).
        #   +34  Update-PfbTestModuleImport.Tests.ps1, added by THIS branch -- 33 fixture Its
        #        plus the one real-tree -WhatIf fixed-point It. The rewriter it tests declares
        #        `#Requires -Version 7.0`, so a PS7 gate is correct for it, and the whole file
        #        runs on 7 (that leg measures 2 skipped against its ceiling of 8).
        #   +6   Build-PfbDeadKeyReport.Tests.ps1, which is from NEITHER branch. It arrived on
        #        2026-08-16 in 302f9e4 (#120), two days AFTER 364a0fe set this ceiling to 268 on
        #        2026-08-14. #120 had slack and passed without touching this file, so 268 was
        #        already stale against main before either branch existed -- the exact "ceiling
        #        measured before an unrelated merge goes stale" hazard described at the top of
        #        this block, caught in a rebase rather than in CI.
        #   ---
        #   297  expected measured on the merged tree.
        #
        # The 292 half of that is a REAL CI figure, not a local one: run 32338515336
        # (windows-latest, Windows PowerShell 5.1) reported 2984 passed / 0 failed / 292 skipped
        # on the pre-rebase tree, matching the local run exactly. The +5 is #112's own
        # measurement. 313 keeps the standing +16 headroom over 297. If CI reports materially
        # more than 297, something other than these three files moved and the delta should be
        # re-attributed before raising again.
        #
        # ---------------------------------------------------------------------------------
        # END OF RETAINED HISTORY. Live gate below.
        # ---------------------------------------------------------------------------------
        #
        # Seeded from run 32392093324 on main@98c7a16 (2026-08-20, windows-latest, Windows
        # PowerShell 5.1): 3033 passed / 0 failed / 297 skipped / 0 not-run, attributed across
        # 19 files. The entries sum to exactly 297, which reconciles with the run's own total --
        # the gate asserts that reconciliation on every run, so a container the walk misses is
        # a red rather than a quietly smaller number.
        #
        # Every entry is the same cause: a Describe carrying
        # -Skip:($PSVersionTable.PSVersion.Major -lt 7), or a whole tooling file gated that way,
        # because the generator or spec-walking code under test needs pwsh 7. They RUN on 7 --
        # that leg skips 2 in total -- so these are the PS7 gate working as designed, not lost
        # coverage. That is why the two editions need separate maps.
        #
        # When one of these numbers moves, the gate names the file and the delta. Update the
        # line and say why in the commit message. Do NOT pad it.
        ExpectedSkips     = @{
            # Tooling files gated wholesale: no executed tests on 5.1 at all. These are the
            # ones the empty-container rail would flag if their -Skip: guards were ever
            # replaced with `#Requires -Version 7.0`, which would take them out of the skip
            # count entirely and make them invisible here.
            'Build-PfbApiDriftReport.Tests.ps1'                  = 65
            'Build-PfbCapabilityMap.Tests.ps1'                   = 50
            'Update-PfbTestModuleImport.Tests.ps1'               = 34
            'PfbPipelineSelectorTools.Tests.ps1'                 = 33
            'PfbSelectorProbeHarness.Tests.ps1'                  = 16
            'Build-PfbFieldCmdletMap.Tests.ps1'                  = 15
            'PfbPipelineSelectorRail.Tests.ps1'                  = 11
            'Build-PfbResponseShapeMap.Tests.ps1'                = 9
            'Build-PfbDeadKeyReport.Tests.ps1'                   = 6
            # Mixed files: some Describes PS7-gated, others deliberately ungated so they
            # execute on both legs. The passing halves are what several RequiredDescribes
            # entries above are asserting, so these two numbers moving in opposite directions
            # is a real signal rather than noise.
            'Build-PfbValueEnumMap.Tests.ps1'                    = 14
            'Build-PfbCapabilityMap.ContextScopeDrift.Tests.ps1' = 13
            # 8 -> 12 for issue #113: four new tests assert against the REAL Public/Private
            # tree and the real capability map, so they carry the file's existing PS7 gate.
            # Measured on Windows PowerShell 5.1, not inferred -- 125 passed / 12 skipped.
            'PfbApiDriftTools.Tests.ps1'                         = 12
            'PfbValueEnumTools.Tests.ps1'                        = 8
            'PfbSpecTools.Tests.ps1'                             = 6
            'PfbSpecTools.ContextScope.Tests.ps1'                = 4
            'Issue31.DriftConfidence.Tests.ps1'                  = 1
            # Not PS7 gating: ordinary per-test guards on platform or edition behaviour. The
            # first two also appear in the pwsh7 map, at lower counts.
            'New-PfbJwtToken.Tests.ps1'                          = 2
            'Set-PfbTlsProtocol.Tests.ps1'                       = 1
            'Connect-PfbArray.OAuth2TokenRefresh.Tests.ps1'      = 1
        }
        # Only the ungated blocks are required here. The six spec-cache blocks above are
        # PS7-gated by design, so requiring them on 5.1 would be a permanent false red.
        RequiredDescribes = @(
            'Committed drift report (REGRESSION guard, no spec cache required)'
            'Committed drift report: annotations and summary fields survived generation'
            'ConvertTo-PfbRepoRelativePath (REGRESSION guard for issue #63: runs with no spec cache, on every edition)'
            # Issue #102 -- ungated on both editions for the same reason as above: committed
            # capability data only, no PS7 gate, no graceful-skip path.
            '-TotalOnly is exposed only where the published spec declares total_only (#102)'
            'the 26 cmdlets corrected by #102 no longer expose -TotalOnly'
            'the 12 cmdlets whose endpoints do declare total_only keep the switch (#102 is not a blanket removal)'
            # Ungated for the same reason: it parses tracked .ps1 files via the AST, so it needs
            # neither the spec cache nor the generated manifest and has no skip path.
            'Build-PfbValueEnumMap: hand-written ValidateSet citations'
            # Test-module import guard. Ungated -- pure AST over tracked .ps1 files, so it
            # needs neither the spec cache nor PowerShell 7 and has no skip path. Listed
            # under winps51 too, for that reason.
            'Test-module import guard (AST, no spec cache required, every edition)'
            # Dead-key gate, ungated half. It reads only the committed
            # Reports/PfbDeadKeyReport.json -- no spec cache, no PowerShell 7, no skip path --
            # so it must contribute executed tests on BOTH legs. Its two PS7-only siblings,
            # 'Build-PfbDeadKeyReport regeneration (real spec cache required, PS7 only)' and
            # 'Build-PfbDeadKeyReport classification (synthetic fixture, no spec cache, PS7
            # only)', are deliberately absent from this list and appear under pwsh7 only.
            'Committed dead-key report (REGRESSION guard, no spec cache required)'
            # Issue #121 empty-pipeline guards -- see the pwsh7 block for the full rationale.
            # Unlike the dead-key and issue-#90 generator gates above, BOTH of these belong on
            # this leg too: the guard generator declares `#Requires -Version 5.1`, so its
            # real-tree fixed-point check is not PS7-only and requiring it here is not a false
            # red. Measured 7 passed / 15 passed on 5.1 for the two files.
            'Empty-pipeline guard coverage'
            'Update-PfbEmptyPipelineGuards - real tree'
            # Issue #112, synthetic half only. It reads no spec and uses no PS7-only syntax, so
            # it runs on this leg (measured 7 passed on 5.1) and is the ONLY thing proving the
            # comparison can produce a finding at all -- the real-spec half it guards is
            # vacuously green and is PS7-gated, so it appears under pwsh7 alone.
            'Get-PfbContextScopeVersionFinding, against synthetic declarations'
        )
    }
}
