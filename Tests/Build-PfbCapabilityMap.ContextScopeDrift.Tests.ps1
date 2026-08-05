#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
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
