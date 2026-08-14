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

    It 'reproduces the Stage 1 headline numbers' {
        # A tripwire, not a snapshot. These are the measured baseline the audit report is
        # written against; if the generator drifts from the sweep that produced it, the
        # narrative and the artifact stop agreeing and neither says so.
        $report = Get-Content $script:reportPath -Raw | ConvertFrom-Json
        $report.totals.probePairs | Should -Be 1179
        $report.totals.findings | Should -Be 389

        $pairs = @($report.results |
                Where-Object { $_.Outcome -in @('Coerced', 'WrongScalar') } |
                ForEach-Object { "$($_.Cmdlet)/$($_.Parameter)" } |
                Sort-Object -Unique)
        $pairs.Count | Should -Be 127
    }

    It 'records only BindError as unmeasured' {
        # Unbindable and CmdletError are VERDICTS -- PowerShell declining to bind at all, and
        # the cmdlet throwing before the shim. Collapsing them into BindError is what made 8
        # measured pairs look like blind spots in the first revision of the audit.
        $report = Get-Content $script:reportPath -Raw | ConvertFrom-Json
        @($report.results | Where-Object Outcome -eq 'BindError').Count | Should -Be 2
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
