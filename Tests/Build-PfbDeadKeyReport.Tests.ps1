#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Regeneration gate for tools/Build-PfbDeadKeyReport.ps1 -- catches a STALE committed artifact.
.DESCRIPTION
    Tests/CommittedDeadKeyReport.Tests.ps1 reads only the committed
    Reports/PfbDeadKeyReport.json, so it runs on every CI leg but is blind to one thing: whether
    that artifact still reflects the code and the pinned spec. This file closes that hole by
    REGENERATING and comparing, and by driving the classifier over synthetic fixtures whose
    expected answers are known independently of the real repo's contents.

    TWO DESCRIBES, split on a dependency boundary: regeneration needs the real tools/specs
    cache, the real Public/ tree and the committed artifact; synthetic classification needs
    only a fixture it builds itself. One shared BeforeAll would have let a broken fixture red
    the two regeneration tests, reporting the real generator as broken when it was fine.
    The split itself moved no It between editions: both Describes are PS7-gated, so 5.1 skips
    every It in this file -- SIXTEEN of them today. That figure changes whenever an It is added
    here and is consumed by Tests/coverage-baseline.psd1; it read six until issue #141 Task 5
    added ten.

    WHY EVERY DESCRIBE CARRIES -Skip:($PSVersionTable.PSVersion.Major -lt 7):
    the generator carries `#Requires -Version 7.0`, so it cannot run on Windows PowerShell 5.1
    at all. It is invoked ONLY from a gated Describe's own BeforeAll. Do not add an ungated
    block to this file and do not move the BeforeAll to file scope: a `#Requires -Version 7.0`
    script pulled in by an UNGATED BeforeAll kills every test in the file with a CONTAINER
    FAILURE rather than skipping them. That happened in this repo, at a cost of 65 tests -- see
    the header of Tests/CommittedDriftReport.Tests.ps1 and the run-pester-tests skill.

    WHY A MISSING SPEC CACHE IS A HARD FAILURE AND NOT A SKIP:
    the PS7 version gate is a genuine, permanent property of the runner, so it is a real skip.
    An absent tools/specs cache is not. In CI it can never legitimately be absent -- the
    prepare-specs job builds it and both test legs download it -- so failing loudly there is
    never spurious. Locally, the hook that copies tools/specs into a new worktree FAILS OPEN,
    and "treat a skip as a failure" is a convention that depends on a human reading the run
    summary. A human not reading a summary is exactly what issue #63 was, and a silently
    hollow dead-key gate is exactly what the incident this whole gate exists to prevent looks
    like one level up. So the cache check throws.
#>

Describe 'Build-PfbDeadKeyReport regeneration (real spec cache required, PS7 only)' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {

    # SPLIT FROM THE SYNTHETIC BLOCK BELOW ON PURPOSE, and the seam is a dependency boundary
    # rather than a stylistic one: this half needs the real ~50MB tools/specs cache, the real
    # Public/ tree and the committed artifact; the half below needs a fixture and nothing else.
    # Sharing one BeforeAll made a throw anywhere red every test in the file, so a broken
    # FIXTURE would have reported the real generator as broken. Splitting also stops the
    # synthetic half depending on a cache it never reads. Both halves keep the PS7 gate, so the
    # split moved no It between editions -- 5.1 skips all sixteen (see the file header).

    BeforeAll {
        $script:repoRoot = Split-Path -Parent $PSScriptRoot
        $script:generatorPath = Join-Path $repoRoot 'tools/Build-PfbDeadKeyReport.ps1'
        $script:committedReportPath = Join-Path $repoRoot 'Reports/PfbDeadKeyReport.json'
        $script:specsDirectory = Join-Path $repoRoot 'tools/specs'

        # HARD FAILURE, not a skip -- see the header. Assert-PfbSpecCache.ps1 throws when the
        # directory is absent or holds fewer than its floor of fb*.json files.
        #
        # Deliberately NOT piped to Out-Null: that script reports its count with Write-Host,
        # which bypasses the pipeline, so the line would suppress nothing while reading as
        # though it did. Its "<path> contains N spec file(s)." appearing in the Pester output
        # is the useful confirmation that the cache this half depends on actually arrived.
        & (Join-Path $repoRoot 'scripts/Assert-PfbSpecCache.ps1') -SpecsDirectory $specsDirectory

        $script:regenWorkRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("PfbDeadKeyGate_" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $regenWorkRoot -Force | Out-Null

        $script:regeneratedPath = Join-Path $regenWorkRoot 'regenerated.json'
        & $generatorPath -OutputPath $regeneratedPath | Out-Null

        $script:regeneratedElsewherePath = Join-Path $regenWorkRoot 'regenerated-elsewhere.json'
        Push-Location $regenWorkRoot
        try {
            & $generatorPath -OutputPath $regeneratedElsewherePath | Out-Null
        }
        finally {
            Pop-Location
        }

        # Read the FRESH regeneration, never the committed artifact, for every classification
        # assertion below. The committed file is regenerated in a later task, so asserting
        # against it would make these tests report on the artifact's age rather than on the
        # classifier.
        $script:regeneratedReport = Get-Content -LiteralPath $regeneratedPath -Raw | ConvertFrom-Json
        $script:regeneratedDeadKeys = @($regeneratedReport.deadKeys)
    }

    AfterAll {
        # Its OWN variable, not a name shared with the block below -- a shared $script:workRoot
        # crossed exactly the boundary the split exists to isolate, and left this AfterAll able
        # to delete the other block's directory. Guarded with Get-Variable rather than a bare
        # truthiness test because this AfterAll still runs when BeforeAll threw before the
        # assignment (an absent spec cache does exactly that), and reading an undefined variable
        # would throw under StrictMode, turning a clear cache failure into a confusing second one.
        $existing = Get-Variable -Name 'regenWorkRoot' -Scope Script -ErrorAction SilentlyContinue
        if ($existing -and $existing.Value -and (Test-Path -LiteralPath $existing.Value)) {
            Remove-Item -LiteralPath $existing.Value -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'regenerates content-identically to the committed Reports/PfbDeadKeyReport.json' {
        # THE stale-artifact check. Reds when the generator, the Public/ cmdlets, or the pinned
        # spec moved without the artifact being regenerated and committed alongside them.
        #
        # BOTH SIDES ARE NEWLINE-NORMALISED -- both, not just the one that happened to break.
        # That is this repo's already-written answer to exactly this problem: see
        # Get-PfbSelectorArtifactHash at Tests/PfbPipelineSelectorRail.Tests.ps1:47-76, whose doc
        # comment names the CI run that hit it (31830362870) and ends "Normalise both, not the
        # one that happened to break." The committed blob is LF; the generator ends in
        # Set-Content, which emits [Environment]::NewLine, so a Windows regeneration is CRLF.
        # There is no .gitattributes in this repo, so a checkout's endings are whatever the
        # clone's core.autocrlf says -- CI is green on a raw byte compare only because
        # autocrlf=true on the Windows runners happens to make the checkout CRLF too. A
        # contributor with core.autocrlf=false or input would get an LF checkout against a CRLF
        # regeneration and be told "the committed artifact is stale", which is false, and would
        # commit a 53KB whitespace-only diff that then breaks the Linux legs.
        #
        # ReadAllText also drops a byte-order mark, which is correct here for the same reason it
        # is correct there: content is what this test asserts. Real content drift still reds --
        # a one-character change inside a wireKey was measured to fail this It after this
        # normalisation was added.
        #
        # The SECOND comparison below deliberately stays a RAW BYTE compare: both of its sides
        # are generator output on one platform with no checkout in between, so byte-for-byte is
        # both correct and strictly stronger there. Do not "make them consistent".
        $committedText = [System.IO.File]::ReadAllText($committedReportPath) -replace "`r`n", "`n"
        $regeneratedText = [System.IO.File]::ReadAllText($regeneratedPath) -replace "`r`n", "`n"
        $regeneratedText.Length | Should -Be $committedText.Length -Because "the committed artifact is stale: regenerating produced $($regeneratedText.Length) newline-normalised characters against the committed $($committedText.Length). Re-run tools/Build-PfbDeadKeyReport.ps1 and commit the result."

        # Located in the NORMALISED text, so the offset it reports is an offset into the thing
        # actually being compared rather than into the raw bytes.
        $firstDifference = -1
        for ($i = 0; $i -lt [Math]::Min($committedText.Length, $regeneratedText.Length); $i++) {
            if ($committedText[$i] -ne $regeneratedText[$i]) { $firstDifference = $i; break }
        }
        $context = ''
        if ($firstDifference -ge 0) {
            $start = [Math]::Max(0, $firstDifference - 40)
            $context = " Committed text around it: '" + $committedText.Substring($start, [Math]::Min(80, $committedText.Length - $start)) + "'."
        }
        $firstDifference | Should -Be -1 -Because "the committed artifact is stale: it first diverges from a fresh regeneration at normalised character $firstDifference.$context Re-run tools/Build-PfbDeadKeyReport.ps1 and commit the result."
    }

    It 'produces the same bytes when regenerated from a different working directory' {
        # Location independence, asserted rather than assumed: an absolute path or a
        # CWD-relative default leaking into the artifact makes a regeneration from a git
        # worktree rewrite lines that did not semantically change, burying the real diff.
        $fromRepoRoot = [System.IO.File]::ReadAllBytes($regeneratedPath)
        $fromElsewhere = [System.IO.File]::ReadAllBytes($regeneratedElsewherePath)
        $fromElsewhere.Length | Should -Be $fromRepoRoot.Length -Because 'the generated report must not depend on the process working directory'

        $firstDifference = -1
        for ($i = 0; $i -lt [Math]::Min($fromRepoRoot.Length, $fromElsewhere.Length); $i++) {
            if ($fromRepoRoot[$i] -ne $fromElsewhere[$i]) { $firstDifference = $i; break }
        }
        $firstDifference | Should -Be -1 -Because "regenerating from '$regenWorkRoot' instead of the repo root changed the output at byte $firstDifference -- the generator is resolving something against the working directory"
    }

    It 'classifies Get-PfbAlert -Flagged as WRONG-SURFACE with PATCH/Body provenance' {
        # THE anti-vacuity acceptance for the whole feature (issue #141 Task 5 Step 4).
        # `flagged` is a real PATCH /alerts body property, reachable ONLY through
        # $ref -> allOf -> $ref. Every synthetic fixture in this file could pass with a
        # one-level schema reader; this cannot -- such a reader sees ZERO properties on that
        # schema and would publish `classification: UNDECLARED`, a confident false assertion
        # that no operation on /alerts declares the key. The sibling It below proves that
        # one-level reader really does return zero, so this assertion is not merely "the
        # answer we happen to get".
        $entry = @($regeneratedDeadKeys | Where-Object { $_.cmdlet -eq 'Get-PfbAlert' -and $_.parameter -eq 'Flagged' })
        @($entry).Count | Should -Be 1 -Because "Get-PfbAlert -Flagged writes the query key 'flagged' on GET alerts, which does not declare it, so it must appear exactly once in deadKeys. Present dead keys for Get-PfbAlert: $(@($regeneratedDeadKeys | Where-Object cmdlet -eq 'Get-PfbAlert' | ForEach-Object { "$($_.parameter)/$($_.wireKey)" }) -join ', ')"
        $entry[0].wireKey | Should -Be 'flagged'
        $entry[0].method | Should -Be 'GET'
        $entry[0].endpoint | Should -Be 'alerts'
        $entry[0].classification | Should -Be 'WRONG-SURFACE' -Because "PATCH /alerts declares a body property named 'flagged', so the field exists and the cmdlet is sending it on the wrong surface. UNDECLARED here means the `$ref/allOf walk regressed to a one-level read. declaredElsewhere was: $(@($entry[0].declaredElsewhere | ForEach-Object { "$($_.method)/$($_.surface)" }) -join ', ')"

        $bodySites = @($entry[0].declaredElsewhere | Where-Object { $_.surface -eq 'Body' })
        @($bodySites).Count | Should -BeGreaterThan 0 -Because 'the classification is only meaningful with the provenance that justifies it'
        @($bodySites | ForEach-Object { $_.method }) | Should -Contain 'PATCH' -Because "PATCH is the verb whose body declares 'flagged'; a different verb would mean the index is reading the wrong operation"
    }

    It 'proves the $ref/allOf body walk is load-bearing: a one-level read of PATCH alerts sees no properties' {
        # THE CONTROL for the It above. An assertion that a walker "found flagged" cannot
        # distinguish a real allOf resolution from a schema that happened to declare it
        # inline -- so measure the cheap wrong implementation on the same input and require
        # it to DISAGREE. If this ever stops disagreeing, the spec changed shape and the
        # WRONG-SURFACE assertion above has quietly stopped proving anything.
        . (Join-Path $repoRoot 'tools/lib/PfbSpecTools.ps1')
        $capabilityMap = Get-Content -LiteralPath (Join-Path $repoRoot 'Data/PfbCapabilityMap.json') -Raw | ConvertFrom-Json -Depth 20
        $pinnedVersion = $capabilityMap.generatedFrom | Select-Object -Last 1
        $spec = Get-Content -LiteralPath (Join-Path $specsDirectory "fb$pinnedVersion.json") -Raw | ConvertFrom-Json -Depth 64

        $mediaSchema = $spec.paths."/api/$pinnedVersion/alerts".patch.requestBody.content.'application/json'.schema
        $mediaSchema | Should -Not -BeNullOrEmpty -Because 'the fixture-free control depends on PATCH /alerts having a JSON request body in the pinned spec'

        # The one-level reader: resolve the $ref once, then take .properties -- exactly the
        # implementation the plan rejects.
        $oneLevel = Resolve-PfbRef -Node $mediaSchema -Spec $spec
        $oneLevelNames = @(if ($oneLevel.properties) { $oneLevel.properties.PSObject.Properties.Name } else { @() })
        $oneLevelNames | Should -Not -Contain 'flagged' -Because "a one-level read must MISS 'flagged' for the WRONG-SURFACE assertion to be a real test of allOf resolution. It saw: [$($oneLevelNames -join ', ')]"

        # -MaxDepth 32 states the depth the generator inherits, but this call does NOT exercise
        # it: measured, the walker at its SIGNATURE DEFAULT of 8 also returns all 18 properties
        # of PATCH /alerts including 'flagged', so 32-vs-8 is unobservable at this call site.
        # The issue #71 truncation lives in the fb2.12-2.16 allOf chains, not this one -- do not
        # read this line as a demonstration of that hazard.
        $walked = @(Get-PfbSchemaPropertyNames -Schema $mediaSchema -Spec $spec -MaxDepth 32)
        $walked | Should -Contain 'flagged' -Because "Get-PfbSchemaPropertyNames resolves `$ref and allOf, so it must see the property the one-level read missed. It saw: [$($walked -join ', ')]"
    }

    It 'classifies New-PfbCertificateSigningRequest -Name as UNDECLARED with an empty provenance array' {
        # The counterweight to the Flagged case: same generator, same index, opposite answer.
        # POST certificates/certificate-signing-requests is the endpoint's ONLY operation and
        # declares zero query keys; its body declares common_name and friends but no 'names'.
        # So nothing on the endpoint declares the key on either surface -- and that is the one
        # classification that is a positive assertion of absence.
        $entry = @($regeneratedDeadKeys | Where-Object { $_.cmdlet -eq 'New-PfbCertificateSigningRequest' -and $_.parameter -eq 'Name' })
        @($entry).Count | Should -Be 1 -Because "New-PfbCertificateSigningRequest -Name writes 'names' on POST certificates/certificate-signing-requests, which declares no query keys at all"
        $entry[0].wireKey | Should -Be 'names'
        $entry[0].method | Should -Be 'POST'
        $entry[0].classification | Should -Be 'UNDECLARED' -Because "nothing on this endpoint declares 'names' on either surface. declaredElsewhere was: $(@($entry[0].declaredElsewhere | ForEach-Object { "$($_.method)/$($_.surface)" }) -join ', ')"
        @($entry[0].declaredElsewhere).Count | Should -Be 0 -Because 'UNDECLARED must carry an empty array, never a populated one'
        $null -ne $entry[0].declaredElsewhere | Should -BeTrue -Because 'and never null -- a consumer reading null cannot tell "no declaration anywhere" from "this generator did not look"'
    }

    It 'gives every real dead key a classification from the closed vocabulary, consistent with its provenance' {
        # A whole-population invariant rather than a count pin (counts are re-baselined in a
        # later task). It is the assertion that catches a record the classifier skipped
        # entirely, which the two named-cmdlet tests above cannot see.
        @($regeneratedDeadKeys).Count | Should -BeGreaterThan 0 -Because 'a zero-length population would make every assertion in this It vacuously true -- this is the control, not a smoke test'

        $offenders = [System.Collections.Generic.List[string]]::new()
        foreach ($record in $regeneratedDeadKeys) {
            $sites = @($record.declaredElsewhere)
            $hasBody = @($sites | Where-Object { $_.surface -eq 'Body' }).Count -gt 0
            $hasOtherVerbQuery = @($sites | Where-Object { $_.surface -eq 'Query' -and $_.method -ne $record.method }).Count -gt 0
            $expected = if ($hasBody) { 'WRONG-SURFACE' } elseif ($hasOtherVerbQuery) { 'WRONG-VERB' } else { 'UNDECLARED' }
            $identity = "$($record.cmdlet)|$($record.parameter)"

            if ($record.classification -notin @('WRONG-SURFACE', 'WRONG-VERB', 'UNDECLARED')) {
                $offenders.Add("$identity has classification '$($record.classification)', outside the closed vocabulary")
                continue
            }
            if ($record.classification -ne $expected) {
                $offenders.Add("$identity is '$($record.classification)' but its provenance [$(@($sites | ForEach-Object { "$($_.method)/$($_.surface)" }) -join ', ')] implies '$expected'")
            }
            # Sorted by method then surface, ORDINALLY, deduplicated. Recomputed here rather
            # than trusted.
            #
            # NOT for byte-order reasons. An earlier version of this comment claimed a duplicate
            # (method, surface) pair would make the artifact's byte order depend on .NET's
            # introsort partitioning; that was measured false and retracted here and at the dedup
            # site in tools/Build-PfbDeadKeyReport.ps1. A site object carries only Method and
            # Surface and the projection emits only those two, so a tie on both sort keys is a tie
            # on the ENTIRE serialised record -- an unstable sort cannot reorder byte-identical
            # elements observably. What a duplicate actually produces is a WRONG ROW, and the
            # assertion below is what catches it.
            $keys = @($sites | ForEach-Object { "$($_.method)|$($_.surface)" })
            if (@($keys | Select-Object -Unique).Count -ne $keys.Count) {
                $offenders.Add("$identity has a duplicated declaredElsewhere entry: [$($keys -join ', ')]")
            }
            for ($i = 1; $i -lt $keys.Count; $i++) {
                if ([string]::Compare($keys[$i - 1], $keys[$i], [System.StringComparison]::Ordinal) -ge 0) {
                    $offenders.Add("$identity has declaredElsewhere out of ordinal method-then-surface order: [$($keys -join ', ')]")
                }
            }
        }

        @($offenders) -join '; ' | Should -BeNullOrEmpty
    }
}

Describe 'Build-PfbDeadKeyReport classification (synthetic fixture, no spec cache, PS7 only)' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {

    BeforeAll {
        $script:repoRoot = Split-Path -Parent $PSScriptRoot
        $script:generatorPath = Join-Path $repoRoot 'tools/Build-PfbDeadKeyReport.ps1'
        $script:fixtureWorkRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("PfbDeadKeyFixture_" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $fixtureWorkRoot -Force | Out-Null

        # No Assert-PfbSpecCache call here, and that is the point of the split: every input this
        # block reads is built below, so the real cache is irrelevant to it.
        # EVERY spec fixture node is a [PSCustomObject], never a bare @{}. Resolve-PfbRef's loop
        # condition tests `$current.PSObject.Properties.Name -contains '$ref'`, which NEVER
        # matches on a hashtable, so a @{} fixture silently drops every $ref'd parameter and the
        # test passes while proving nothing (the trap is noted in tools/lib/PfbSpecTools.ps1).
        # The fixture is serialised to disk here because the generator loads its spec from a
        # file -- keeping the in-memory shape correct anyway means this fixture stays valid if
        # it is ever handed to Resolve-PfbRef directly, and preserves property order.
        #
        # 'synthetic/dead' DELETE declares its 'names' parameter THROUGH A $ref on purpose: if
        # ref resolution ever regressed, 'names' would read as undeclared, the surviving
        # selector would vanish, and assertion 3's cmdlet would wrongly join noSurvivingSelector.
        # That makes the hollow-fixture trap detectable rather than silent.
        $script:fixtureVersion = '9.9'
        $script:fixtureSpecsDirectory = Join-Path $fixtureWorkRoot 'specs'
        $script:fixturePublicDirectory = Join-Path $fixtureWorkRoot 'Public'
        New-Item -ItemType Directory -Path $fixtureSpecsDirectory -Force | Out-Null
        New-Item -ItemType Directory -Path $fixturePublicDirectory -Force | Out-Null

        $fixtureSpec = [PSCustomObject]@{
            components = [PSCustomObject]@{
                parameters = [PSCustomObject]@{
                    NamesParam = [PSCustomObject]@{ name = 'names'; 'in' = 'query' }
                }
                schemas    = [PSCustomObject]@{
                    # DELIBERATELY TWO LEVELS OF INDIRECTION, mirroring the real Alert schema:
                    # the operation's requestBody holds a bare $ref to SyntheticSurfacePatch,
                    # whose ONLY key is allOf, whose branch is a $ref to the schema that
                    # actually declares 'flagged'. A reader that resolves the first $ref and
                    # then takes .properties gets an EMPTY LIST, so the wrong-surface fixture
                    # below would classify UNDECLARED and this whole Describe would pass while
                    # proving the opposite of what it claims. The real-spec control in the
                    # sibling Describe covers the same hazard against fb<version>; this covers
                    # it without the ~50MB cache.
                    SyntheticSurfacePatch   = [PSCustomObject]@{
                        allOf = @(
                            [PSCustomObject]@{ '$ref' = '#/components/schemas/SyntheticSurfaceBase' }
                        )
                    }
                    SyntheticSurfaceBase    = [PSCustomObject]@{
                        properties = [PSCustomObject]@{
                            # SPELT 'Flagged' WHILE THE CMDLET SENDS 'flagged', on purpose. The
                            # deadness gate itself uses PowerShell's -contains, which is
                            # case-INSENSITIVE, so an index that matched case-sensitively would
                            # be STRICTER than the gate it exists to explain: it would report
                            # UNDECLARED -- a positive assertion of absence -- about a key the
                            # same generator would have called declared. This spelling makes
                            # that regression fail a test instead of publishing a false claim.
                            Flagged          = [PSCustomObject]@{ type = 'boolean' }
                            other_body_field = [PSCustomObject]@{ type = 'string' }
                        }
                    }
                    # Used by BOTH endpoint-case fixtures below, so the mixed-case case and its
                    # lowercase control differ in exactly one thing: the case of the endpoint.
                    SyntheticEndpointPatch  = [PSCustomObject]@{
                        properties = [PSCustomObject]@{
                            archived = [PSCustomObject]@{ type = 'boolean' }
                            # A *_names BODY property on an endpoint that no dead key resolves
                            # to. Nothing in this fixture needs it declared; it exists so that a
                            # Body lookup widened from the record's own endpoint to a union over
                            # the whole index -- even one narrowed to *_names keys -- finds
                            # 'policy_names' here and hands Remove-PfbSyntheticDeadKey's dead
                            # PolicyName a Body provenance it cannot have. Without this line that
                            # widening is an equivalent mutant.
                            policy_names = [PSCustomObject]@{ type = 'array' }
                        }
                    }
                    SyntheticUndeclaredPost = [PSCustomObject]@{
                        properties = [PSCustomObject]@{
                            other_field = [PSCustomObject]@{ type = 'string' }
                        }
                    }
                }
            }
            paths      = [PSCustomObject]@{
                # WRONG-SURFACE case. GET declares only 'limit', so a GET sending 'flagged' is
                # dead. Three other declaration sites exist on the SAME path so the provenance
                # list exercises both sort keys and the Body-over-Query priority at once:
                # DELETE declares 'flagged' as a query key, and PATCH declares it BOTH as a
                # query key and (through the allOf chain above) as a body property. Ordinal
                # method-then-surface order is therefore DELETE/Query, PATCH/Body, PATCH/Query.
                "/api/$fixtureVersion/synthetic/surface"     = [PSCustomObject]@{
                    get    = [PSCustomObject]@{
                        parameters = @(
                            [PSCustomObject]@{ name = 'limit'; 'in' = 'query' }
                        )
                    }
                    patch  = [PSCustomObject]@{
                        parameters  = @(
                            [PSCustomObject]@{ name = 'flagged'; 'in' = 'query' }
                        )
                        requestBody = [PSCustomObject]@{
                            content = [PSCustomObject]@{
                                'application/json' = [PSCustomObject]@{
                                    schema = [PSCustomObject]@{ '$ref' = '#/components/schemas/SyntheticSurfacePatch' }
                                }
                            }
                        }
                    }
                    delete = [PSCustomObject]@{
                        parameters = @(
                            # 'FLAGGED' for the same reason SyntheticSurfaceBase spells its
                            # property 'Flagged': the QUERY half of the index must be exactly as
                            # case-tolerant as the -contains gate, and the only way to assert
                            # that is a fixture whose case differs from the key being looked up.
                            [PSCustomObject]@{ name = 'FLAGGED'; 'in' = 'query' }
                        )
                    }
                }
                # WRONG-VERB case. Nothing on this path declares a body at all, so the only
                # possible provenance is a query declaration under another verb.
                "/api/$fixtureVersion/synthetic/verb"        = [PSCustomObject]@{
                    get    = [PSCustomObject]@{
                        parameters = @(
                            [PSCustomObject]@{ name = 'limit'; 'in' = 'query' }
                        )
                    }
                    delete = [PSCustomObject]@{
                        parameters = @(
                            [PSCustomObject]@{ name = 'destroyed'; 'in' = 'query' }
                        )
                    }
                }
                # UNDECLARED case. The only operation declares 'limit' as its query key and
                # 'other_field' as its only body property, so 'names' appears nowhere.
                "/api/$fixtureVersion/synthetic/undeclared"  = [PSCustomObject]@{
                    post = [PSCustomObject]@{
                        parameters  = @(
                            [PSCustomObject]@{ name = 'limit'; 'in' = 'query' }
                        )
                        requestBody = [PSCustomObject]@{
                            content = [PSCustomObject]@{
                                'application/json' = [PSCustomObject]@{
                                    schema = [PSCustomObject]@{ '$ref' = '#/components/schemas/SyntheticUndeclaredPost' }
                                }
                            }
                        }
                    }
                }
                # ENDPOINT-CASE PAIR. Both paths are spelt lower-case here; the cmdlets below
                # send 'Widgets' (mixed) and 'gadgets' (lower). The declaration index is keyed
                # on the endpoint, and the deadness gate reaches the spec through PSObject
                # property access on a ConvertFrom-Json object, which is case-INSENSITIVE -- so
                # a record whose -Endpoint literal differs in case from the spec path key
                # passes the gate and reaches classification. An ordinal-exact endpoint key
                # would then miss the index entirely and publish UNDECLARED: an assertion of
                # absence about a key this same generator can see. The pair makes that
                # difference observable; without the lowercase control, a red could equally
                # mean the fixture itself is malformed.
                "/api/$fixtureVersion/widgets"              = [PSCustomObject]@{
                    get   = [PSCustomObject]@{
                        parameters = @(
                            [PSCustomObject]@{ name = 'limit'; 'in' = 'query' }
                        )
                    }
                    patch = [PSCustomObject]@{
                        requestBody = [PSCustomObject]@{
                            content = [PSCustomObject]@{
                                'application/json' = [PSCustomObject]@{
                                    schema = [PSCustomObject]@{ '$ref' = '#/components/schemas/SyntheticEndpointPatch' }
                                }
                            }
                        }
                    }
                }
                "/api/$fixtureVersion/gadgets"              = [PSCustomObject]@{
                    get   = [PSCustomObject]@{
                        parameters = @(
                            [PSCustomObject]@{ name = 'limit'; 'in' = 'query' }
                        )
                    }
                    patch = [PSCustomObject]@{
                        requestBody = [PSCustomObject]@{
                            content = [PSCustomObject]@{
                                'application/json' = [PSCustomObject]@{
                                    schema = [PSCustomObject]@{ '$ref' = '#/components/schemas/SyntheticEndpointPatch' }
                                }
                            }
                        }
                    }
                }
                # Exists only so the audited-control fixture's OTHER parameter resolves to a
                # DECLARED key. Without it that cmdlet's -Name would be skipped as
                # 'endpoint/verb absent from spec' and the skip-accounting assertions would be
                # measuring the wrong bucket.
                "/api/$fixtureVersion/synthetic/allow"       = [PSCustomObject]@{
                    delete = [PSCustomObject]@{
                        parameters = @(
                            [PSCustomObject]@{ name = 'names'; 'in' = 'query' }
                            # The QUERY counterpart of the *_names body property above, on a
                            # DIFFERENT endpoint from the one whose dead PolicyName resolves. It
                            # closes the sibling widening: a Body site synthesised because SOME
                            # endpoint declares the key as a query key. Query-declared here and
                            # nowhere on synthetic/dead, so the unmutated generator must still
                            # report UNDECLARED with no provenance.
                            [PSCustomObject]@{ name = 'policy_names'; 'in' = 'query' }
                        )
                    }
                }
                "/api/$fixtureVersion/synthetic/dead"        = [PSCustomObject]@{
                    delete = [PSCustomObject]@{
                        parameters = @(
                            [PSCustomObject]@{ '$ref' = '#/components/parameters/NamesParam' }
                        )
                    }
                }
                "/api/$fixtureVersion/synthetic/no-selector" = [PSCustomObject]@{
                    delete = [PSCustomObject]@{
                        parameters = @(
                            [PSCustomObject]@{ name = 'ids'; 'in' = 'query' }
                        )
                    }
                }
                "/api/$fixtureVersion/synthetic/paging"      = [PSCustomObject]@{
                    get = [PSCustomObject]@{
                        parameters = @(
                            [PSCustomObject]@{ name = 'names'; 'in' = 'query' }
                        )
                    }
                }
                "/api/$fixtureVersion/synthetic/context"     = [PSCustomObject]@{
                    get = [PSCustomObject]@{
                        parameters = @(
                            [PSCustomObject]@{ name = 'names'; 'in' = 'query' }
                        )
                    }
                }
            }
        }
        $fixtureSpec | ConvertTo-Json -Depth 20 |
            Set-Content -LiteralPath (Join-Path $fixtureSpecsDirectory "fb$fixtureVersion.json") -Encoding UTF8

        # DERIVED FROM THE FIXTURE, never hand-listed. The anti-leak assertion below excludes
        # the endpoints that legitimately have a Body provenance, and a hand-maintained literal
        # would make the mechanical response to a red "append the offending endpoint" -- a
        # one-token edit indistinguishable from a legitimate one, which disables the gate
        # exactly the way a comment asking for conscious review cannot prevent. Deriving it
        # means an unjustified addition is impossible to make, and a fixture path that LOSES
        # its request body cannot leave a stale over-broad exclusion behind.
        #
        # ONE COST OF THE SWAP, recorded rather than discovered later: the derived set is strictly
        # LARGER than the hand-written literal it replaced -- it newly excludes
        # 'synthetic/undeclared', which does declare a requestBody and which the literal had
        # omitted. So a Body-provenance leak on that endpoint is now invisible to the anti-leak
        # assertion below, and is caught only per-record by the classification assertions further
        # down in the UNDECLARED test. That compensation is per-record: a SECOND dead key on
        # 'synthetic/undeclared' would have neither guard. The derivation is still the right trade
        # -- the literal's omission was itself a latent false-red -- but the exclusion did widen.
        $script:fixtureBodyBearingEndpoints = @(
            foreach ($pathProperty in $fixtureSpec.paths.PSObject.Properties) {
                $declaresBody = $false
                foreach ($operationProperty in $pathProperty.Value.PSObject.Properties) {
                    if ($operationProperty.Value.PSObject.Properties.Name -contains 'requestBody') {
                        $declaresBody = $true
                    }
                }
                if ($declaresBody) {
                    $pathProperty.Name -replace ('^/api/' + [regex]::Escape($fixtureVersion) + '/'), ''
                }
            }
        )

        $fixtureCapabilityMapPath = Join-Path $fixtureWorkRoot 'PfbFixtureCapabilityMap.json'
        ([PSCustomObject]@{ generatedFrom = @($fixtureVersion) } | ConvertTo-Json -Depth 5) |
            Set-Content -LiteralPath $fixtureCapabilityMapPath -Encoding UTF8

        # A DESTRUCTIVE dead key ('policy_names') alongside a SURVIVING selector ('names'), so
        # this operation must be reported as a dead key and must NOT be a no-surviving-selector.
        Set-Content -LiteralPath (Join-Path $fixturePublicDirectory 'Remove-PfbSyntheticDeadKey.ps1') -Encoding UTF8 -Value @'
function Remove-PfbSyntheticDeadKey {
    [CmdletBinding()]
    param(
        [Parameter()] [string[]]$Name,
        [Parameter()] [string[]]$PolicyName,
        [Parameter()] [PSCustomObject]$Array
    )
    $queryParams = @{ 'names' = $Name; 'policy_names' = $PolicyName }
    Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'synthetic/dead' -QueryParams $queryParams
}
'@

        # Its ONLY selector is dead, so the DELETE would arrive unselected -- the motivating
        # incident's exact shape.
        Set-Content -LiteralPath (Join-Path $fixturePublicDirectory 'Remove-PfbSyntheticNoSelector.ps1') -Encoding UTF8 -Value @'
function Remove-PfbSyntheticNoSelector {
    [CmdletBinding()]
    param(
        [Parameter()] [string[]]$MemberName,
        [Parameter()] [PSCustomObject]$Array
    )
    $queryParams = @{ 'member_names' = $MemberName }
    Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'synthetic/no-selector' -QueryParams $queryParams
}
'@

        # A dead PAGING key. Wrong results, but nothing about it is a selector.
        Set-Content -LiteralPath (Join-Path $fixturePublicDirectory 'Get-PfbSyntheticPaging.ps1') -Encoding UTF8 -Value @'
function Get-PfbSyntheticPaging {
    [CmdletBinding()]
    param(
        [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )
    $queryParams = @{ 'limit' = $Limit }
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'synthetic/paging' -QueryParams $queryParams
}
'@

        # context_names is Fusion FLEET ROUTING, not a selector: dropping it changes which
        # array answers, never which objects are acted on.
        Set-Content -LiteralPath (Join-Path $fixturePublicDirectory 'Get-PfbSyntheticContext.ps1') -Encoding UTF8 -Value @'
function Get-PfbSyntheticContext {
    [CmdletBinding()]
    param(
        [Parameter()] [string[]]$ContextName,
        [Parameter()] [PSCustomObject]$Array
    )
    $queryParams = @{ 'context_names' = $ContextName }
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'synthetic/context' -QueryParams $queryParams
}
'@

        # ---- issue #141 Task 5 fixtures -------------------------------------------------
        # EVERY parameter name below is decoupled from the wire key it writes (-Marked writes
        # 'flagged', -Gone writes 'destroyed', -Title writes 'names'), so an implementation that
        # guessed the key from the parameter name cannot pass. The classification under test is
        # a property of the KEY against the spec, so a coincidental name match would make each
        # of these tests unable to tell reading from guessing.
        #
        # -Unresolvable is the planted non-zero control for the 'wire name unresolved' bucket:
        # it is typed, its declaring function DOES issue Invoke-PfbApiRequest, and it appears
        # nowhere in the payload, so it is a genuine resolution failure. Without it, an
        # assertion that the two NEW buckets are non-zero could not distinguish a working
        # classifier from a skip counter that increments everything it sees.
        Set-Content -LiteralPath (Join-Path $fixturePublicDirectory 'Get-PfbSyntheticWrongSurface.ps1') -Encoding UTF8 -Value @'
function Get-PfbSyntheticWrongSurface {
    [CmdletBinding()]
    param(
        [Parameter()] [bool]$Marked,
        [Parameter()] [string]$Unresolvable,
        [Parameter()] [PSCustomObject]$Array
    )
    $queryParams = @{ 'flagged' = $Marked }
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'synthetic/surface' -QueryParams $queryParams
}
'@

        Set-Content -LiteralPath (Join-Path $fixturePublicDirectory 'Get-PfbSyntheticWrongVerb.ps1') -Encoding UTF8 -Value @'
function Get-PfbSyntheticWrongVerb {
    [CmdletBinding()]
    param(
        [Parameter()] [bool]$Gone,
        [Parameter()] [PSCustomObject]$Array
    )
    $queryParams = @{ 'destroyed' = $Gone }
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'synthetic/verb' -QueryParams $queryParams
}
'@

        Set-Content -LiteralPath (Join-Path $fixturePublicDirectory 'New-PfbSyntheticUndeclared.ps1') -Encoding UTF8 -Value @'
function New-PfbSyntheticUndeclared {
    [CmdletBinding()]
    param(
        [Parameter()] [string[]]$Title,
        [Parameter()] [PSCustomObject]$Array
    )
    $queryParams = @{ 'names' = $Title }
    Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'synthetic/undeclared' -QueryParams $queryParams
}
'@

        # 'OutsideStandardRequest' fixture: NO Invoke-PfbApiRequest call anywhere in the body,
        # which is the whole structural fact Test-PfbFunctionMakesStandardRequest measures
        # (tools/lib/PfbCmdletParamTools.ps1:1630). Two parameters, so the bucket it feeds is
        # distinguishable from a bucket that happens to be 1.
        Set-Content -LiteralPath (Join-Path $fixturePublicDirectory 'Set-PfbSyntheticNoRequest.ps1') -Encoding UTF8 -Value @'
function Set-PfbSyntheticNoRequest {
    [CmdletBinding()]
    param(
        [Parameter()] [string]$Alpha,
        [Parameter()] [string]$Beta
    )
    $script:PfbSyntheticState = @{ Alpha = $Alpha; Beta = $Beta }
}
'@

        # 'NotWireParameter' fixture, and it MUST be named Remove-PfbBucket with a parameter
        # named Eradicate: the allowlist is keyed on the exact 'Cmdlet|Parameter' identity
        # ('{0}|{1}' -f $funcAst.Name, $paramName at tools/lib/PfbCmdletParamTools.ps1:1781), so
        # no invented synthetic name can reach that state. It also has to issue a real
        # Invoke-PfbApiRequest, because 'OutsideStandardRequest' is tested FIRST in the same
        # ladder and would otherwise absorb both parameters and hide this state entirely.
        # -Name writes the DECLARED key 'names' on DELETE synthetic/allow, so it is not dead
        # and does not perturb the dead-key assertions.
        Set-Content -LiteralPath (Join-Path $fixturePublicDirectory 'Remove-PfbBucket.ps1') -Encoding UTF8 -Value @'
function Remove-PfbBucket {
    [CmdletBinding()]
    param(
        [Parameter()] [string[]]$Name,
        [Parameter()] [switch]$Eradicate,
        [Parameter()] [PSCustomObject]$Array
    )
    if (-not $Eradicate) { throw 'refusing to remove without -Eradicate' }
    $queryParams = @{ 'names' = $Name }
    Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'synthetic/allow' -QueryParams $queryParams
}
'@

        # The endpoint-case pair. -Endpoint 'Widgets' vs the spec's '/api/9.9/widgets' is the
        # ONLY difference between these two cmdlets; 'gadgets' is the lowercase control, and it
        # must classify identically under shipped code and stay green under an ordinal-exact
        # index, so a red on the mixed-case one can only mean the case divergence.
        Set-Content -LiteralPath (Join-Path $fixturePublicDirectory 'Get-PfbSyntheticMixedCaseEndpoint.ps1') -Encoding UTF8 -Value @'
function Get-PfbSyntheticMixedCaseEndpoint {
    [CmdletBinding()]
    param(
        [Parameter()] [bool]$Stowed,
        [Parameter()] [PSCustomObject]$Array
    )
    $queryParams = @{ 'archived' = $Stowed }
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'Widgets' -QueryParams $queryParams
}
'@

        Set-Content -LiteralPath (Join-Path $fixturePublicDirectory 'Get-PfbSyntheticLowerCaseEndpoint.ps1') -Encoding UTF8 -Value @'
function Get-PfbSyntheticLowerCaseEndpoint {
    [CmdletBinding()]
    param(
        [Parameter()] [bool]$Stowed,
        [Parameter()] [PSCustomObject]$Array
    )
    $queryParams = @{ 'archived' = $Stowed }
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'gadgets' -QueryParams $queryParams
}
'@

        $script:syntheticReportPath = Join-Path $fixtureWorkRoot 'synthetic.json'
        & $generatorPath `
            -SpecsDirectory $fixtureSpecsDirectory `
            -PublicDirectory $fixturePublicDirectory `
            -CapabilityMapPath $fixtureCapabilityMapPath `
            -OutputPath $syntheticReportPath | Out-Null
        $script:syntheticReport = Get-Content -LiteralPath $syntheticReportPath -Raw | ConvertFrom-Json

        $script:syntheticDeadKeyText = @(@($syntheticReport.deadKeys) | ForEach-Object {
            "$($_.severity) $($_.cmdlet) -$($_.parameter) -> '$($_.wireKey)' on $($_.method) $($_.endpoint) (declared: $(@($_.declared) -join ', '))"
        }) -join '; '
        $script:syntheticNssText = @(@($syntheticReport.noSurvivingSelector) | ForEach-Object {
            "$($_.cmdlet) $($_.method) $($_.endpoint)"
        }) -join '; '
        # Rendered once so every skip-accounting failure message below carries the WHOLE
        # bucket table. A failure that reports only the bucket it asserted on cannot tell
        # "the state was not detected" from "it was counted in the wrong bucket", which is
        # precisely the confusion Task 4's two new states exist to remove.
        $script:syntheticSkipReasons = $syntheticReport.counts.skipReasons
        $script:syntheticSkipText = @(@($syntheticSkipReasons.PSObject.Properties) | ForEach-Object {
            "$($_.Name)=$($_.Value)"
        }) -join ', '
    }

    AfterAll {
        # Its own variable and its own guard -- see the note on the sibling block's AfterAll.
        $existing = Get-Variable -Name 'fixtureWorkRoot' -Scope Script -ErrorAction SilentlyContinue
        if ($existing -and $existing.Value -and (Test-Path -LiteralPath $existing.Value)) {
            Remove-Item -LiteralPath $existing.Value -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'classifies a synthetic undeclared query key as a dead key, with the verb-derived severity' {
        $entry = @(@($syntheticReport.deadKeys) | Where-Object { $_.cmdlet -eq 'Remove-PfbSyntheticDeadKey' -and $_.parameter -eq 'PolicyName' })
        @($entry).Count | Should -Be 1 -Because "Remove-PfbSyntheticDeadKey -PolicyName writes 'policy_names' on DELETE synthetic/dead, which declares only 'names', so it must be reported exactly once. Reported dead keys were: $syntheticDeadKeyText"
        $entry[0].severity | Should -Be 'DESTRUCTIVE' -Because "DELETE is destructive, so an undeclared key on it must be classified DESTRUCTIVE, not $($entry[0].severity)"
        $entry[0].wireKey | Should -Be 'policy_names'
        $entry[0].method | Should -Be 'DELETE'
        $entry[0].endpoint | Should -Be 'synthetic/dead'
        @($entry[0].declared) | Should -Be @('names') -Because "the declared-key list is what a reader fixes the cmdlet from, and it must survive `$ref resolution -- 'names' is declared on this fixture THROUGH a `$ref"

        $surviving = @(@($syntheticReport.deadKeys) | Where-Object { $_.cmdlet -eq 'Remove-PfbSyntheticDeadKey' -and $_.parameter -eq 'Name' })
        @($surviving) | Should -BeNullOrEmpty -Because "-Name writes the declared key 'names', so it is not dead; if it is reported dead then `$ref resolution regressed and this whole fixture is hollow"
    }

    It 'reports a synthetic cmdlet whose only selector is dead as noSurvivingSelector' {
        $group = @(@($syntheticReport.noSurvivingSelector) | Where-Object { $_.cmdlet -eq 'Remove-PfbSyntheticNoSelector' })
        @($group).Count | Should -Be 1 -Because "Remove-PfbSyntheticNoSelector -MemberName writes 'member_names' on DELETE synthetic/no-selector, which declares only 'ids'. Its only selector is dead, so the DELETE arrives unselected -- the motivating incident. Reported groups were: $syntheticNssText"
        $group[0].method | Should -Be 'DELETE'
        $group[0].endpoint | Should -Be 'synthetic/no-selector'
    }

    It 'does not report a paging-only dead key as noSurvivingSelector' {
        # A dead 'limit' returns the wrong page, never the wrong objects. Folding it into the
        # highest-severity class would drown the entries that actually mean "unselected write".
        @(@($syntheticReport.deadKeys) | Where-Object { $_.cmdlet -eq 'Get-PfbSyntheticPaging' }).Count |
            Should -Be 1 -Because "the fixture is only meaningful if 'limit' IS reported dead on GET synthetic/paging. Reported dead keys were: $syntheticDeadKeyText"
        @(@($syntheticReport.noSurvivingSelector) | Where-Object { $_.cmdlet -eq 'Get-PfbSyntheticPaging' }) |
            Should -BeNullOrEmpty -Because "'limit' is a paging key, not a selector, so a cmdlet whose only dead key is 'limit' must not be reported as having no surviving selector. Reported groups were: $syntheticNssText"
    }

    It 'does not report a context_names-only dead key as noSurvivingSelector' {
        # context_names is Fusion fleet ROUTING -- it chooses which array answers, not which
        # objects are acted on. Test-PfbDeadKeySelectorName excludes it by exact name for this
        # reason, and a suffix regex on '_names' would wrongly catch it.
        @(@($syntheticReport.deadKeys) | Where-Object { $_.cmdlet -eq 'Get-PfbSyntheticContext' }).Count |
            Should -Be 1 -Because "the fixture is only meaningful if 'context_names' IS reported dead on GET synthetic/context. Reported dead keys were: $syntheticDeadKeyText"
        @(@($syntheticReport.noSurvivingSelector) | Where-Object { $_.cmdlet -eq 'Get-PfbSyntheticContext' }) |
            Should -BeNullOrEmpty -Because "context_names is a fleet-routing key, not a selector, so it must never make a cmdlet look as though it has no surviving selector. Reported groups were: $syntheticNssText"
    }

    It 'classifies a key declared as a body property under another verb as WRONG-SURFACE' {
        # Step 1-2. 'flagged' is dead on GET synthetic/surface (which declares only 'limit'),
        # and is declared THREE other ways on the same path: DELETE query, PATCH query, and
        # PATCH body through $ref -> allOf -> $ref. Body must win the priority ladder even
        # though a wrong-verb QUERY declaration also exists, because "you sent a body field as
        # a query parameter" is the actionable diagnosis.
        $entry = @(@($syntheticReport.deadKeys) | Where-Object { $_.cmdlet -eq 'Get-PfbSyntheticWrongSurface' -and $_.parameter -eq 'Marked' })
        @($entry).Count | Should -Be 1 -Because "-Marked writes 'flagged' on GET synthetic/surface, which declares only 'limit'. Reported dead keys were: $syntheticDeadKeyText"
        $entry[0].wireKey | Should -Be 'flagged' -Because 'the parameter is named Marked, so a key of "marked" would mean the resolver guessed from the name instead of reading the payload literal'
        $entry[0].classification | Should -Be 'WRONG-SURFACE' -Because "PATCH synthetic/surface declares 'flagged' as a body property, reachable only through `$ref -> allOf -> `$ref. UNDECLARED here means the fixture's allOf chain was not resolved; WRONG-VERB means Body lost the priority ladder to the DELETE/PATCH query declarations. declaredElsewhere was: $(@($entry[0].declaredElsewhere | ForEach-Object { "$($_.method)/$($_.surface)" }) -join ', ')"

        # Provenance is the whole value of the classification, and it is asserted as an exact
        # ORDERED list: deduplicated, and sorted by method then surface ordinally.
        #
        # NOT because an unstable sort could reorder it. An earlier version of this comment said
        # so; that reasoning is retracted for the same reason as the one at the deduplication
        # assertion above. These three sites have DISTINCT sort keys, so the comparison never
        # returns 0 and the introsort's output is deterministic; instability manifests only on
        # ties, and a tie on (method, surface) is a tie on the entire serialised record. The
        # ordered form is asserted because it pins the comparer's actual CONTRACT -- method first,
        # then surface, both ordinal -- which an order-insensitive assertion would leave
        # unexercised, as the -Because below spells out.
        $sites = @($entry[0].declaredElsewhere | ForEach-Object { "$($_.method)/$($_.surface)" })
        $sites | Should -Be @('DELETE/Query', 'PATCH/Body', 'PATCH/Query') -Because "the fixture declares exactly those three sites, and both sort keys must be exercised: DELETE before PATCH orders on method, Body before Query orders on surface within PATCH. Got: [$($sites -join ', ')]"
    }

    It 'classifies a key declared only as a query key under another verb as WRONG-VERB' {
        # Step 1-2, the second arm. Nothing on synthetic/verb declares a request body at all,
        # so this fixture cannot be satisfied by a Body site and isolates the WRONG-VERB arm
        # from the WRONG-SURFACE one above.
        $entry = @(@($syntheticReport.deadKeys) | Where-Object { $_.cmdlet -eq 'Get-PfbSyntheticWrongVerb' -and $_.parameter -eq 'Gone' })
        @($entry).Count | Should -Be 1 -Because "-Gone writes 'destroyed' on GET synthetic/verb, which declares only 'limit'. Reported dead keys were: $syntheticDeadKeyText"
        $entry[0].wireKey | Should -Be 'destroyed' -Because 'the parameter is named Gone, so the key can only have come from the payload literal'
        $entry[0].classification | Should -Be 'WRONG-VERB' -Because "DELETE synthetic/verb declares 'destroyed' as a query key while GET does not. declaredElsewhere was: $(@($entry[0].declaredElsewhere | ForEach-Object { "$($_.method)/$($_.surface)" }) -join ', ')"
        @($entry[0].declaredElsewhere | ForEach-Object { "$($_.method)/$($_.surface)" }) |
            Should -Be @('DELETE/Query') -Because 'the single declaration site is the evidence for the verb claim'
    }

    It 'classifies a key declared nowhere on the endpoint as UNDECLARED with an empty array' {
        # Step 1-2, the third arm, and the one that is a POSITIVE ASSERTION of absence: the
        # endpoint's only operation declares 'limit' as its query key and 'other_field' as its
        # only body property, so 'names' genuinely appears on neither surface. The empty-array
        # assertion matters as much as the classification -- a consumer reading null cannot
        # distinguish "no declaration anywhere" from "this generator did not look".
        $entry = @(@($syntheticReport.deadKeys) | Where-Object { $_.cmdlet -eq 'New-PfbSyntheticUndeclared' -and $_.parameter -eq 'Title' })
        @($entry).Count | Should -Be 1 -Because "-Title writes 'names' on POST synthetic/undeclared, which declares only 'limit'. Reported dead keys were: $syntheticDeadKeyText"
        $entry[0].wireKey | Should -Be 'names' -Because 'the parameter is named Title, so the key can only have come from the payload literal'
        $entry[0].classification | Should -Be 'UNDECLARED' -Because "nothing on synthetic/undeclared declares 'names' -- not the POST query keys and not its body. A WRONG-SURFACE answer would mean the index leaked another endpoint's body properties in. declaredElsewhere was: $(@($entry[0].declaredElsewhere | ForEach-Object { "$($_.method)/$($_.surface)" }) -join ', ')"
        @($entry[0].declaredElsewhere).Count | Should -Be 0 -Because 'UNDECLARED must carry no provenance'
        $null -ne $entry[0].declaredElsewhere | Should -BeTrue -Because 'and an empty array rather than null'

        # THE ANTI-LEAK CONTROL for the index: 'other_field' is a body property of THIS
        # endpoint, and 'flagged' is a body property of a DIFFERENT one. If the index were
        # keyed too loosely -- on the spec document rather than per (endpoint, method) -- then
        # a dead key would find a declaration on some other path and this file's three
        # classification arms would all still pass. Asserting that no dead key in the whole
        # synthetic population claims a Body site it cannot have is what closes that.
        # The excluded set is COMPUTED from the fixture spec in BeforeAll (the normalized paths
        # whose operations declare a requestBody) rather than written out here, so it cannot be
        # widened by hand to silence a red. Its own non-emptiness is asserted first: an empty
        # exclusion set would make the assertion below strictly stronger, but an exclusion set
        # that silently stopped being derived at all is a fixture defect worth naming.
        $bodyBearing = @($fixtureBodyBearingEndpoints)
        @($bodyBearing).Count | Should -BeGreaterThan 0 -Because 'the exclusion set is derived from the fixture spec, so an empty one means the derivation broke rather than that the fixture has no bodies'

        # -notin is case-INSENSITIVE, which is deliberate and matches the gate: the derived set
        # holds the spec-cased path ('widgets') while a record may carry the cmdlet-cased
        # literal ('Widgets'), and those are the same endpoint everywhere else in this file.
        $leaks = @(@($syntheticReport.deadKeys) | Where-Object {
            $_.endpoint -notin $bodyBearing -and @($_.declaredElsewhere | Where-Object { $_.surface -eq 'Body' }).Count -gt 0
        } | ForEach-Object { "$($_.cmdlet)|$($_.parameter) on $($_.endpoint)" })
        @($leaks) -join '; ' | Should -BeNullOrEmpty -Because "only [$($bodyBearing -join ', ')] declare a request body in this fixture, so a Body provenance on any other endpoint means the declaration index is not keyed per endpoint"
    }

    It 'matches the declaration index on the endpoint case-insensitively, exactly as the gate does' {
        # The endpoint axis of the same argument the key axis already carries: the deadness
        # gate reaches the spec through PSObject property access on a ConvertFrom-Json object,
        # which is case-INSENSITIVE, so a cmdlet whose -Endpoint literal differs in case from
        # the spec path key is still gated normally and still reaches classification. An index
        # keyed ordinal-exactly would miss it and publish UNDECLARED -- a positive assertion
        # that nothing on the endpoint declares the key, about a key this same generator can
        # see one line earlier. That is the strictly worse failure direction, so it is asserted
        # rather than assumed.
        #
        # Not a live defect today: all 85 real dead-key endpoint literals match a normalized
        # spec path exactly. This guards a future ordinal hardening, which is a plausible and
        # well-intentioned change.
        $mixed = @(@($syntheticReport.deadKeys) | Where-Object { $_.cmdlet -eq 'Get-PfbSyntheticMixedCaseEndpoint' })
        @($mixed).Count | Should -Be 1 -Because "-Stowed writes 'archived' on GET Widgets, and the gate resolves '/api/$fixtureVersion/Widgets' against the lower-case spec key, so the key is dead and reaches classification. Reported dead keys were: $syntheticDeadKeyText"
        # -BeExactly, NOT -Be. `Should -Be` is CASE-INSENSITIVE for strings, so the -Be form of
        # this line could not fail for the reason it gives: measured, lowercasing the emitted
        # record to 'widgets' (lookups untouched) left every assertion in this file green.
        $mixed[0].endpoint | Should -BeExactly 'Widgets' -Because 'the record must keep the literal the cmdlet itself wrote; a normalising rewrite here would hide the divergence this test exists to exercise, and endpoint is how a reader locates that literal in the source'
        $mixed[0].classification | Should -Be 'WRONG-SURFACE' -Because "PATCH widgets declares 'archived' as a body property. UNDECLARED here means the index is keyed more strictly than the gate. declaredElsewhere was: $(@($mixed[0].declaredElsewhere | ForEach-Object { "$($_.method)/$($_.surface)" }) -join ', ')"
        @($mixed[0].declaredElsewhere).Count | Should -Be 1 -Because 'the one PATCH body declaration is the whole provenance'
        @($mixed[0].declaredElsewhere | ForEach-Object { "$($_.method)/$($_.surface)" }) | Should -Be @('PATCH/Body')

        # THE CONTROL. Identical fixture in every respect except that its endpoint literal
        # matches the spec path case, so it classifies the same way with or without
        # case-insensitive endpoint keys. If the assertion above ever reds while this one is
        # green, the case divergence is the only remaining explanation.
        $lower = @(@($syntheticReport.deadKeys) | Where-Object { $_.cmdlet -eq 'Get-PfbSyntheticLowerCaseEndpoint' })
        @($lower).Count | Should -Be 1 -Because "the control must itself be a dead key, or it controls for nothing. Reported dead keys were: $syntheticDeadKeyText"
        $lower[0].classification | Should -Be 'WRONG-SURFACE' -Because 'the control shares the spec shape, key and verb of the mixed-case fixture, so a difference between the two can only come from the endpoint case'
        @($lower[0].declaredElsewhere | ForEach-Object { "$($_.method)/$($_.surface)" }) | Should -Be @('PATCH/Body')
    }

    It 'counts a parameter of a function that issues no request as outside standard request, not unresolved' {
        # Step 5, first new bucket. Set-PfbSyntheticNoRequest contains no Invoke-PfbApiRequest
        # call, so NONE of its parameters can resolve -- and reporting them as "wire name
        # unresolved" describes a resolver failure that never happened
        # (tools/lib/PfbCmdletParamTools.ps1:1630). Both of its parameters must land in this
        # bucket and nowhere else.
        $syntheticSkipReasons.'outside standard request' | Should -Be 2 -Because "Set-PfbSyntheticNoRequest declares -Alpha and -Beta and issues no Invoke-PfbApiRequest. Buckets were: $syntheticSkipText"

        # THE CONTROL, per the measure-with-a-control rule: 'wire name unresolved' must be
        # provably able to fire in this same run, otherwise the assertion above is
        # indistinguishable from a generator that stopped counting unresolved parameters
        # altogether. -Unresolvable on Get-PfbSyntheticWrongSurface is the planted non-zero:
        # typed, in a function that DOES issue a request, and absent from the payload.
        $syntheticSkipReasons.'wire name unresolved' | Should -BeGreaterThan 0 -Because "-Unresolvable is a genuine resolution failure and must still be counted as one; a zero here means the two new states have swallowed the bucket they were split out of. Buckets were: $syntheticSkipText"

        @(@($syntheticReport.deadKeys) | Where-Object { $_.cmdlet -eq 'Set-PfbSyntheticNoRequest' }) |
            Should -BeNullOrEmpty -Because 'a parameter with no request to land in can never be a dead key'
    }

    It 'counts an audited request control as not wire parameter, not unresolved' {
        # Step 5, second new bucket. The allowlist is keyed on the exact 'Cmdlet|Parameter'
        # identity, so this fixture has to BE Remove-PfbBucket -Eradicate; see the fixture
        # comment. It also has to issue a real request, because 'OutsideStandardRequest' is
        # tested first in the same ladder -- if this assertion and the one above ever both
        # move together, that ordering is what broke.
        $syntheticSkipReasons.'not wire parameter' | Should -Be 1 -Because "Remove-PfbBucket -Eradicate is on the audited allowlist (Get-PfbNotWireParameterAllowlist) and its function does issue Invoke-PfbApiRequest, so it must be counted here and not as 'outside standard request'. Buckets were: $syntheticSkipText"

        # -Name writes the DECLARED key on this endpoint, so the fixture proves the cmdlet was
        # inventoried and evaluated rather than skipped wholesale -- without which the count
        # above could be explained by the file never being read.
        @(@($syntheticReport.deadKeys) | Where-Object { $_.cmdlet -eq 'Remove-PfbBucket' }) |
            Should -BeNullOrEmpty -Because "-Name writes the declared key 'names' on DELETE synthetic/allow and -Eradicate is not a wire field at all, so this cmdlet has no dead key. Reported dead keys were: $syntheticDeadKeyText"
    }
}
