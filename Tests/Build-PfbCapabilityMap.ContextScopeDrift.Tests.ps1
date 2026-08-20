#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    # Defined in the top-level BeforeAll, NOT at file scope, so both the real-spec Describe and
    # the synthetic-input Describe below can call it. A function defined at file scope is created
    # during Pester's DISCOVERY pass, in a scope the run pass cannot see -- every It then fails
    # with "The term ... is not recognized", which is what happened when this was written that
    # way. Pester also permits only ONE BeforeAll per block, so this cannot be split out into its
    # own adjacent block either.
    #
    # It takes the collected declarations rather than reading specs itself, deliberately: a
    # comparison that owns its own I/O can only ever be tested against whatever is on disk, and
    # nothing on disk exhibits any of these conditions today (issue #112).
    function Get-PfbContextScopeVersionFinding {
        [CmdletBinding()]
        param(
            # endpoint -> @{ <version> = '<TOKEN>|<TOKEN>' }, tokens upper-cased and sorted, and
            # ONLY for versions that actually declare an override.
            [Parameter(Mandatory)] [hashtable]$Declared,
            # endpoint -> the versions whose spec contains the operation at all. Required to tell
            # a WITHDRAWN override from an endpoint that simply left the API.
            [Parameter(Mandatory)] [hashtable]$Seen,
            # Every scanned version, ascending. Rank comes from position here, never from a string
            # or numeric comparison of the version itself: '2.10' sorts before '2.2' as a string,
            # and 2.20 truncates to 2.2 as a number.
            [Parameter(Mandatory)] [string[]]$VersionOrder
        )

        $rank = @{}
        for ($i = 0; $i -lt $VersionOrder.Count; $i++) { $rank[$VersionOrder[$i]] = $i }

        foreach ($endpoint in ($Declared.Keys | Sort-Object)) {
            $byVersion = $Declared[$endpoint]
            $declaringVersions = @($byVersion.Keys |
                    Where-Object { $rank.ContainsKey($_) } | Sort-Object { $rank[$_] })
            if ($declaringVersions.Count -eq 0) { continue }

            $previousVersion = $null
            foreach ($version in $declaringVersions) {
                $current = $byVersion[$version]
                if ($null -ne $previousVersion) {
                    $previous = $byVersion[$previousVersion]
                    if ($current -ne $previous) {
                        # A GAIN (the earlier tokens all survive) and a SWAP need different
                        # responses, so they are different findings rather than one "it changed".
                        # A gain means the map's single scalar scope cannot hold what the endpoint
                        # now declares; a swap means the scope itself is version-dependent.
                        $previousTokens = @($previous -split '\|')
                        $currentTokens = @($current -split '\|')
                        $lost = @($previousTokens | Where-Object { $currentTokens -notcontains $_ })
                        [pscustomobject]@{
                            Endpoint = $endpoint
                            Finding  = if ($lost.Count -eq 0) { 'KindGained' } else { 'ValueChange' }
                            Detail   = "declared '$previous' at $previousVersion, '$current' at $version"
                        }
                    }
                }
                $previousVersion = $version
            }

            # Withdrawal: the operation is still in a LATER spec but no longer carries an
            # override. Bounded to versions after the first declaration -- before it, an absent
            # override is simply an endpoint upstream had not annotated yet, the normal state.
            $firstDeclared = $declaringVersions[0]
            foreach ($version in @($Seen[$endpoint])) {
                if (-not $rank.ContainsKey($version)) { continue }
                if ($rank[$version] -le $rank[$firstDeclared]) { continue }
                if ($byVersion.ContainsKey($version)) { continue }
                [pscustomobject]@{
                    Endpoint = $endpoint
                    Finding  = 'Withdrawn'
                    Detail   = ("declared '{0}' at {1}, but {2} carries no override while the " +
                                'operation still exists') -f $byVersion[$firstDeclared], $firstDeclared, $version
                }
            }
        }
    }

    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $script:repoRoot 'tools/lib/PfbSpecTools.ps1')

    # The curated table, mirrored from tools/Build-PfbCapabilityMap.ps1. Mirrored
    # deliberately: this test's job is to detect the table going stale, so it must state
    # independently what the table is expected to contain. Keep the two in sync by hand --
    # if they diverge, the 'exactly these' assertion below fails, which is the point.
    $script:expectedCurated = @{
        'GET /topology-groups'         = 'fleet'
        'GET /topology-groups/arrays'  = 'fleet'
        'GET /topology-groups/members' = 'fleet'
        'GET /workloads/tags'          = 'array'
    }
}

Describe 'contextScope drift against the real specs and the committed map' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {

    BeforeAll {
        $script:mapPath = Join-Path $script:repoRoot 'Data/PfbCapabilityMap.json'
        $script:specPath = Join-Path $script:repoRoot 'tools/specs/fb2.28.json'
        $script:hasBoth = (Test-Path $script:mapPath) -and (Test-Path $script:specPath)

        if ($script:hasBoth) {
            $script:map = Get-Content -Path $script:mapPath -Raw | ConvertFrom-Json -Depth 20
            $spec = Get-Content -Path $script:specPath -Raw | ConvertFrom-Json -Depth 64
            $script:scopeRecords = @(Get-PfbSpecContextScope -Spec $spec)
            $script:byEndpoint = @{}
            foreach ($r in $script:scopeRecords) { $script:byEndpoint[$r.Endpoint] = $r }
        }
    }

    It 'the committed map is schemaVersion 2' {
        if (-not $script:hasBoth) { Set-ItResult -Skipped -Because 'map or fb2.28 spec absent'; return }
        $script:map.schemaVersion | Should -Be 2
    }

    It 'the GENERATOR''s curated table matches this mirror, so an un-regenerated edit cannot hide' {
        # Every other assertion in this file compares the mirror against the committed MAP.
        # That leaves a hole: edit $curatedContextScope in the generator and forget to
        # regenerate, and the map still holds the old values, the mirror still holds the old
        # values, and the generator has silently diverged from both.
        #
        # Scraping the generator's literal closes it WITHOUT reintroducing the problem the
        # mirror exists to avoid -- the scope values and flag state are still validated
        # against the real spec and the committed map independently, above and below. This
        # assertion only proves the three copies agree.
        $generatorPath = Join-Path $script:repoRoot 'tools/Build-PfbCapabilityMap.ps1'
        if (-not (Test-Path $generatorPath)) { Set-ItResult -Skipped -Because 'generator absent'; return }

        $generatorSource = Get-Content -Path $generatorPath -Raw
        $blockMatch = [regex]::Match($generatorSource, '\$curatedContextScope\s*=\s*@\{(?<body>[^}]*)\}')
        $blockMatch.Success | Should -BeTrue -Because 'the $curatedContextScope literal must be findable; if it was restructured, update this scrape deliberately'

        $scraped = @{}
        foreach ($entryMatch in [regex]::Matches($blockMatch.Groups['body'].Value, "'(?<key>[^']+)'\s*=\s*'(?<value>[^']+)'")) {
            $scraped[$entryMatch.Groups['key'].Value] = $entryMatch.Groups['value'].Value
        }

        @($scraped.Keys | Sort-Object) | Should -Be @($script:expectedCurated.Keys | Sort-Object) -Because 'the generator table and this mirror have diverged'
        foreach ($key in $scraped.Keys) {
            $scraped[$key] | Should -Be $script:expectedCurated[$key] -Because "curated scope for $key disagrees between the generator and this mirror"
        }
    }

    It 'the five declared overrides still match what the map emits as provenance=declared' {
        if (-not $script:hasBoth) { Set-ItResult -Skipped -Because 'map or fb2.28 spec absent'; return }
        $declaredInSpec = @($script:scopeRecords | Where-Object { @($_.DomainsOverride).Count -gt 0 } | ForEach-Object { $_.Endpoint } | Sort-Object)
        $declaredInMap = @($script:map.endpoints.PSObject.Properties |
                Where-Object { $_.Value.contextScope.provenance -eq 'declared' } |
                ForEach-Object { $_.Name } | Sort-Object)
        $declaredInMap | Should -Be $declaredInSpec
    }

    It 'REGRESSION GUARD: no curated entry has gained an upstream override' {
        # This is the assertion that keeps the table shrinking on its own. When upstream
        # fills in a domains override for one of these, the curated value stops being the
        # best data available and starts SHADOWING it -- silently, because both produce a
        # plausible scope. Retire the entry from tools/Build-PfbCapabilityMap.ps1's
        # $curatedContextScope, regenerate, and remove it from $expectedCurated here.
        if (-not $script:hasBoth) { Set-ItResult -Skipped -Because 'map or fb2.28 spec absent'; return }
        foreach ($endpoint in $script:expectedCurated.Keys) {
            $record = $script:byEndpoint[$endpoint]
            $record | Should -Not -BeNullOrEmpty -Because "$endpoint should exist in fb2.28"
            @($record.DomainsOverride).Count | Should -Be 0 -Because "$endpoint has GAINED an upstream override -- retire its curated entry rather than shadowing the declaration"
        }
    }

    It 'every curated entry is still flagged x-pure-incomplete-gre' {
        # A curated value only earns its place where the absent override proves nothing.
        # If upstream un-flags an endpoint without adding an override, that is a different
        # signal and deserves a fresh decision, not a stale curated value.
        if (-not $script:hasBoth) { Set-ItResult -Skipped -Because 'map or fb2.28 spec absent'; return }
        foreach ($endpoint in $script:expectedCurated.Keys) {
            $script:byEndpoint[$endpoint].IsIncompleteGre | Should -BeTrue -Because "$endpoint is no longer flagged incomplete"
        }
    }

    It 'the map records exactly the expected curated endpoints as provenance=live-tested, with the expected scopes' {
        if (-not $script:hasBoth) { Set-ItResult -Skipped -Because 'map or fb2.28 spec absent'; return }
        $liveTested = @($script:map.endpoints.PSObject.Properties |
                Where-Object { $_.Value.contextScope.provenance -eq 'live-tested' })
        @($liveTested | ForEach-Object { $_.Name } | Sort-Object) | Should -Be @($script:expectedCurated.Keys | Sort-Object)
        foreach ($property in $liveTested) {
            $property.Value.contextScope.scope | Should -Be $script:expectedCurated[$property.Name] -Because "curated scope for $($property.Name)"
        }
    }

    It 'the flagged-but-uncurated population is exactly 19 and all record unknown' {
        # 28 flagged - 5 carrying overrides - 4 curated = 19.
        if (-not $script:hasBoth) { Set-ItResult -Skipped -Because 'map or fb2.28 spec absent'; return }
        $unknownInMap = @($script:map.endpoints.PSObject.Properties |
                Where-Object { $_.Value.contextScope.provenance -eq 'unknown' })
        $unknownInMap.Count | Should -Be 19
        foreach ($property in $unknownInMap) {
            $property.Value.contextScope.scope | Should -Be 'unknown'
            $script:byEndpoint[$property.Name].IsIncompleteGre | Should -BeTrue -Because "$($property.Name) records unknown, so it must be flagged"
        }
    }

    It 'every topology-group WRITE verb falls to the array default, while its reads stay curated fleet' {
        # Documented, accepted, and verified live on 2026-08-04: those writes DO succeed in
        # array context, unlike /presets/workload writes, so the fail-safe default is not
        # merely safe here -- it is correct. Re-check when #38 lands.
        #
        # Derived rather than hardcoded: the exact write-verb set across the
        # topology-groups family is what #38 is still settling, so enumerate whatever the
        # map holds instead of pinning a count that will move.
        if (-not $script:hasBoth) { Set-ItResult -Skipped -Because 'map or fb2.28 spec absent'; return }

        $family = @($script:map.endpoints.PSObject.Properties |
                Where-Object { $_.Name -match '^[A-Z]+ /topology-groups(/|$)' })
        $family.Count | Should -BeGreaterThan 0 -Because 'the topology-groups family must be present in the map'

        foreach ($property in $family) {
            # Note the parentheses: `-not $x -contains $y` binds -not to $x FIRST and
            # silently evaluates to $false for every non-empty $x, making the guard vacuous.
            if ($script:expectedCurated.ContainsKey($property.Name)) {
                $property.Value.contextScope.provenance | Should -Be 'live-tested' -Because "$($property.Name) is curated"
                continue
            }
            $property.Value.contextScope.provenance | Should -Be 'default' -Because "$($property.Name) is unflagged and uncurated"
            $property.Value.contextScope.scope      | Should -Be 'array' -Because "$($property.Name) accepts an array context"
        }
    }
}

Describe 'Get-PfbContextScopeVersionFinding, against synthetic declarations' {
    # No spec I/O and no ConvertFrom-Json -Depth, so this runs on BOTH editions and needs no
    # spec cache. It exists because the real-spec Describe below is VACUOUSLY green: every
    # endpoint that declares an override declares it in exactly one version (fb2.28), so
    # nothing on disk can demonstrate that these findings ever fire. A tripwire nobody has
    # seen trip is indistinguishable from a tripwire that cannot.

    BeforeAll {
        $script:order = @('2.26', '2.27', '2.28')
    }

    It 'reports nothing when an endpoint declares the same scope in every version' {
        $findings = @(Get-PfbContextScopeVersionFinding `
                -Declared @{ 'GET /x' = @{ '2.26' = 'FLEET'; '2.27' = 'FLEET'; '2.28' = 'FLEET' } } `
                -Seen     @{ 'GET /x' = @('2.26', '2.27', '2.28') } `
                -VersionOrder $script:order)
        $findings.Count | Should -Be 0
    }

    It 'reports ValueChange when a declared scope is SWAPPED for a different one' {
        $findings = @(Get-PfbContextScopeVersionFinding `
                -Declared @{ 'GET /x' = @{ '2.26' = 'FLEET'; '2.28' = 'ARRAY' } } `
                -Seen     @{ 'GET /x' = @('2.26', '2.27', '2.28') } `
                -VersionOrder $script:order)
        @($findings | Where-Object Finding -EQ 'ValueChange').Count | Should -Be 1
        ($findings | Where-Object Finding -EQ 'ValueChange').Detail | Should -Match "'FLEET' at 2.26"
    }

    It 'reports KindGained when an endpoint gains an ADDITIONAL context kind' {
        # The case issue #112 has to survive: a future REALM or TOPOLOGY_GROUP domain appearing
        # alongside FLEET on an endpoint that already declared FLEET. The map holds one scalar
        # scope per endpoint, so it cannot record both, and the generator's FLEET-wins rule
        # would silently pick one.
        $findings = @(Get-PfbContextScopeVersionFinding `
                -Declared @{ 'GET /x' = @{ '2.27' = 'FLEET'; '2.28' = 'FLEET|TOPOLOGY_GROUP' } } `
                -Seen     @{ 'GET /x' = @('2.27', '2.28') } `
                -VersionOrder $script:order)
        @($findings | Where-Object Finding -EQ 'KindGained').Count | Should -Be 1
        @($findings | Where-Object Finding -EQ 'ValueChange').Count | Should -Be 0
    }

    It 'reports ValueChange, not KindGained, when a kind is gained AND another is lost' {
        $findings = @(Get-PfbContextScopeVersionFinding `
                -Declared @{ 'GET /x' = @{ '2.27' = 'ARRAY|FLEET'; '2.28' = 'FLEET|REALM' } } `
                -Seen     @{ 'GET /x' = @('2.27', '2.28') } `
                -VersionOrder $script:order)
        @($findings | Where-Object Finding -EQ 'ValueChange').Count | Should -Be 1
        @($findings | Where-Object Finding -EQ 'KindGained').Count | Should -Be 0
    }

    It 'reports Withdrawn when a later spec still has the operation but drops its override' {
        $findings = @(Get-PfbContextScopeVersionFinding `
                -Declared @{ 'GET /x' = @{ '2.26' = 'FLEET' } } `
                -Seen     @{ 'GET /x' = @('2.26', '2.27', '2.28') } `
                -VersionOrder $script:order)
        @($findings | Where-Object Finding -EQ 'Withdrawn').Count | Should -Be 2
    }

    It 'reports NOTHING when the operation itself leaves the API' {
        # An endpoint that is gone carries no override because it carries nothing. Treating that
        # as a withdrawal would make every removed operation a permanent false finding.
        $findings = @(Get-PfbContextScopeVersionFinding `
                -Declared @{ 'GET /x' = @{ '2.26' = 'FLEET' } } `
                -Seen     @{ 'GET /x' = @('2.26') } `
                -VersionOrder $script:order)
        $findings.Count | Should -Be 0
    }

    It 'ignores an override declared before the first version in scope rather than mis-ranking it' {
        # A version absent from -VersionOrder has no rank. Comparing it would silently order it
        # first, which is how a stale or hand-built table produces a confident wrong answer.
        $findings = @(Get-PfbContextScopeVersionFinding `
                -Declared @{ 'GET /x' = @{ '2.20' = 'ARRAY'; '2.28' = 'FLEET' } } `
                -Seen     @{ 'GET /x' = @('2.28') } `
                -VersionOrder $script:order)
        $findings.Count | Should -Be 0
    }
}

Describe 'contextScope stability across every cached REST version (issue #112)' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
    # Issue #112 records a deliberate omission: contextScope is ONE value per endpoint,
    # computed last-seen-wins across the whole spec set, with no version dimension. The
    # justification is that a resource does not migrate between the fleet database and an
    # individual array, so scope is a property of the resource rather than of the API version.
    #
    # This Describe is the tripwire on that justification. If it ever fails, the premise has
    # stopped holding: the map cannot represent what upstream is now declaring, the runtime
    # gates in Private/Assert-PfbContextSupported.ps1 would apply the newest reading to an array
    # running an older REST version, and NO other test can see it -- the drift suite compares
    # the shipped artifact against generator output, and both sides would agree.
    #
    # Reopen #112 when it fires. Do not silence it by widening the expectation.

    BeforeAll {
        $script:specsDirectory = Join-Path $script:repoRoot 'tools/specs'
        $script:hasSpecs = Test-Path (Join-Path $script:specsDirectory 'fb2.28.json')

        if ($script:hasSpecs) {
            # Ordered by (major, minor) parsed from the FILENAME. Never `foreach ($v in 2.20)`:
            # that literal is the number 2.2, which silently opens fb2.2.json -- a real file --
            # so a cross-version claim ends up covering a version it never read.
            $ordered = @(Get-ChildItem -Path $script:specsDirectory -Filter 'fb*.json' -File |
                    Sort-Object {
                        $parts = ($_.BaseName -replace '^fb', '') -split '\.'
                        ([int]$parts[0] * 1000) + [int]$parts[1]
                    })

            $script:versionOrder = @($ordered | ForEach-Object { $_.BaseName -replace '^fb', '' })
            $script:declaredByEndpoint = @{}
            $script:seenByEndpoint = @{}
            $script:domainTokens = [System.Collections.Generic.HashSet[string]]::new()

            foreach ($file in $ordered) {
                $version = $file.BaseName -replace '^fb', ''
                $spec = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json -Depth 64
                foreach ($record in (Get-PfbSpecContextScope -Spec $spec)) {
                    if (-not $script:seenByEndpoint.ContainsKey($record.Endpoint)) {
                        $script:seenByEndpoint[$record.Endpoint] = [System.Collections.Generic.List[string]]::new()
                    }
                    $script:seenByEndpoint[$record.Endpoint].Add($version)

                    $tokens = @($record.DomainsOverride | ForEach-Object { "$_".ToUpperInvariant() } | Sort-Object)
                    if ($tokens.Count -eq 0) { continue }
                    foreach ($token in $tokens) { [void]$script:domainTokens.Add($token) }
                    if (-not $script:declaredByEndpoint.ContainsKey($record.Endpoint)) {
                        $script:declaredByEndpoint[$record.Endpoint] = @{}
                    }
                    $script:declaredByEndpoint[$record.Endpoint][$version] = ($tokens -join '|')
                }
            }

            $script:versionFindings = @(Get-PfbContextScopeVersionFinding `
                    -Declared $script:declaredByEndpoint `
                    -Seen $script:seenByEndpoint `
                    -VersionOrder $script:versionOrder)
        }
    }

    It 'POSITIVE CONTROL: the walk actually saw the API surface and found declarations' {
        # Without this, a broken walk -- one that stops resolving $ref or allOf, as the 2.17
        # restructuring made easy -- returns nothing, and every assertion below passes as
        # "no changes found" having examined nothing. An empty result here is INCONCLUSIVE,
        # never negative.
        #
        # Bounds, not exact counts: a new spec version must not red this file.
        if (-not $script:hasSpecs) { Set-ItResult -Skipped -Because 'tools/specs cache absent'; return }
        $script:versionOrder.Count | Should -BeGreaterThan 20 -Because 'the cache should hold the whole 2.x series'
        $script:seenByEndpoint.Count | Should -BeGreaterThan 500 -Because 'the walk must see the API surface, not a fragment of it'
        $script:declaredByEndpoint.Count | Should -BeGreaterThan 0 -Because 'at least one endpoint declares a domains override; zero means the walk broke'
    }

    It 'no endpoint declares a DIFFERENT context scope in a later version' {
        # The literal question #112 asks. A swap means scope is version-dependent after all, so
        # the map needs a version dimension on contextScope and #112 should be reopened.
        if (-not $script:hasSpecs) { Set-ItResult -Skipped -Because 'tools/specs cache absent'; return }
        $swaps = @($script:versionFindings | Where-Object Finding -EQ 'ValueChange')
        $swaps.Count | Should -Be 0 -Because (
            "contextScope has no version dimension (issue #112), so a scope that changes between " +
            "REST versions cannot be represented and the newest reading would be applied to older " +
            "arrays: $(($swaps | ForEach-Object { "$($_.Endpoint) $($_.Detail)" }) -join '; ')")
    }

    It 'no endpoint GAINS an additional context kind in a later version' {
        # e.g. an endpoint declaring FLEET today also declaring TOPOLOGY_GROUP or REALM
        # tomorrow. The map holds one scalar scope per endpoint, and the generator's
        # FLEET-wins rule would quietly pick one of the two rather than record both --
        # so the kind-vs-scope gate would reject a context the array accepts.
        if (-not $script:hasSpecs) { Set-ItResult -Skipped -Because 'tools/specs cache absent'; return }
        $gains = @($script:versionFindings | Where-Object Finding -EQ 'KindGained')
        $gains.Count | Should -Be 0 -Because (
            "contextScope records ONE scope per endpoint, so an endpoint addressable by more than " +
            "one kind cannot be represented (issue #112): " +
            "$(($gains | ForEach-Object { "$($_.Endpoint) $($_.Detail)" }) -join '; ')")
    }

    It 'no endpoint WITHDRAWS an override it declared in an earlier version' {
        # Last-seen-wins would revert the endpoint to the 'array' default (or to 'unknown' if it
        # is flagged incomplete-gre), silently changing what the runtime gates enforce, with the
        # committed map and the generator still in perfect agreement.
        if (-not $script:hasSpecs) { Set-ItResult -Skipped -Because 'tools/specs cache absent'; return }
        $withdrawn = @($script:versionFindings | Where-Object Finding -EQ 'Withdrawn')
        $withdrawn.Count | Should -Be 0 -Because (
            "last-seen-wins would revert these endpoints to the generator's default scope: " +
            "$(($withdrawn | ForEach-Object { "$($_.Endpoint) $($_.Detail)" }) -join '; ')")
    }

    It 'the declared domain vocabulary is still exactly ARRAY and FLEET' {
        # The NEW-KIND tripwire, and the one most likely to fire first: it needs only a single
        # version to declare an unfamiliar token, not two versions to disagree.
        #
        # Build-PfbCapabilityMap.ps1 interprets FLEET and ARRAY and sends anything else to
        # scope/provenance 'unknown', which SUPPRESSES the kind-vs-scope gate entirely
        # (Private/Assert-PfbContextSupported.ps1) -- so a new domain would not fail loudly, it
        # would quietly stop validating. Set-PfbContext -Kind already accepts TopologyGroup with
        # no spec vocabulary behind it, so the client half of that gap exists today.
        if (-not $script:hasSpecs) { Set-ItResult -Skipped -Because 'tools/specs cache absent'; return }
        @($script:domainTokens | Sort-Object) | Should -Be @('ARRAY', 'FLEET') -Because (
            'a new domain token means the generator gained an uninterpreted scope and the ' +
            'kind-vs-scope gate silently stopped validating those endpoints (issue #112)')
    }
}
