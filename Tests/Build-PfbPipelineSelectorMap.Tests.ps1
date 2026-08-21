#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Shape, determinism and registration tests for the committed pipeline-selector map.
.DESCRIPTION
    These assert on the COMMITTED artifact, not on a freshly generated one, so they fail if
    someone edits the generator and forgets to regenerate -- the same contract the other
    Reports/ generators carry.

    Reading the report needs no PowerShell 7 features, so unlike the audit's other test files
    these Describes are NOT edition-gated. The generator that produces the report is 7-only;
    parsing its JSON output is not.
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:reportPath = Join-Path $script:repoRoot 'Reports/PfbPipelineSelectorMap.json'
}

Describe 'Build-PfbPipelineSelectorMap parameter contract' {

    It 'exposes -ResponseShapeMapPath so a caller can redirect the shape-map input' {
        # AST rather than Get-Command -Syntax: the generator carries #Requires -Version 7.0,
        # so resolving it as a command fails outright on Windows PowerShell 5.1. Parsing the
        # file is edition-agnostic and does not execute the ~minutes-long probe harness.
        $generatorPath = Join-Path $script:repoRoot 'tools/Build-PfbPipelineSelectorMap.ps1'
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($generatorPath, [ref]$null, [ref]$null)
        $names = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })

        $names | Should -Contain 'ResponseShapeMapPath'
    }

    It 'no longer hardcodes the committed response-shape map path' {
        # The regression this guards: with the path inlined at the call site, a caller could
        # pass -ResponseShapeMapPath and still silently read the committed file.
        $generatorPath = Join-Path $script:repoRoot 'tools/Build-PfbPipelineSelectorMap.ps1'
        $source = Get-Content $generatorPath -Raw

        $source | Should -Not -Match "Get-Content \(Join-Path \`$repoRoot 'Data/PfbResponseShapeMap\.json'\)"
    }
}

Describe 'Build-PfbPipelineSelectorMap' {

    It 'emits a report with the documented top-level shape' {
        Test-Path $script:reportPath | Should -BeTrue
        $report = Get-Content $script:reportPath -Raw | ConvertFrom-Json
        $report.schemaVersion | Should -Not -BeNullOrEmpty
        $report.totals | Should -Not -BeNullOrEmpty
        $report.results | Should -Not -BeNullOrEmpty
    }

    It 'is deterministic: results are sorted ORDINALLY by cmdlet, parameter, producer' {
        # NOT Sort-Object -Culture '' -- that is invariant LINGUISTIC comparison and the two
        # gated editions disagree on it (5.1 ignores the hyphen in 'file-system-snapshots',
        # 7 does not), which moved 10 of 1179 rows between editions with every verdict
        # identical. The generator emits via Sort-PfbSelectorRecord, which uses
        # [System.StringComparer]::Ordinal; assert against the same comparer.
        $report = Get-Content $script:reportPath -Raw | ConvertFrom-Json
        $keys = [string[]]@($report.results |
                ForEach-Object { "$($_.Cmdlet)`v$($_.Parameter)`v$($_.Producer)" })
        $sorted = [string[]]@($keys)
        [array]::Sort($sorted, [System.StringComparer]::Ordinal)

        ($keys -join '|') | Should -Be ($sorted -join '|')
    }

    It 'carries the fields Rail A needs, including the two Stage 1 added' {
        # ProbeProperties/ProbeTypes let Rail A rebuild a probe object without tools/specs,
        # which is gitignored and whose absence silently skips other tests in this repo.
        # ErrorKind/FilledParameter let it tell an unmeasured row from a measured one.
        $report = Get-Content $script:reportPath -Raw | ConvertFrom-Json
        $row = $report.results[0]
        foreach ($field in @('Cmdlet', 'Parameter', 'Producer', 'Outcome', 'Evidence',
                'ErrorKind', 'FilledParameter', 'ProbeProperties', 'ProbeTypes')) {
            $row.PSObject.Properties.Name | Should -Contain $field
        }
    }

    It 'reproduces the measured headline numbers' {
        # A tripwire, not a snapshot. These are the measured baseline the audit report is
        # written against; if the generator drifts from the sweep that produced it, the
        # narrative and the artifact stop agreeing and neither says so.
        #
        # Re-baselined from the Stage 1 audit figures (1179 / 389 / 127) when the Stage 2
        # fixes landed, because those fixes deliberately moved all three. A tripwire is only
        # worth keeping if each re-baseline is justified rather than merely applied, so:
        #
        #   probePairs 1179 -> 1247  more pipeline-bound parameters now exist to probe. The
        #                            module-wide population moved 303 -> 311, accounted for
        #                            row by row in PfbPipelineSelectorTools.Tests.ps1, and
        #                            renamed selectors resolve to more producers each.
        #   findings    389 -> 264   the point of the branch: coercions that were fixed are
        #                            no longer found.
        #   pairs       127 -> 101   unique cmdlet/parameter pairs still coercing. This must
        #                            equal the entry count of Fixtures/PfbSelectorWaivers.psd1,
        #                            which Rail A pins from the opposite direction -- a waiver
        #                            for a pair that no longer coerces fails there -- so the
        #                            two figures cannot drift apart quietly.
        $report = Get-Content $script:reportPath -Raw | ConvertFrom-Json
        $report.totals.probePairs | Should -Be 1247
        $report.totals.findings | Should -Be 264

        $pairs = @($report.results |
                Where-Object { $_.Outcome -in @('Coerced', 'WrongScalar') } |
                ForEach-Object { "$($_.Cmdlet)/$($_.Parameter)" } |
                Sort-Object -Unique)
        $pairs.Count | Should -Be 101
    }

    It 'records only BindError as unmeasured' {
        # Unbindable and CmdletError are VERDICTS -- PowerShell declining to bind at all, and
        # the cmdlet throwing before the shim. Collapsing them into BindError is what made 8
        # measured pairs look like blind spots in the first revision of the audit.
        #
        # RE-BASELINED 2 -> 4 alongside the twin pin in PfbPipelineSelectorRail.Tests.ps1, which
        # carries the full account: making Update-PfbLegalHoldEntity -Released mandatory (#106
        # Part 2) means the probe can no longer construct a call for that cmdlet, so its two rows
        # move from Bound/Unbindable to a HarnessRefusal BindError. Unlike its twin, this
        # assertion reads the COMMITTED report instead of regenerating, so it is not PS7-gated
        # and reds on Windows PowerShell 5.1 too.
        $report = Get-Content $script:reportPath -Raw | ConvertFrom-Json
        @($report.results | Where-Object Outcome -eq 'BindError').Count | Should -Be 4
        @($report.results | Where-Object Outcome -eq 'Unbindable').Count | Should -BeGreaterThan 0
    }

    It 'registers itself in the Reports README table' {
        $readme = Get-Content (Join-Path $script:repoRoot 'Reports/README.md') -Raw
        $readme.Contains('PfbPipelineSelectorMap.json') | Should -BeTrue
        $readme.Contains('Build-PfbPipelineSelectorMap.ps1') | Should -BeTrue
    }

    It 'emits a readable markdown companion' {
        $markdown = Join-Path $script:repoRoot 'Reports/PfbPipelineSelectorMap.md'
        Test-Path $markdown | Should -BeTrue
        $text = Get-Content $markdown -Raw
        $text.Contains('Coerced') | Should -BeTrue
    }
}
