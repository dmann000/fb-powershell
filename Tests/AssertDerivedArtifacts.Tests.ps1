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

    # Pull the artifact list out of $script:ArtifactPlan STRUCTURALLY rather than by matching
    # literals in the raw text. A substring scan is defeated for the one artifact at the root
    # of the dependency graph: 'Data/PfbCapabilityMap.json' also appears in the spec-pinning
    # code, so dropping it from the plan would leave a text-matching test green while the gate
    # silently stopped checking the capability map.
    $script:planAssignment = $gateAst.Find({
        param($node)
        $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $node.Left.Extent.Text -eq '$script:ArtifactPlan'
    }, $true)

    $script:planArtifacts = @()
    if ($script:planAssignment) {
        $hashtables = $script:planAssignment.Right.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.HashtableAst]
        }, $true)
        foreach ($hashtable in $hashtables) {
            foreach ($pair in $hashtable.KeyValuePairs) {
                if ($pair.Item1.Extent.Text -eq 'Artifacts') {
                    $literals = $pair.Item2.FindAll({
                        param($node)
                        $node -is [System.Management.Automation.Language.StringConstantExpressionAst]
                    }, $true)
                    foreach ($literal in $literals) { $script:planArtifacts += $literal.Value }
                }
            }
        }
    }

    # Same treatment for the downstream-wiring table, so the guard below asserts on the
    # expressions actually passed to each generator rather than on prose about them.
    $script:stepArgumentPairs = @()
    $stepAssignment = $gateAst.Find({
        param($node)
        $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $node.Left.Extent.Text -eq '$stepArguments'
    }, $true)
    if ($stepAssignment) {
        # Pre-order traversal, so the first hashtable is the outer step->arguments map.
        $outer = $stepAssignment.Right.Find({
            param($node)
            $node -is [System.Management.Automation.Language.HashtableAst]
        }, $true)
        foreach ($stepPair in $outer.KeyValuePairs) {
            $inner = $stepPair.Item2.Find({
                param($node)
                $node -is [System.Management.Automation.Language.HashtableAst]
            }, $true)
            foreach ($argPair in $inner.KeyValuePairs) {
                $script:stepArgumentPairs += [pscustomobject]@{
                    Step       = $stepPair.Item1.Extent.Text.Trim("'")
                    Parameter  = $argPair.Item1.Extent.Text.Trim("'")
                    Expression = $argPair.Item2.Extent.Text
                }
            }
        }
    }
}

Describe 'Assert-PfbDerivedArtifacts artifact coverage' {

    It 'has a parseable $script:ArtifactPlan to assert against' {
        # If the extraction silently found nothing, every set assertion below would compare two
        # empty lists and pass vacuously. Fail here instead, loudly.
        $planAssignment | Should -Not -BeNullOrEmpty
        $planArtifacts.Count | Should -BeGreaterThan 0
    }

    It 'covers exactly the eleven derived artifacts, no more and no fewer' {
        # Deliberately a literal, not a re-read of the script's own table: comparing the script
        # against itself would pass however many artifacts were dropped from it. Set equality in
        # BOTH directions, so a dropped artifact and a stray twelfth entry each fail.
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

        $missing = @($expected | Where-Object { $planArtifacts -notcontains $_ })
        $unexpected = @($planArtifacts | Where-Object { $expected -notcontains $_ })

        $missing -join ', ' | Should -BeExactly '' -Because 'an artifact dropped from $script:ArtifactPlan silently stops being gated'
        $unexpected -join ', ' | Should -BeExactly '' -Because 'an artifact added to the plan without a generator wiring would throw at compare time, not here'
        $planArtifacts.Count | Should -Be 11
    }

    It 'excludes Data/PfbVersionMap.json' {
        # Update-PfbVersionMap.ps1 needs the SSOT_API_KEY secret, which GitHub does not expose
        # to a fork PR. Including this artifact would make the gate fail for want of a
        # credential rather than for staleness -- a red that says nothing about the change.
        #
        # Asserted against the AST-extracted plan, not the raw text: the script's description
        # mentions this path in prose explaining the exclusion, so a text scan would be testing
        # whether that prose happens to be unquoted.
        $planArtifacts | Should -Not -Contain 'Data/PfbVersionMap.json'
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

Describe 'Assert-PfbDerivedArtifacts load-bearing decisions' {
    # The plan names two decisions load-bearing. Both are implemented correctly and neither had
    # a guard, which is what these two blocks add.

    It 'stages specs one pinned version at a time, never the whole directory' {
        # If staging ever became a directory or wildcard copy, a spec published after the pin
        # would reach the generators and red an unrelated PR -- the precise failure that forced
        # the pre-existing check to stay advisory. The filename is built per pinned version.
        $gateSource.Contains('"fb$version.json"') | Should -BeTrue -Because 'the staged filename must be derived from each pinned version string'

        $copyLines = @($gateSource -split "`n" | Where-Object { $_ -match 'Copy-Item' })
        $copyLines.Count | Should -BeGreaterThan 0
        foreach ($line in $copyLines) {
            $line | Should -Not -Match '\*' -Because 'a wildcard copy would let an unpinned spec through'
            $line | Should -Not -Match '-Recurse' -Because 'a recursive copy of the cache would ignore the pin'
            # The source must be the per-version path built above, not the cache directory.
            $line | Should -Not -Match '-(Literal)?Path\s+\$SpecsDirectory\s*$'
        }
    }

    It 'feeds every downstream generator the regenerated upstream, never the committed one' {
        # This is the edge that can break SILENTLY. Build-PfbApiDriftReport.ps1 treats a missing
        # -ResponseShapeMapPath as an optional degradation rather than an error, so dropping
        # that DependsOn edge would not throw -- it would compare a report with empty response
        # findings against the committed one. That reds today only because the committed report
        # happens to carry non-empty responseFieldRemovals; if those ever legitimately empty
        # out it becomes a false pass reachable only via the -Artifact subset path, which a
        # full-set run can never exercise. Hence a structural assertion on the wiring.
        $stepArgumentPairs.Count | Should -BeGreaterThan 0 -Because 'an empty extraction would make every assertion below vacuous'

        # Public/ and Private/ are the SOURCE being checked, not derived artifacts, so they are
        # the only arguments legitimately pointed at the real repo.
        $repoRootedByDesign = @('PublicDirectory', 'PrivateDirectory')

        foreach ($pair in $stepArgumentPairs) {
            if ($repoRootedByDesign -contains $pair.Parameter) { continue }

            $pair.Expression | Should -Not -Match '\$repoRoot' -Because "$($pair.Step) -$($pair.Parameter) must not resolve against the repo working tree"

            if ($pair.Parameter -eq 'SpecsDirectory') {
                $pair.Expression | Should -Match '\$stagedSpecsDir' -Because 'generators must read the pinned staged specs, not the live cache'
            } elseif ($pair.Parameter -like '*Path') {
                $pair.Expression | Should -Match '\$out|\$regenerated' -Because "$($pair.Step) -$($pair.Parameter) must point into the scratch tree"
            }
        }
    }

    It 'wires the response-shape map into the drift report explicitly' {
        # Named separately because this is the one edge whose omission the generator would not
        # complain about (see the reasoning above).
        $driftShapeMap = @($stepArgumentPairs | Where-Object { $_.Step -eq 'ApiDriftReport' -and $_.Parameter -eq 'ResponseShapeMapPath' })

        $driftShapeMap.Count | Should -Be 1
        $driftShapeMap[0].Expression | Should -Match '\$regeneratedShapeMap'
    }

    It 'refuses a scratch directory it does not own, so cleanup cannot delete repo content' {
        # -WorkDirectory tools would make the staging directory the real tools/specs, which the
        # forced recursive cleanup then deletes. New-Item -Force no-ops on an existing
        # directory, so nothing else stops it.
        $gateSource | Should -Match 'already contains a .specs. or .out. subdirectory'
        $gateSource | Should -Match 'resolves inside the repository'
    }
}
