#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Contract guards over scripts/Assert-PfbDerivedArtifacts.ps1 -- the PR-time staleness gate.
.DESCRIPTION
    These assert on the script's SOURCE, never by running it. A full regeneration is minutes
    of work and needs tools/specs/, a gitignored ~50MB cache that most CI legs do not have --
    so an execution-based test would either blow the job's time budget or skip silently, which
    is the failure mode issue #63 was about in the first place.

    What is actually at risk here is the gate's COVERAGE: an artifact quietly dropped from the
    script's table stops being checked and nothing else notices. So the expected eleven are
    written out as a literal below rather than read back from the script.

    The script under test carries `#Requires -Version 7.0` because it invokes the generators.
    Nothing in this file does, so nothing here is edition-gated: it parses and reads text.
    5.1 CONSTRAINT: no `ConvertFrom-Json -Depth`, no ternaries, no `??`.
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:gatePath = Join-Path $repoRoot 'scripts/Assert-PfbDerivedArtifacts.ps1'
    $script:gateSource = Get-Content -Path $gatePath -Raw
    # Parsing rather than dot-sourcing or Get-Command: the script is PS7-only and would fail
    # to resolve at all on Windows PowerShell 5.1, and dot-sourcing it would run the gate.
    $script:gateAst = [System.Management.Automation.Language.Parser]::ParseFile($gatePath, [ref]$null, [ref]$null)
}

Describe 'Assert-PfbDerivedArtifacts artifact coverage' {

    It 'covers every one of the eleven derived artifacts' {
        # Deliberately a literal, not a re-read of the script's own table: comparing the script
        # against itself would pass however many artifacts were dropped from it.
        $expected = @(
            'Data/PfbCapabilityMap.json'
            'Data/PfbResponseShapeMap.json'
            'Reports/PfbValueEnumMap.json'
            'Reports/PfbValueEnumReconciliation.md'
            'Reports/PfbFieldCmdletMap.json'
            'Reports/PfbFieldCmdletMapping.md'
            'Reports/PfbPipelineSelectorMap.json'
            'Reports/PfbPipelineSelectorMap.md'
            'Reports/PfbApiDriftReport.json'
            'Reports/PfbApiDriftReport.md'
            'Reports/PfbDeadKeyReport.json'
        )

        foreach ($artifact in $expected) {
            $gateSource | Should -Match ([regex]::Escape("'$artifact'")) -Because "$artifact must stay in the gate's artifact table or it silently stops being checked"
        }
    }

    It 'excludes Data/PfbVersionMap.json' {
        # Update-PfbVersionMap.ps1 needs the SSOT_API_KEY secret, which GitHub does not expose
        # to a fork PR. Including this artifact would make the gate fail for want of a
        # credential rather than for staleness -- a red that says nothing about the change.
        $gateSource | Should -Not -Match ([regex]::Escape("'Data/PfbVersionMap.json'"))
    }

    It 'names each of the seven generators it must invoke' {
        $generators = @(
            'Build-PfbCapabilityMap.ps1'
            'Build-PfbResponseShapeMap.ps1'
            'Build-PfbValueEnumMap.ps1'
            'Build-PfbFieldCmdletMap.ps1'
            'Build-PfbPipelineSelectorMap.ps1'
            'Build-PfbApiDriftReport.ps1'
            'Build-PfbDeadKeyReport.ps1'
        )

        foreach ($generator in $generators) {
            $gateSource | Should -Match ([regex]::Escape($generator))
        }
    }
}

Describe 'Assert-PfbDerivedArtifacts parameter contract' {

    It 'exposes -SpecsDirectory, -WorkDirectory, -Artifact and -KeepWorkDirectory' {
        $names = @($gateAst.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })

        $names | Should -Contain 'SpecsDirectory'
        $names | Should -Contain 'WorkDirectory'
        $names | Should -Contain 'Artifact'
        $names | Should -Contain 'KeepWorkDirectory'
    }

    It 'declares PowerShell 7, since the generators it invokes require it' {
        $gateSource | Should -Match '#Requires -Version 7\.0'
    }
}

Describe 'Assert-PfbDerivedArtifacts comparison semantics' {

    It 'normalizes CRLF to LF before hashing' {
        # A regression guard on a decision that is INVISIBLE on the Linux CI leg: the repo has
        # no .gitattributes, so a Windows checkout holds Reports/*.md as CRLF while the
        # generators emit LF. Comparing raw bytes would pass in CI and fail for every Windows
        # developer -- wrong in the direction that teaches people to ignore the gate.
        $gateSource.Contains('Replace("`r`n", "`n")') | Should -BeTrue -Because 'the CRLF-to-LF normalization must survive any rewrite of the comparison'
    }

    It 'pins the spec set to the committed capability map generatedFrom list' {
        # Without the pin, a newly published REST version changes the drift report and reds an
        # unrelated PR -- the exact reason the pre-existing check was left advisory.
        $gateSource | Should -Match 'generatedFrom'
    }
}
