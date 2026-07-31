#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Data-integrity guard: every REST version the capability map was generated from must
    have a corresponding entry in Data/PfbVersionMap.json.
.DESCRIPTION
    Data/PfbVersionMap.json is currently a static, hand-curated file rather than one kept
    fresh by tools/Update-PfbVersionMap.ps1's CI run (see that script's header and
    tools/README.md Sec.3). This test does not care how the file was produced; it only
    catches drift, e.g. a new REST version landing in Data/PfbCapabilityMap.json (via the
    weekly CI refresh) without a matching Purity//FB pairing being added, either by hand
    or by the generator.
#>

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $script:capabilityMapPath = Join-Path $repoRoot 'Data/PfbCapabilityMap.json'
    $script:versionMapPath = Join-Path $repoRoot 'Data/PfbVersionMap.json'

    # ConvertFrom-Json has no -Depth parameter on Windows PowerShell 5.1 (added in PS6) --
    # 5.1's own recursion limit (100) is already far deeper than either file's shape.
    function script:ConvertFrom-PfbTestJson {
        param([Parameter(ValueFromPipeline)] [string]$InputObject)
        if ($PSVersionTable.PSVersion.Major -ge 6) {
            $InputObject | ConvertFrom-Json -Depth 5
        }
        else {
            $InputObject | ConvertFrom-Json
        }
    }

    # REST versions sort numerically, not lexically -- '2.9' is OLDER than '2.27', but a
    # string sort puts it after. Collapse to a single integer so comparisons are unambiguous
    # on both PowerShell editions.
    function script:ConvertTo-PfbComparableVersion {
        param([string]$Version)
        $parts = "$Version" -split '\.'
        $major = 0
        $minor = 0
        [void][int]::TryParse($parts[0], [ref]$major)
        if ($parts.Count -gt 1) { [void][int]::TryParse($parts[1], [ref]$minor) }
        ($major * 10000) + $minor
    }

    # Splits "in the capability map but with no version-map pairing" into LAG AT THE HEAD
    # versus a HOLE IN THE MIDDLE.
    #
    # Data/PfbVersionMap.json is refreshed by a *manual* run of
    # tools/Update-PfbVersionMap.ps1 against an Everpure-internal SSOT endpoint that
    # GitHub-hosted CI cannot reach. Worse, the SSOT reference table only publishes a
    # REST<->Purity//FB pairing some time *after* a REST version ships -- verified
    # 2026-07-25, when REST 2.28 was live and already fetched into the capability map while
    # the SSOT table still had no 2.28 row at all. So a newly-released version legitimately
    # appears in the capability map before any pairing exists anywhere to record.
    #
    # Failing on that would break the weekly refresh on exactly the runs that have something
    # new to report -- and because the job dies before `Open pull request`, the failure would
    # swallow the "new REST version detected" signal the workflow exists to emit. So
    # head-lag warns and passes; a gap at or below the newest mapped version is a real data
    # defect and still fails.
    #
    # Factored out of the It block so these semantics are unit-testable without needing real
    # Data/ files on disk -- see the classification Describe at the bottom of this file.
    function script:Split-PfbVersionMapGap {
        param([string[]]$ExpectedVersions, [string[]]$MappedVersions)

        $mapped = [System.Collections.Generic.HashSet[string]]::new([string[]]$MappedVersions)
        $missing = @($ExpectedVersions | Where-Object { -not $mapped.Contains($_) })

        $highWaterName = $MappedVersions |
            Sort-Object -Property { ConvertTo-PfbComparableVersion $_ } |
            Select-Object -Last 1
        $highWater = ConvertTo-PfbComparableVersion $highWaterName

        [pscustomobject]@{
            HighWaterName = $highWaterName
            Lagging       = @($missing | Where-Object { (ConvertTo-PfbComparableVersion $_) -gt $highWater })
            Holes         = @($missing | Where-Object { (ConvertTo-PfbComparableVersion $_) -le $highWater })
        }
    }
}

Describe 'Data/PfbVersionMap.json coverage (skips gracefully if the generated files are not present)' {
    It 'has an entry for every REST version the capability map was generated from' {
        if (-not (Test-Path $capabilityMapPath) -or -not (Test-Path $versionMapPath)) {
            Set-ItResult -Skipped -Because 'Data/PfbCapabilityMap.json or Data/PfbVersionMap.json not present'
            return
        }

        $capabilityMap = Get-Content -Path $capabilityMapPath -Raw | ConvertFrom-PfbTestJson
        $versionMap = Get-Content -Path $versionMapPath -Raw | ConvertFrom-PfbTestJson

        $expectedVersions = $capabilityMap.generatedFrom
        $expectedVersions | Should -Not -BeNullOrEmpty -Because 'the capability map should record which REST versions it was generated from'

        # Head-lag warns, a gap below the high-water mark fails -- see
        # Split-PfbVersionMapGap's comment for why the two are treated differently.
        $gap = Split-PfbVersionMapGap -ExpectedVersions $expectedVersions -MappedVersions ([string[]]$versionMap.PSObject.Properties.Name)
        $highWaterName = $gap.HighWaterName
        $lagging = $gap.Lagging
        $holes = $gap.Holes

        if ($lagging) {
            $message = "Data/PfbVersionMap.json has no Purity//FB pairing for newer REST version(s): $($lagging -join ', '). " +
                       "Newest mapped version is $highWaterName. This is expected lag, not a defect: run " +
                       'tools/Update-PfbVersionMap.ps1 manually with SSOT credentials once the SSOT reference table publishes the pairing.'
            Write-Warning $message
            # Surface it in the Actions run summary too, so the weekly refresh flags the
            # outstanding manual step instead of it being buried in step logs.
            if ($env:GITHUB_ACTIONS -eq 'true') {
                Write-Host "::warning title=Version map behind capability map::$message"
            }
        }

        $holes | Should -BeNullOrEmpty -Because "these REST versions are at or below the newest mapped version ($highWaterName) but have no Purity//FB pairing in Data/PfbVersionMap.json: $($holes -join ', ') -- a gap below the high-water mark is a data defect, not upstream lag"
    }

    It 'every entry has a non-empty purity property' {
        if (-not (Test-Path $versionMapPath)) {
            Set-ItResult -Skipped -Because 'Data/PfbVersionMap.json not present'
            return
        }

        $versionMap = Get-Content -Path $versionMapPath -Raw | ConvertFrom-PfbTestJson

        $emptyEntries = $versionMap.PSObject.Properties | Where-Object { [string]::IsNullOrWhiteSpace($_.Value.purity) } | ForEach-Object { $_.Name }

        $emptyEntries | Should -BeNullOrEmpty -Because "these REST versions have an entry but no purity value: $($emptyEntries -join ', ')"
    }
}

Describe 'Version-map gap classification (head lag vs hole)' {
    BeforeAll {
        # 2.9 is deliberately present: REST versions sort lexically WRONG ('2.9' > '2.27' as
        # strings), so a naive sort would pick 2.9 as the newest mapped version and then
        # misclassify every genuinely-newer version as a hole.
        $script:mapped = 0..27 | ForEach-Object { "2.$_" }
    }

    It 'picks the numerically-newest mapped version as the high-water mark, not the lexically-largest' {
        $gap = Split-PfbVersionMapGap -ExpectedVersions $mapped -MappedVersions $mapped
        $gap.HighWaterName | Should -Be '2.27'
    }

    It 'reports nothing when the two sets agree' {
        $gap = Split-PfbVersionMapGap -ExpectedVersions $mapped -MappedVersions $mapped
        $gap.Lagging | Should -BeNullOrEmpty
        $gap.Holes | Should -BeNullOrEmpty
    }

    It 'classifies a newly-released version above the high-water mark as expected lag, not a hole' {
        $gap = Split-PfbVersionMapGap -ExpectedVersions ($mapped + '2.28') -MappedVersions $mapped
        $gap.Lagging | Should -Be @('2.28')
        $gap.Holes | Should -BeNullOrEmpty
    }

    It 'classifies a missing version below the high-water mark as a hole, not lag' {
        $withHole = $mapped | Where-Object { $_ -ne '2.20' }
        $gap = Split-PfbVersionMapGap -ExpectedVersions $mapped -MappedVersions $withHole
        $gap.Holes | Should -Be @('2.20')
        $gap.Lagging | Should -BeNullOrEmpty
    }

    It 'separates the two when a hole and a lagging version occur together' {
        $withHole = $mapped | Where-Object { $_ -ne '2.20' }
        $gap = Split-PfbVersionMapGap -ExpectedVersions ($mapped + '2.28') -MappedVersions $withHole
        $gap.Holes | Should -Be @('2.20')
        $gap.Lagging | Should -Be @('2.28')
    }

    It 'treats a single-digit-minor gap correctly rather than by string order' {
        # 2.9 missing while 2.27 is mapped: numerically below the high-water mark, so a hole.
        $withHole = $mapped | Where-Object { $_ -ne '2.9' }
        $gap = Split-PfbVersionMapGap -ExpectedVersions $mapped -MappedVersions $withHole
        $gap.Holes | Should -Be @('2.9')
        $gap.Lagging | Should -BeNullOrEmpty
    }
}
