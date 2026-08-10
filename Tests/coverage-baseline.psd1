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
        MaxSkipped        = 15
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
        )
    }
    winps51 = @{
        MaxSkipped        = 260
        # Only the ungated blocks are required here. The six spec-cache blocks above are
        # PS7-gated by design, so requiring them on 5.1 would be a permanent false red.
        RequiredDescribes = @(
            'Committed drift report (REGRESSION guard, no spec cache required)'
            'Committed drift report: annotations and summary fields survived generation'
            'ConvertTo-PfbRepoRelativePath (REGRESSION guard for issue #63: runs with no spec cache, on every edition)'
        )
    }
}
