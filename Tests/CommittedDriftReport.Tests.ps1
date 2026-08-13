#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    REGRESSION guards over the COMMITTED Reports/PfbApiDriftReport.json|.md -- issue #63.
.DESCRIPTION
    Every other assertion about the drift report runs against a report the test itself
    regenerates, which means it needs tools/specs/: a ~50MB cache of raw OpenAPI specs that is
    gitignored (.gitignore:36 and again .gitignore:46) and therefore absent on every CI runner.
    Those assertions reported "skipped", the job reported "success", and the coverage loss was
    invisible in the run summary -- roughly 23% of the suite, including the absolute-path
    guards added in PR #62.

    The standing requirement those guards protect is about what is COMMITTED to the repository,
    so reading the committed file directly is both cheaper and more on-point. It needs no cache,
    no PowerShell 7, and no fixture tree, so these run on all four CI legs.

    WHY A SEPARATE FILE, not a new Describe inside Build-PfbApiDriftReport.Tests.ps1:
    that file's top-level BeforeAll invokes tools/Build-PfbApiDriftReport.ps1 (which carries
    `#Requires -Version 7.0`) and calls `ConvertFrom-Json -Depth`, a parameter Windows
    PowerShell 5.1 does not have. Every Describe in that file is PS7-gated, so on 5.1 the
    BeforeAll never runs. Adding a single UNGATED block there would drag it in and kill all 65
    tests in the file with a container failure -- see the run-pester-tests skill, which
    documents that exact incident. A guard that must run everywhere needs a home that can.

    5.1 CONSTRAINT: no `ConvertFrom-Json -Depth` (not a 5.1 parameter), no ternaries, no `??`.
    Verified: 5.1 parses the 584KB committed report with a plain ConvertFrom-Json in ~180ms.
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:committedReportJsonPath = Join-Path $repoRoot 'Reports/PfbApiDriftReport.json'
    $script:committedReportMdPath = Join-Path $repoRoot 'Reports/PfbApiDriftReport.md'
    $script:committedReport = Get-Content -Path $committedReportJsonPath -Raw | ConvertFrom-Json
    # The annotation SOURCE, so the guards below can compare the committed artifact against
    # the file it was generated from rather than against a hardcoded copy of its prose.
    $script:annotationSourcePath = Join-Path $repoRoot 'docs/drift-annotations.json'
    $script:annotationSource = Get-Content -Path $annotationSourcePath -Raw | ConvertFrom-Json
}

Describe 'Committed drift report (REGRESSION guard, no spec cache required)' {
    # An absolute path in these artifacts causes two concrete harms, both observed in the wild
    # before the original guards existed:
    #   1. It published a developer's home-directory path (`C:\Users\<name>\...`) to the repo --
    #      88 occurrences in each of PfbApiDriftReport.json and .md on main.
    #   2. It made the committed file depend on WHERE it was generated. Regenerating from a git
    #      worktree instead of the main checkout rewrote all 88 lines, producing 174 of 279 diff
    #      lines of pure churn that buried the 3 real changes under review.
    # `target.file` was always relative; `confidence.unresolvedParameters[].file` was not.

    It 'the committed report files exist and are tracked inputs, not a build cache' {
        # If this ever fails the rest of the block is meaningless, so it fails first and loudly
        # rather than letting the scans below pass vacuously over a missing file.
        Test-Path $committedReportJsonPath | Should -BeTrue
        Test-Path $committedReportMdPath | Should -BeTrue
        @($committedReport.parameterGaps).Count | Should -BeGreaterThan 0 -Because 'a report with no parameterGaps would make every scan below vacuous'
    }

    It 'emits no absolute path in any committed unresolvedParameters entry' {
        $scanned = 0
        $offenders = foreach ($g in $committedReport.parameterGaps) {
            foreach ($u in @($g.confidence.unresolvedParameters)) {
                $scanned++
                if ($u.file -and ($u.file -match '^[A-Za-z]:[\\/]' -or $u.file -match '^[\\/]{1,2}')) {
                    "$($g.endpoint) -$($u.parameter): $($u.file)"
                }
            }
        }
        $scanned | Should -BeGreaterThan 0 -Because 'a vacuous scan would pass this test without checking anything'
        @($offenders) | Should -BeNullOrEmpty -Because 'unresolvedParameters[].file must be repo-relative, like target.file'
    }

    It 'emits no absolute path in any committed enriched body-property target entry' {
        # NOTE: `target` hangs off each ENRICHED missingBodyProperties[] entry, not off the gap
        # itself. An earlier draft of the regenerating sibling read $g.target.file -- always
        # $null, so it passed vacuously and survived the mutation that broke its two siblings.
        # Assert a non-zero population so it can never silently go hollow again.
        $targets = foreach ($g in $committedReport.parameterGaps) {
            foreach ($p in @($g.missingBodyProperties)) {
                if ($p -isnot [string] -and $p.target -and $p.target.file) {
                    [pscustomobject]@{ Endpoint = $g.endpoint; Field = $p.name; File = $p.target.file }
                }
            }
        }
        @($targets).Count | Should -BeGreaterThan 0 -Because 'a vacuous scan would pass this test without checking anything'
        $offenders = @($targets | Where-Object { $_.File -match '^[A-Za-z]:[\\/]' -or $_.File -match '^[\\/]{1,2}' })
        $offenders | Should -BeNullOrEmpty
    }

    It 'leaks no absolute path into the committed rendered markdown report' {
        $md = Get-Content $committedReportMdPath -Raw
        [regex]::Matches($md, '[A-Za-z]:\\{1,2}Users').Count | Should -Be 0
        [regex]::Matches($md, '/home/runner').Count | Should -Be 0
        [regex]::Matches($md, '/Users/[^/\s]+/').Count | Should -Be 0
    }
}

Describe 'Committed drift report: annotations and summary fields survived generation' {
    # These three have spec-cache-gated counterparts that assert the same properties on a
    # REGENERATED report, which is the right check for "does the generator still wire this
    # through". The committed-file versions answer a different and equally real question --
    # "did the artifact we actually shipped keep them" -- and need no cache to do it, so they
    # run on every leg instead of none. Both are kept deliberately; this is not a duplicate.

    # WHY THESE TWO COMPARE AGAINST docs/drift-annotations.json RATHER THAN AGAINST LITERALS:
    # an earlier draft pinned one field name ('context_names') and one note's wording
    # ('not yet implemented'). Both move for legitimate reasons, and pinning them points the
    # guard the wrong way:
    #   - The notes are hand-written prose describing decisions that are still being made. A
    #     test asserting 'not yet implemented' fails on the very PR that implements the thing
    #     and reweords the note -- so the guard obstructs the change it should be indifferent to.
    #   - WHICH fields are annotated moves too. A field stops appearing in systemicGaps once
    #     the module starts sending it (see Get-PfbNonActionableParameters and
    #     Get-PfbCentralInjectionSites: continuation_token is already gone for exactly this
    #     reason). Naming one field makes an unrelated, correct improvement look like a
    #     regression.
    # What must never silently break -- and is what issue #63 was actually about -- is the
    # WIRING: a note in the source file reaching the committed artifact unmodified. That is
    # invariant under both kinds of movement, so it is what these assert. Each carries its own
    # non-vacuity floor, because an annotation set that matched nothing would otherwise pass
    # these by checking nothing at all.

    It 'carries every field annotation from docs/drift-annotations.json into the committed systemic gaps, verbatim' {
        $fieldNotes = @{}
        foreach ($a in $annotationSource.annotations) {
            if ($a.matchType -eq 'field') { $fieldNotes[$a.match] = $a.note }
        }
        $fieldNotes.Count | Should -BeGreaterThan 0 -Because 'docs/drift-annotations.json must carry at least one matchType=field annotation, or this test checks nothing'

        $checked = 0
        foreach ($gap in $committedReport.systemicGaps) {
            if (-not $fieldNotes.ContainsKey($gap.name)) { continue }
            $checked++
            @($gap.annotations).Count | Should -BeGreaterThan 0 -Because "'$($gap.name)' has a field annotation in docs/drift-annotations.json that did not reach the committed report"
            @($gap.annotations.note) | Should -Contain $fieldNotes[$gap.name] -Because "the committed note on '$($gap.name)' must be the source file's note verbatim, not a drifted copy"
        }
        $checked | Should -BeGreaterThan 0 -Because 'no annotated field appeared in systemicGaps at all -- either the annotation loader regressed, or every annotated field stopped being a gap. Both want a human to look; neither should pass silently.'
    }

    It 'carries every endpoint annotation from docs/drift-annotations.json into the committed parameter gaps, verbatim' {
        # matchType 'endpoint' matches as a case-insensitive SUBSTRING of '<METHOD> /<path>'
        # (docs/drift-annotations.json's own schema field says so). Matched with .Contains on
        # lowered strings rather than -like: a wildcard pattern treats ` as an escape
        # character and [ ] as a character class, so an endpoint or match value containing
        # either would be misread.
        $endpointAnnotations = @($annotationSource.annotations | Where-Object { $_.matchType -eq 'endpoint' })
        @($endpointAnnotations).Count | Should -BeGreaterThan 0 -Because 'docs/drift-annotations.json must carry at least one matchType=endpoint annotation, or this test checks nothing'

        $checked = 0
        foreach ($ann in $endpointAnnotations) {
            $needle = $ann.match.ToLowerInvariant()
            foreach ($row in $committedReport.parameterGaps) {
                if (-not $row.endpoint.ToLowerInvariant().Contains($needle)) { continue }
                $checked++
                @($row.annotations).Count | Should -BeGreaterThan 0 -Because "endpoint '$($row.endpoint)' matches the '$($ann.match)' annotation in docs/drift-annotations.json, which did not reach the committed report"
                @($row.annotations.note) | Should -Contain $ann.note -Because "the committed note on '$($row.endpoint)' must be the source file's note verbatim, not a drifted copy"
            }
        }
        $checked | Should -BeGreaterThan 0 -Because 'no annotated endpoint matched any parameter-gap row -- either the annotation matcher regressed, or every annotated endpoint stopped having a gap. Both want a human to look.'
    }

    It 'carries phantomFieldCount as a non-negative integer and a non-empty conventionStrength' {
        $committedReport.PSObject.Properties.Name | Should -Contain 'phantomFieldCount' -Because 'a property that vanished entirely would otherwise be indistinguishable from one holding zero'
        $committedReport.phantomFieldCount | Should -BeGreaterOrEqual 0
        @($committedReport.conventionStrength).Count | Should -BeGreaterThan 0 -Because 'an empty conventionStrength would make the committed report silently useless'
    }
}
