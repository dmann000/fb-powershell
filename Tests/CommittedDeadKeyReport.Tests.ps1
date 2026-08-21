#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    REGRESSION guard over the COMMITTED Reports/PfbDeadKeyReport.json.
.DESCRIPTION
    A cmdlet parameter that is written into a query key the endpoint does not DECLARE is
    silently discarded by the array: a GET returns the unfiltered collection, and a DELETE
    arrives with no selector at all. The motivating incident aimed a DELETE at another admin's
    API token using an undeclared key, so the request arrived unselected and destroyed the
    caller's own token. tools/Build-PfbDeadKeyReport.ps1 finds those keys; this file is what
    makes a NEWLY INTRODUCED one a red build instead of a live-array surprise.

    WHY THIS FILE READS THE COMMITTED ARTIFACT AND NEVER REGENERATES:
      1. The gate must run on EVERY CI leg, including Windows PowerShell 5.1. The generator
         carries `#Requires -Version 7.0` and cannot run there at all, and it needs the
         gitignored ~50MB tools/specs cache, which a bare runner does not have.
      2. The failure mode worth catching is a STALE COMMITTED ARTIFACT. A gate that
         regenerates before asserting can never catch it -- it would compare fresh output
         against itself. Tests/Build-PfbDeadKeyReport.Tests.ps1 (PS7-gated) owns the
         regeneration comparison; this file owns what was actually shipped.

    MONOTONE, NOT EXACT -- read before "tightening" anything here.
    Every set assertion below is "nothing NEW appeared", never "the set is exactly this".
    An exact-equality gate fails on the very PR that FIXES a dead key, and so forces an
    artifact regeneration into every later fix -- the anti-pattern the second Describe of
    Tests/CommittedDriftReport.Tests.ps1 argues against at length ("a test asserting 'not yet
    implemented' fails on the PR that implements the thing"). The stated goal is that the set
    cannot GROW silently, which is a monotone property. A SHRINK MUST PASS, all the way to
    zero: the generator was verified to survive an empty deadKeys set. A PR that fixes EVERY
    dead key reds this file in exactly one place -- the two non-emptiness assertions at the
    bottom of assertion 1 -- and nowhere else, and the edit that case needs is stated precisely
    at the SHRINK-TO-ZERO RELAX POINT note on assertion 1, which is the single authority for it.
    Any PARTIAL fix, up to and including all 13 destructive entries or all 6 groups at once,
    needs no edit at all.

    HOW THE BASELINE WAS DERIVED, and what would / would not red this file:
    The artifact is itself the committed thing, so the baseline is the artifact as regenerated
    for the issue-90 selector fixes (specVersion 2.28): 85 deadKeys
    (13 DESTRUCTIVE / 2 CREATE / 70 WRONG-RESULTS) and 6 noSurvivingSelector groups. The
    DESTRUCTIVE identities and the noSurvivingSelector identities were read out of that file
    and pinned below as ALLOWLISTS; the dead-key and skip counts were pinned as CEILINGS; and
    the inventory counts were pinned as FLOORS, which is the one direction the monotone design
    does NOT leave free -- see the coverage-collapse test for why. Therefore:
      REDS   -- a dead key appearing on a destructive verb that is not already pinned; a new
                noSurvivingSelector group; the dead-key count or a CEILINGED skip count going
                UP; a new skip reason; a severity outside the known vocabulary;
                parametersInventoried or keysEvaluated collapsing; the counts failing to
                reconcile; an absolute path in the artifact; the artifact's ordering not
                matching the generator's ordinal comparer. ('body property' is a known skip
                reason that is deliberately NOT ceilinged -- see $baselineUnceilingedSkipReasons
                in BeforeAll.)
      PASSES -- any entry disappearing, any dead-key or skip count going DOWN, all the way to
                zero. Only the total-zero case needs an edit, and only to one assertion; see
                the SHRINK-TO-ZERO RELAX POINT note on assertion 1.

    NON-VACUITY IS ASSERTED AS A PROPERTY OF EACH SCAN, not of the collection it walks. Every
    scan counts what it visited and asserts a bound tied to its input's REAL SIZE -- never a
    bare `> 0`, which proves only that a loop ran once and which a loop silently skipping most
    of its entries passes. The bound takes one of two forms, depending on whether the input size
    is knowable in advance:

      EQUALITY, where it is. The three scans over a materialised collection -- destructive dead
      keys, noSurvivingSelector groups, and skip reasons -- each assert visited == input count.

      A CONTENT-DERIVED FLOOR, where it is not. The absolute-path scan is a recursive descent
      with no collection to measure, so it asserts it visited at least 5 strings per dead-key
      record: enough to prove it descended into the deadKeys subtree rather than skimming the
      top level. A `> 0` floor there was measured at one string away from vacuous.

    Both forms are trivially satisfied at zero dead keys (0 == 0, and >= 0), so neither costs
    shrink-safety. File-level non-vacuity lives in assertion 1 alone.
    Renaming a cmdlet or moving an endpoint changes an identity, so it reads as "new" and
    reds. That is intended: it wants a human to re-confirm the key is still declared, and the
    fix is a one-line edit to the pinned list in the same reviewed diff.

    5.1 CONSTRAINT: no `ConvertFrom-Json -Depth` (not a 5.1 parameter), no ternaries, no `??`.
    The ordinal comparer mirrored below was executed under Windows PowerShell 5.1.26100 and
    confirmed to yield true ordinal order there, including on mixed case.
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:committedReportPath = Join-Path $repoRoot 'Reports/PfbDeadKeyReport.json'
    # Existence is checked HERE rather than in an It, because an It could never see it fail:
    # with the file absent, the Get-Content below errors first and Pester turns that into a
    # container failure, so no It body runs at all. A `Test-Path | Should -BeTrue` in an It
    # would therefore be an assertion that cannot fail -- exactly what this file's header
    # argues against elsewhere. The throw exists to replace the raw Get-Content error, which
    # names the path but not what the reader should do about it.
    if (-not (Test-Path -LiteralPath $script:committedReportPath)) {
        throw "Reports/PfbDeadKeyReport.json is missing at '$($script:committedReportPath)'. It is a TRACKED artifact, not a build cache -- do not regenerate it to satisfy this test. Restore it from git (git checkout -- Reports/PfbDeadKeyReport.json); if it was deliberately deleted, this whole gate went with it."
    }
    $script:committedReport = Get-Content -Path $committedReportPath -Raw | ConvertFrom-Json

    # --- Pinned baseline, read out of the regenerated issue-90 artifact -----------------
    # Identity of a dead key = cmdlet|parameter|wireKey|method|endpoint. Identity of a
    # no-surviving-selector group = cmdlet|method|endpoint (exactly the fields the artifact
    # carries for each; there is no file/line in either record).
    $script:baselineDestructive = @(
        'Remove-PfbFileLock|Id|ids|DELETE|file-systems/locks'
        'Remove-PfbFleetMember|FleetName|fleet_names|DELETE|fleets/members'
        'Remove-PfbLocalGroup|Id|ids|DELETE|directory-services/local/groups'
        'Remove-PfbNetworkAccessRule|PolicyId|policy_ids|DELETE|network-access-policies/rules'
        'Remove-PfbNetworkAccessRule|PolicyName|policy_names|DELETE|network-access-policies/rules'
        'Remove-PfbNfsExportRule|PolicyId|policy_ids|DELETE|nfs-export-policies/rules'
        'Remove-PfbNfsExportRule|PolicyName|policy_names|DELETE|nfs-export-policies/rules'
        'Remove-PfbNodeGroupNode|GroupName|group_names|DELETE|node-groups/nodes'
        'Remove-PfbNodeGroupNode|MemberName|member_names|DELETE|node-groups/nodes'
        'Remove-PfbObjectStoreAccessKey|Id|ids|DELETE|object-store-access-keys'
        'Remove-PfbObjectStoreRoleAccessPolicy|RoleName|role_names|DELETE|object-store-roles/object-store-access-policies'
        'Remove-PfbSmbClientRule|PolicyId|policy_ids|DELETE|smb-client-policies/rules'
        'Remove-PfbSmbClientRule|PolicyName|policy_names|DELETE|smb-client-policies/rules'
    )
    $script:baselineNoSurvivingSelector = @(
        'Get-PfbFileLockClient|GET|file-systems/locks/clients'
        'Get-PfbKeytabDownload|GET|keytabs/download'
        'Get-PfbLegalHoldEntity|GET|legal-holds/held-entities'
        'Get-PfbNodeGroupNode|GET|node-groups/nodes'
        'New-PfbNlmReclamation|POST|file-systems/locks/nlm-reclamations'
        'Remove-PfbNodeGroupNode|DELETE|node-groups/nodes'
    )
    # CEILINGS, not pins -- see the monotone note above.
    #
    # LOWERED 85 -> 83. PR #134 fixed #119, which removed the two Invoke-PfbNetworkPing /
    # Invoke-PfbNetworkTrace `source.name` records (one of them a severity WRONG-RESULTS
    # entry), and the committed report went 85 -> 83. Nothing red, because 85 is a ceiling and
    # a DROP is the direction it calls better -- which is exactly why this needs re-lowering
    # by hand: left at 85 the gate silently tolerates two brand-new dead keys, and would
    # report safety it is no longer providing.
    #
    # Re-lower this whenever a fix drops the count. It stays a CEILING rather than becoming a
    # pin: dead keys legitimately fall as fixes land, and a pin would red every such fix and
    # make the gate a tax on doing the right thing. The cost of the ceiling is precisely the
    # slack being closed here, so closing it promptly is the whole discipline.
    $script:baselineDeadKeyCount = 83
    $script:baselineNoSurvivingSelectorCount = 6
    $script:baselineSkipReasons = @{
        # New-PfbBucketAuditFilter|Name was introduced by 9d08ecc as a new parameter, so
        # nothing that was evaluable stopped being evaluated. The parameter demonstrably
        # reaches the wire through `$filterNames = if ($Name) { $Name } else { $BucketName }`
        # and `$queryParams['names'] = $filterNames -join ','`; it is unresolvable only because
        # the AST resolver cannot trace that conditional. This is the `body property` case,
        # not the coverage-loss case this ceiling guards against.
        'wire name unresolved'           = 126
        'endpoint/method ambiguous'      = 14
        'endpoint/verb absent from spec' = 0
    }
    # KNOWN skip reasons that are deliberately NOT ceilinged. Do not read this as an oversight
    # and put 'body property' back into the hashtable above.
    #
    # 'body property' was ceilinged at 278 and had to come out: bumping it to 279 -- i.e. any
    # unrelated PR adding a single body-surface parameter -- red the gate with "those keys are
    # now unevaluable, not proven safe", which asserts a safety regression that did not happen.
    # A new body parameter was never evaluable AS A QUERY KEY in the first place, so its
    # non-evaluation is not lost coverage. Body-surface parameters are explicitly P1's scope, so
    # the ceiling red a PR that had done nothing wrong. The other three reasons are not like
    # this: growth in 'wire name unresolved' or 'endpoint/method ambiguous' means keys that WERE
    # evaluable stopped being evaluated, which genuinely does shrink what this gate covers.
    #
    # Reconciliation still catches arithmetic inconsistency, but it does NOT catch a realistic
    # reclassification that moves one record from keysEvaluated into this bucket while preserving
    # the total. The keysEvaluated floor is the remaining coverage-collapse check, with deliberate
    # headroom from its measured 1757. This reason is unceilinged because that weaker watch is the
    # accepted cost of avoiding false reds on legitimate body-surface work.
    $script:baselineUnceilingedSkipReasons = @('body property')
}

Describe 'Committed dead-key report (REGRESSION guard, no spec cache required)' {

    It 'the committed report exists and carries a non-empty deadKeys set' {
        # ANTI-VACUITY, first in the file. If this fails every scan below is meaningless, so
        # it fails first and loudly rather than passing silently over a missing or empty file.
        #
        # SHRINK-TO-ZERO RELAX POINT -- the ONLY one in this file. This is the only place that
        # asserts how MUCH is in the report; everything else asserts either that nothing NEW
        # appeared, or that a floor/ceiling holds, or that a scan visited everything it was
        # handed. Those are all satisfied by an empty artifact.
        #
        # WHAT A PR THAT FIXES EVERY REMAINING DEAD KEY HAS TO DO, stated precisely because an
        # earlier version of this comment got it wrong and would have sent that reader in
        # circles. With `deadKeys: []` and `noSurvivingSelector: []` the file reds HERE and
        # nowhere else. The edit is to drop the two non-emptiness assertions at the bottom of
        # this block -- the `Should -Not -BeNullOrEmpty` on deadKeys and the `-BeGreaterThan 0`
        # on its count -- keeping the structural property-exists and non-null checks above
        # them, which still separate "empty artifact" from "broken artifact". Nothing else
        # needs touching: the two scans assert an equality against their own input size, which
        # is trivially true at zero, and both ordering blocks no-op on an empty list.
        #
        # It is a real decision rather than a formality: past that point the file no longer
        # proves it scanned anything, and its guarantee narrows to the monotone one.
        #
        # A PARTIAL fix -- even all 13 destructive entries, or all 6 groups, at once -- needs
        # no edit at all. Every one of these cases was constructed and confirmed.
        # specVersion is asserted PRESENT AND VERSION-SHAPED, never pinned to a value. It is the
        # spec the whole report was computed against, so an artifact that lost it is not
        # interpretable at all -- and nothing else on the ungated leg looked at it (it was
        # constrained only indirectly, through the skip ceilings, and finding 3 loosens those).
        # A pin to '2.28' would red the routine REST-version-bump PR, which is exactly the
        # exact-equality anti-pattern this file's header argues against.
        $committedReport.PSObject.Properties.Name | Should -Contain 'specVersion' -Because 'the report is only interpretable against the spec version it was computed from; an artifact that dropped specVersion is structurally broken'
        [string]$committedReport.specVersion | Should -Match '^\d+\.\d+$' -Because "specVersion must look like a REST API version (e.g. 2.28); it is '$($committedReport.specVersion)'. Deliberately a SHAPE and not a pin -- pinning it would red the PR that bumps the spec."
        $committedReport.PSObject.Properties.Name | Should -Contain 'deadKeys' -Because 'a deadKeys property that vanished entirely would otherwise be indistinguishable from one holding an empty list'
        $committedReport.PSObject.Properties.Name | Should -Contain 'noSurvivingSelector' -Because 'a noSurvivingSelector property that vanished would make the highest-severity scan below vacuous'
        # Explicitly NOT -BeNullOrEmpty via @(...).Count: `@($null).Count` is 1, so a report
        # carrying `"deadKeys": null` would sail past a count-only floor and this assertion
        # would fail neither first nor loudly.
        $committedReport.deadKeys | Should -Not -BeNullOrEmpty -Because 'a null or empty deadKeys would make every scan below vacuous'
        $null -ne $committedReport.noSurvivingSelector | Should -BeTrue -Because 'a null noSurvivingSelector is a structurally broken artifact, not an empty one -- the generator always emits an array'
        @($committedReport.deadKeys).Count | Should -BeGreaterThan 0 -Because 'a report with no deadKeys would make every scan below vacuous'
    }

    It 'introduces no NEW dead key on a destructive verb' {
        # DESTRUCTIVE == DELETE/PATCH/PUT (Get-PfbDeadKeySeverity). These are the entries where
        # a discarded key means the request arrives with no selector, so a new one is the
        # motivating incident happening again.
        #
        # NON-VACUITY IS A PROPERTY OF THE SCAN, NOT OF THE COLLECTION. The question worth
        # asking is not "was there anything to look at" but "did this loop visit everything it
        # was handed", so the assertion below is an EQUALITY against the full input size rather
        # than a greater-than-zero floor. Three consequences, all deliberate:
        #   - It is strictly stronger. `> 0` proved only that the loop ran at least once, so a
        #     `continue` bug that silently skipped most entries passed it. Equality catches
        #     that, and was confirmed to by construction.
        #   - It is trivially satisfied at zero (0 -eq 0), so the case where a future PR fixes
        #     every dead key needs no edit here at all. Counting the DESTRUCTIVE matches instead
        #     would have made "all 13 destructive dead keys got fixed" -- a tractable single PR,
        #     and the outcome this artifact exists to produce -- red the gate.
        #   - It keeps this test self-sufficient: it proves its own faithfulness without
        #     depending on assertion 1 having run first.
        # File-level non-vacuity lives in assertion 1 alone.
        $scanInput = @($committedReport.deadKeys)
        $scanned = 0
        $offenders = foreach ($entry in $scanInput) {
            $scanned++
            # THE PREDICATE BELOW IS ANCHORED TO THE SEVERITY VOCABULARY, and it is anchored
            # BECAUSE THE UNANCHORED FORM WAS MEASURED VACUOUS. `-ne 'DESTRUCTIVE'` matches
            # nothing at all if the vocabulary moves, and two mutations were run that each
            # produced P7 F0 -- a clean green with this file's highest-value assertion covering
            # zero entries:
            #   1. delete the `severity` property from the artifact -- `$null -ne 'DESTRUCTIVE'`
            #      is true for all 85 records, so every entry `continue`s;
            #   2. rename the vocabulary in the generator (DESTRUCTIVE -> DELETE-RISK) and
            #      regenerate honestly -- same total skip, no failure anywhere.
            # The only thing otherwise pinning the vocabulary is one synthetic assertion in
            # Tests/Build-PfbDeadKeyReport.Tests.ps1, which is PS7-gated -- so on the 5.1 leg,
            # the leg this ungated file exists to serve, the 13-identity destructive allowlist
            # had no proof it matched anything. This assertion makes a renamed or dropped
            # severity a red instead of a silent full-skip.
            #
            # It is NOT a floor on a filtered subset (Task 4 round 1, finding 1 -- do not go
            # back to counting matches). It is a per-record property assertion inside the scan
            # that already visits every record, so it costs nothing at zero dead keys: a
            # `foreach` over an empty collection never evaluates it.
            $entry.severity | Should -BeIn @('DESTRUCTIVE', 'CREATE', 'WRONG-RESULTS') -Because "the severity vocabulary is what the filter below keys on, so an unrecognised or missing severity means the DESTRUCTIVE filter silently matches nothing: $($entry.cmdlet) -$($entry.parameter) carries severity '$($entry.severity)'. If the generator's vocabulary changed deliberately, update this list AND the filter below in the same reviewed diff."
            # `declared` is what a reader fixes the cmdlet from, and it is interpolated into the
            # offender message below -- where a missing property renders as an empty string and
            # degrades the message silently. Asserted here, on the ungated leg, because nothing
            # else on 5.1 checked it at all.
            $entry.PSObject.Properties.Name | Should -Contain 'declared' -Because "every dead-key record must carry the declared-key list a reader fixes the cmdlet from; $($entry.cmdlet) -$($entry.parameter) has none, and its absence would render as an empty list in this test's own failure message rather than as an error"
            if ($entry.severity -ne 'DESTRUCTIVE') { continue }
            $identity = '{0}|{1}|{2}|{3}|{4}' -f $entry.cmdlet, $entry.parameter, $entry.wireKey, $entry.method, $entry.endpoint
            if ($baselineDestructive -notcontains $identity) {
                "NEW DESTRUCTIVE dead key: $($entry.cmdlet) -$($entry.parameter) writes query key '$($entry.wireKey)', which $($entry.method) $($entry.endpoint) does not declare. That endpoint/verb declares only: $(@($entry.declared) -join ', '). The request will arrive without that selector."
            }
        }
        $scanned | Should -Be $scanInput.Count -Because "the scan must visit every dead key, not silently skip some: it visited $scanned of $($scanInput.Count)"
        @($offenders) | Should -BeNullOrEmpty -Because "a destructive verb carrying an undeclared query key is the incident this gate exists to prevent. Either declare/rename the key, or -- if this is a deliberate, reviewed addition -- add its identity to `$baselineDestructive in this file."
    }

    It 'introduces no NEW noSurvivingSelector entry' {
        # The highest-severity class in the artifact: EVERY selector-shaped key the operation
        # sends is dead, so the request carries no usable selector at all. A new one here is
        # strictly worse than a new DESTRUCTIVE dead key alongside a surviving selector.
        #
        # Same visit-everything reasoning as the test above, and here the payoff is sharper:
        # this collection has only 18 entries, so "somebody fixed all of them" is one PR. Any
        # non-emptiness floor -- on this collection or on deadKeys -- would make the gate red on
        # precisely its own success. An equality against the input size does not.
        $scanInput = @($committedReport.noSurvivingSelector)
        $scanned = 0
        $offenders = foreach ($group in $scanInput) {
            $scanned++
            $identity = '{0}|{1}|{2}' -f $group.cmdlet, $group.method, $group.endpoint
            if ($baselineNoSurvivingSelector -notcontains $identity) {
                $deadKeysForGroup = @(@($committedReport.deadKeys) | Where-Object {
                    $_.cmdlet -eq $group.cmdlet -and $_.method -eq $group.method -and $_.endpoint -eq $group.endpoint
                })
                $detail = @($deadKeysForGroup | ForEach-Object { "-$($_.parameter) -> '$($_.wireKey)'" }) -join '; '
                $declared = @()
                if ($deadKeysForGroup.Count -gt 0) { $declared = @($deadKeysForGroup[0].declared) }
                "NEW noSurvivingSelector: $($group.cmdlet) ($($group.method) $($group.endpoint)) has no surviving selector -- every selector-shaped key it sends is undeclared [$detail]. That endpoint/verb declares only: $($declared -join ', ')."
            }
        }
        $scanned | Should -Be $scanInput.Count -Because "the scan must visit every noSurvivingSelector group, not silently skip some: it visited $scanned of $($scanInput.Count)"
        @($offenders) | Should -BeNullOrEmpty -Because "an operation with no surviving selector sends an unselected request. Either declare/rename a selector, or -- if this is a deliberate, reviewed addition -- add its identity to `$baselineNoSurvivingSelector in this file."
    }

    It 'keeps the inventory covered: parametersInventoried and keysEvaluated stay above their floors' {
        # THE COVERAGE-COLLAPSE GUARD. Without it every other assertion in this file can be
        # satisfied by a report that simply stopped looking: cut parametersInventoried 2174 ->
        # 900 and keysEvaluated 1757 -> 700, and a third of the dead keys and a third of the
        # groups vanish from the gate's view with every ceiling and every allowlist still
        # cleared. That was reproduced against this file before this test existed -- all six
        # tests passed. A gate reporting safety it does not provide is worse than no gate.
        #
        # The ceilings below cannot cover it: a regression in the AST inventory walk or the
        # wire-name resolver drops the dead-key and skip counts too, so every one of them moves
        # in the direction the ceilings call "better". Nor can the PS7 regeneration gate: that
        # catches a generator change made WITHOUT regenerating, and a PR that changes the
        # generator and regenerates passes both files.
        #
        # FLOORS, NOT PINS, for the reason scripts/Assert-PfbSpecCache.ps1 gives for its own
        # floor of 20 against 29 published specs: this asserts "the mechanism still ran over
        # the corpus", and the real figures move with ordinary cmdlet churn and with genuine
        # reclassification. Pinning them would turn every unrelated cmdlet addition into a red
        # build. Measured at the baseline commit (specVersion 2.28): parametersInventoried
        # 2174, keysEvaluated 1757 -- so the headroom below is 174 and 157 respectively, and
        # the 900/700 collapse misses by a wide margin.
        #
        # deadKey and the skip counts are deliberately NOT floored. Those must be free to fall
        # to zero; that is the whole monotone design, and flooring them would recreate the bug
        # this file was sent back for.
        $committedReport.counts.parametersInventoried | Should -BeGreaterOrEqual 2000 -Because "the AST inventory must still be walking the whole of Public/: it reported $($committedReport.counts.parametersInventoried) parameters against a measured 2174. A large drop is a coverage collapse, not an improvement -- the keys that disappeared were not proven safe, they stopped being looked at."
        $committedReport.counts.keysEvaluated | Should -BeGreaterOrEqual 1600 -Because "the classifier must still be evaluating the bulk of the inventory: it reported $($committedReport.counts.keysEvaluated) evaluated keys against a measured 1757. Every key that stops being evaluated leaves the gate's view silently."
        # THE RECONCILIATION, both halves -- and the two halves are NOT of equal strength. Said
        # plainly, because an earlier version of this comment overclaimed the first one:
        #
        #   FIRST (ok + deadKey == keysEvaluated) IS TRUE BY CONSTRUCTION for any GENERATED
        #   artifact, on any input. The generator computes ok as
        #   evaluatedRecords.Count - deadKeyRecords.Count and keysEvaluated as
        #   evaluatedRecords.Count, so the identity holds arithmetically whatever the classifier
        #   did. It cannot catch a generator bug and it cannot catch a "partial regeneration"
        #   either -- there is no such thing here, the manifest is serialised whole in one
        #   ConvertTo-Json / Set-Content. What it CAN catch is a HAND-EDITED artifact, which is
        #   why it is kept: it is one line, and it is a strictly better use of that line than the
        #   `ok >= 0` it replaced (which was non-negative by construction too, so it could not
        #   even catch the hand-edit).
        #
        #   SECOND (keysEvaluated + all skip reasons == parametersInventoried) is the one with
        #   real content against a GENERATOR bug: evaluation and skipping are counted on
        #   different paths, so a record that falls through both is invisible to the floors above
        #   and reds here. Proven, not assumed -- dropping a third of the inventory records and
        #   regenerating reds this half.
        #
        # Together they close a specific hole in the floors above: the floors ask whether the
        # headline numbers are big enough, and these ask whether they add up. A collapse that
        # scaled every counter proportionally would clear neither. They assert arithmetic
        # consistency, not stability of any individual skip-reason count: moving one record from
        # keysEvaluated into 'body property' preserves this equation and is watched only by the
        # deliberately loose keysEvaluated floor.
        $skipTotal = 0
        foreach ($reason in $committedReport.counts.skipReasons.PSObject.Properties) { $skipTotal += [int]$reason.Value }
        ([int]$committedReport.counts.ok + [int]$committedReport.counts.deadKey) |
            Should -Be ([int]$committedReport.counts.keysEvaluated) -Because "every evaluated key is either OK or dead, so ok + deadKey must equal keysEvaluated: $($committedReport.counts.ok) + $($committedReport.counts.deadKey) = $([int]$committedReport.counts.ok + [int]$committedReport.counts.deadKey), against keysEvaluated $($committedReport.counts.keysEvaluated)"
        ([int]$committedReport.counts.keysEvaluated + $skipTotal) |
            Should -Be ([int]$committedReport.counts.parametersInventoried) -Because "every inventoried parameter is either evaluated or skipped for exactly one reason, so keysEvaluated + all skip reasons must equal parametersInventoried: $($committedReport.counts.keysEvaluated) + $skipTotal = $([int]$committedReport.counts.keysEvaluated + $skipTotal), against parametersInventoried $($committedReport.counts.parametersInventoried)"
    }

    It 'grows no count: dead keys, no-surviving-selector groups, and every skip reason are <= the committed figures' {
        # <= and never ==, on purpose: an exact pin reds on the PR that FIXES a dead key.
        @($committedReport.deadKeys).Count | Should -BeLessOrEqual $baselineDeadKeyCount -Because "the committed dead-key count must not grow past the $baselineDeadKeyCount baseline; it is $(@($committedReport.deadKeys).Count)"
        @($committedReport.noSurvivingSelector).Count | Should -BeLessOrEqual $baselineNoSurvivingSelectorCount -Because "the committed no-surviving-selector count must not grow past the $baselineNoSurvivingSelectorCount baseline; it is $(@($committedReport.noSurvivingSelector).Count)"

        # A skip is a key the generator could not evaluate at all, so a rising skip count hides
        # dead keys just as effectively as a rising dead-key count -- and does it while the
        # headline numbers look flat or better.
        $scanned = 0
        $offenders = foreach ($reason in $committedReport.counts.skipReasons.PSObject.Properties) {
            $scanned++
            if (-not $baselineSkipReasons.ContainsKey($reason.Name) -and $baselineUnceilingedSkipReasons -notcontains $reason.Name) {
                "UNKNOWN skip reason '$($reason.Name)' (count $($reason.Value)) -- the generator gained a skip class the baseline in this test does not know about"
                continue
            }
            # Known, but deliberately not ceilinged -- see $baselineUnceilingedSkipReasons in
            # BeforeAll for why 'body property' is the odd one out and what still constrains it.
            # Still VISITED and still counted toward the visit-everything equality below: this
            # is a change to what the scan enforces per reason, not to the scan.
            if ($baselineUnceilingedSkipReasons -contains $reason.Name) { continue }
            if ([int]$reason.Value -gt [int]$baselineSkipReasons[$reason.Name]) {
                "skip reason '$($reason.Name)' grew from $($baselineSkipReasons[$reason.Name]) to $($reason.Value) -- those keys are now unevaluable, not proven safe"
            }
        }
        # EQUALITY, not a floor: the input size is trivially knowable here. A scan visiting 1 of
        # 4 skip-reason properties passes a `> 0` floor while hiding a 14 -> 999 growth in one of
        # the three it never looked at.
        $skipReasonCount = @($committedReport.counts.skipReasons.PSObject.Properties).Count
        $scanned | Should -Be $skipReasonCount -Because "the scan must visit every skip reason, not silently skip some: it visited $scanned of $skipReasonCount"
        @($offenders) | Should -BeNullOrEmpty -Because 'a skipped key is unevaluated, so a growing skip count silently shrinks what this gate covers'
    }

    It 'emits no absolute path anywhere in the committed artifact' {
        # Two concrete harms, both observed on the sibling drift artifacts before their guards
        # existed: it publishes a developer's home-directory path to a public repo, and it makes
        # the committed file depend on WHERE it was generated, so a regeneration from a worktree
        # rewrites lines that did not semantically change. The inventory this generator consumes
        # carries a File field holding a full path, so the risk is live rather than theoretical.
        #
        # Iterative walk rather than a recursive function: it keeps the whole scan inside this
        # It block, where a function defined in BeforeAll would be one more scope subtlety on a
        # file that has to behave identically on 5.1 and 7.
        $scanned = 0
        $offenders = [System.Collections.Generic.List[string]]::new()
        $pending = [System.Collections.Generic.List[object]]::new()
        $pending.Add([PSCustomObject]@{ Path = '$'; Value = $committedReport })
        while ($pending.Count -gt 0) {
            $item = $pending[$pending.Count - 1]
            $pending.RemoveAt($pending.Count - 1)
            $value = $item.Value
            if ($null -eq $value) { continue }
            if ($value -is [string]) {
                $scanned++
                if ($value -match '^[A-Za-z]:[\\/]' -or $value -match '^[\\/]{1,2}') {
                    $offenders.Add("$($item.Path) = '$value'")
                }
                continue
            }
            if ($value -is [System.Collections.IEnumerable]) {
                $index = 0
                foreach ($element in $value) {
                    $pending.Add([PSCustomObject]@{ Path = "$($item.Path)[$index]"; Value = $element })
                    $index++
                }
                continue
            }
            if ($value -is [PSCustomObject]) {
                foreach ($property in $value.PSObject.Properties) {
                    $pending.Add([PSCustomObject]@{ Path = "$($item.Path).$($property.Name)"; Value = $property.Value })
                }
            }
            # Anything else (int, bool) carries no path and needs no scan.
        }
        # THE FLOOR IS TIED TO THE ARTIFACT'S REAL CONTENT, and it has to be. This is the one
        # scan whose input size is not knowable in advance -- it is a recursive descent, so
        # there is no collection to measure -- and a `> 0` floor here was demonstrably one
        # string away from vacuous: replacing the IEnumerable descent branch above with a bare
        # `continue` dropped $scanned from 1600 to 1 (top-level specVersion, the only string
        # reachable without descending) and every test in this file still passed. The very fact
        # that made the floor look shrink-safe -- specVersion is always present -- is what held
        # it up while the walk scanned nothing.
        #
        # Each deadKeys record carries at least five string fields (severity, cmdlet, parameter,
        # wireKey, method, endpoint -- six, floored at five so a future field rename cannot red
        # this), so the walk must reach at least 5x the dead-key count in strings or it did not
        # descend into the subtree where a leaked path would actually live. Deliberately
        # expressed against deadKeys.Count rather than a constant: at zero dead keys it reads
        # `>= 0` and still passes, so this stays shrink-safe.
        $expectedMinimumStrings = 5 * @($committedReport.deadKeys).Count
        $scanned | Should -BeGreaterOrEqual $expectedMinimumStrings -Because "the walk must descend into the deadKeys records, not just skim the top level: it visited $scanned strings against the $expectedMinimumStrings that $(@($committedReport.deadKeys).Count) dead-key records carry between them. A walk that stops descending scans nothing and reports clean."
        @($offenders) | Should -BeNullOrEmpty -Because 'every string in the committed report must be repo-relative: an absolute path publishes a local checkout location and makes the artifact depend on where it was generated'
    }

    It 'holds the ordering the generator produced, under the same ordinal mechanism' {
        # Mirrors Sort-PfbDeadKeyRecords in tools/Build-PfbDeadKeyReport.ps1 verbatim: a
        # [System.Comparison[object]] over [string]::Compare(..., Ordinal) on the NAMED
        # PROPERTIES, not on a joined key. It cannot be dot-sourced -- the helper lives inside
        # a self-executing `#Requires -Version 7.0` script, so importing it would run the whole
        # generator and would be impossible on 5.1 -- so it is reimplemented here.
        #
        # Ordinal, not Sort-Object -Culture '': invariant LINGUISTIC order is not stable
        # between 5.1 and 7 (issue #85), and this file runs on both. The comparer below was
        # executed under Windows PowerShell 5.1.26100 and confirmed to yield true ordinal
        # order, including on mixed case.
        #
        # deadKeys sorts on cmdlet then parameter; noSurvivingSelector on cmdlet, method,
        # then endpoint. Both property sets are real fields of the emitted records.
        $sortByOrdinal = {
            param($records, $properties)
            $list = [System.Collections.Generic.List[object]]::new()
            foreach ($record in $records) { $list.Add($record) }
            $list.Sort([System.Comparison[object]]{
                param($left, $right)
                foreach ($propertyName in $properties) {
                    $comparison = [string]::Compare(
                        [string]$left.$propertyName,
                        [string]$right.$propertyName,
                        [System.StringComparison]::Ordinal)
                    if ($comparison -ne 0) { return $comparison }
                }
                return 0
            })
            # @(...) because a List.Sort over an empty collection emits nothing at all, and a
            # bare $null would throw on .Count under StrictMode.
            return @($list)
        }

        # Both blocks are guarded rather than floored. An ordering assertion over an empty list
        # is trivially satisfied, so a floor here would only mean "reds when the collection it
        # is checking the order of became empty" -- which for noSurvivingSelector is 18 fixes
        # away and is the outcome the artifact exists to produce. Non-vacuity for this file
        # lives in assertion 1, not here.
        $deadKeys = @($committedReport.deadKeys)
        if ($deadKeys.Count -gt 0) {
            $deadKeyActual = @($deadKeys | ForEach-Object { '{0}|{1}' -f $_.cmdlet, $_.parameter })
            $deadKeyExpected = @((& $sortByOrdinal $deadKeys @('cmdlet', 'parameter')) | ForEach-Object { '{0}|{1}' -f $_.cmdlet, $_.parameter })
            ($deadKeyActual -join "`n") | Should -Be ($deadKeyExpected -join "`n") -Because 'deadKeys must be committed in ordinal order on (cmdlet, parameter); an unsorted artifact produces churn diffs that bury the real change'
        }

        $groups = @($committedReport.noSurvivingSelector)
        if ($groups.Count -gt 0) {
            $groupActual = @($groups | ForEach-Object { '{0}|{1}|{2}' -f $_.cmdlet, $_.method, $_.endpoint })
            $groupExpected = @((& $sortByOrdinal $groups @('cmdlet', 'method', 'endpoint')) | ForEach-Object { '{0}|{1}|{2}' -f $_.cmdlet, $_.method, $_.endpoint })
            ($groupActual -join "`n") | Should -Be ($groupExpected -join "`n") -Because 'noSurvivingSelector must be committed in ordinal order on (cmdlet, method, endpoint)'
        }
    }
}
