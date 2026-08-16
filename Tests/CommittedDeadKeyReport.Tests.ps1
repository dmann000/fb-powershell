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
    cannot GROW silently, which is a monotone property. A SHRINK MUST PASS. The generator was
    verified to survive an empty deadKeys set, so a future PR that fixes every dead key must
    not red this file either.

    HOW THE BASELINE WAS DERIVED, and what would / would not red this file:
    The artifact is itself the committed thing, so the baseline is the artifact as committed
    at the HEAD this file was written against (bde3270, specVersion 2.28): 126 deadKeys
    (22 DESTRUCTIVE / 8 CREATE / 96 WRONG-RESULTS) and 18 noSurvivingSelector groups. The
    DESTRUCTIVE identities and the noSurvivingSelector identities were read out of that file
    and pinned below as ALLOWLISTS; the dead-key and skip counts were pinned as CEILINGS; and
    the inventory counts were pinned as FLOORS, which is the one direction the monotone design
    does NOT leave free -- see the coverage-collapse test for why. Therefore:
      REDS   -- a dead key appearing on a destructive verb that is not already pinned; a new
                noSurvivingSelector group; any dead-key or skip count going UP; a new skip
                reason; parametersInventoried or keysEvaluated collapsing; an absolute path in
                the artifact; the artifact's ordering not matching the generator's ordinal
                comparer.
      PASSES -- any entry disappearing, any dead-key or skip count going DOWN, all the way to
                zero. Only the total-zero case needs an edit, and only to one assertion; see
                the SHRINK-TO-ZERO RELAX POINT note on assertion 1.

    NON-VACUITY IS ASSERTED AS A PROPERTY OF EACH SCAN, not of the collection it walks: every
    scan counts the elements it visited and asserts that count EQUALS its input size. That is
    strictly stronger than a greater-than-zero floor -- which a loop silently skipping most of
    its entries would pass -- and, unlike a floor, it stays true when the collection legitimately
    empties out. File-level non-vacuity lives in assertion 1 alone.
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

    # --- Pinned baseline, read out of the committed artifact at HEAD bde3270 -------------
    # Identity of a dead key = cmdlet|parameter|wireKey|method|endpoint. Identity of a
    # no-surviving-selector group = cmdlet|method|endpoint (exactly the fields the artifact
    # carries for each; there is no file/line in either record).
    $script:baselineDestructive = @(
        'Remove-PfbBucketAccessPolicy|MemberName|member_names|DELETE|buckets/bucket-access-policies'
        'Remove-PfbBucketAccessPolicy|PolicyName|policy_names|DELETE|buckets/bucket-access-policies'
        'Remove-PfbBucketAuditFilter|MemberId|member_ids|DELETE|buckets/audit-filters'
        'Remove-PfbBucketAuditFilter|MemberName|member_names|DELETE|buckets/audit-filters'
        'Remove-PfbBucketCorsPolicy|MemberId|member_ids|DELETE|buckets/cross-origin-resource-sharing-policies'
        'Remove-PfbBucketCorsPolicy|MemberName|member_names|DELETE|buckets/cross-origin-resource-sharing-policies'
        'Remove-PfbBucketCorsPolicy|PolicyName|policy_names|DELETE|buckets/cross-origin-resource-sharing-policies'
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
        'Remove-PfbOpenFile|Name|names|DELETE|file-systems/open-files'
        'Remove-PfbResourceAccess|Name|names|DELETE|resource-accesses'
        'Remove-PfbSmbClientRule|PolicyId|policy_ids|DELETE|smb-client-policies/rules'
        'Remove-PfbSmbClientRule|PolicyName|policy_names|DELETE|smb-client-policies/rules'
    )
    $script:baselineNoSurvivingSelector = @(
        'Get-PfbBucketAuditFilter|GET|buckets/audit-filters'
        'Get-PfbCertificateGroupCertificate|GET|certificate-groups/certificates'
        'Get-PfbFileLockClient|GET|file-systems/locks/clients'
        'Get-PfbFleetKey|GET|fleets/fleet-key'
        'Get-PfbKeytabDownload|GET|keytabs/download'
        'Get-PfbLegalHoldEntity|GET|legal-holds/held-entities'
        'Get-PfbNetworkConnectionStatistics|GET|network-interfaces/network-connection-statistics'
        'Get-PfbNetworkInterfaceNeighbor|GET|network-interfaces/neighbors'
        'Get-PfbNodeGroupNode|GET|node-groups/nodes'
        'Get-PfbRealmDefaults|GET|realms/defaults'
        'New-PfbBucketAccessPolicy|POST|buckets/bucket-access-policies'
        'New-PfbBucketAuditFilter|POST|buckets/audit-filters'
        'New-PfbBucketCorsPolicy|POST|buckets/cross-origin-resource-sharing-policies'
        'New-PfbNlmReclamation|POST|file-systems/locks/nlm-reclamations'
        'Remove-PfbBucketAccessPolicy|DELETE|buckets/bucket-access-policies'
        'Remove-PfbBucketAuditFilter|DELETE|buckets/audit-filters'
        'Remove-PfbBucketCorsPolicy|DELETE|buckets/cross-origin-resource-sharing-policies'
        'Remove-PfbNodeGroupNode|DELETE|node-groups/nodes'
    )
    # CEILINGS, not pins -- see the monotone note above.
    $script:baselineDeadKeyCount = 126
    $script:baselineNoSurvivingSelectorCount = 18
    $script:baselineSkipReasons = @{
        'wire name unresolved'           = 125
        'body property'                  = 278
        'endpoint/method ambiguous'      = 14
        'endpoint/verb absent from spec' = 0
    }
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
        # A PARTIAL fix -- even all 22 destructive entries, or all 18 groups, at once -- needs
        # no edit at all. Every one of these cases was constructed and confirmed.
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
        #     would have made "all 22 destructive dead keys got fixed" -- a tractable single PR,
        #     and the outcome this artifact exists to produce -- red the gate.
        #   - It keeps this test self-sufficient: it proves its own faithfulness without
        #     depending on assertion 1 having run first.
        # File-level non-vacuity lives in assertion 1 alone.
        $scanInput = @($committedReport.deadKeys)
        $scanned = 0
        $offenders = foreach ($entry in $scanInput) {
            $scanned++
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
        $committedReport.counts.ok | Should -BeGreaterOrEqual 0 -Because 'ok = keysEvaluated - deadKey, so a negative value means the two counters disagree and the artifact is internally inconsistent'
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
            if (-not $baselineSkipReasons.ContainsKey($reason.Name)) {
                "UNKNOWN skip reason '$($reason.Name)' (count $($reason.Value)) -- the generator gained a skip class the baseline in this test does not know about"
                continue
            }
            if ([int]$reason.Value -gt [int]$baselineSkipReasons[$reason.Name]) {
                "skip reason '$($reason.Name)' grew from $($baselineSkipReasons[$reason.Name]) to $($reason.Value) -- those keys are now unevaluable, not proven safe"
            }
        }
        $scanned | Should -BeGreaterThan 0 -Because 'a vacuous scan would pass this test without checking anything'
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
        $scanned | Should -BeGreaterThan 0 -Because 'a vacuous scan would pass this test without checking anything'
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
