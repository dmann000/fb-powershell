@{
    # Issue #63: CI reported success while roughly 23% of the suite silently skipped, because
    # the tooling tests gate themselves on the gitignored tools/specs/ build cache. Restoring
    # the cache fixes today's hole; this file is what makes the NEXT one a red build.
    #
    # Two independent assertions, because either alone has a gap:
    #
    #   MaxSkipped        catches a Describe that starts reporting skips.
    #   RequiredDescribes catches a Describe that vanishes from the result tree entirely.
    #                     These blocks skip GRACEFULLY: when their guard evaluates false at
    #                     BeforeAll time, or the file is filtered out of a run, they contribute
    #                     NEITHER a skip NOR a pass. A skip ceiling cannot see that, and a
    #                     green summary is then indistinguishable from a silently-absent
    #                     assertion -- the same failure shape as #63, one level down.
    #
    # MaxSkipped is a CEILING WITH HEADROOM, not a pin. Raise it deliberately in a reviewed
    # diff when a change legitimately adds skipped tests, and say why in the commit message.
    #
    # The two editions differ by design and by a wide margin: every Describe in the tooling
    # test files carries -Skip:($PSVersionTable.PSVersion.Major -lt 7), so the 5.1 leg skips
    # all of them. A single shared ceiling would be either a permanent false red on 5.1 or
    # useless on 7.
    pwsh7   = @{
        # Measured 2 on run 31359783827 (ubuntu-latest, pwsh, spec cache restored): 1842
        # passed / 0 failed / 2 skipped. 8 leaves room for a handful of legitimate additions
        # without going so loose that a real regression hides under it.
        MaxSkipped        = 8
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
        )
    }
    winps51 = @{
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
        MaxSkipped        = 206
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
        )
    }
}
