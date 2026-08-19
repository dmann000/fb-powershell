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
    $script:planEntries = @()
    if ($script:planAssignment) {
        $hashtables = $script:planAssignment.Right.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.HashtableAst]
        }, $true)
        foreach ($hashtable in $hashtables) {
            $entryStep = ''
            $entryDependsOn = @()
            $entryArtifacts = @()
            foreach ($pair in $hashtable.KeyValuePairs) {
                $literals = $pair.Item2.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.StringConstantExpressionAst]
                }, $true)
                $values = @($literals | ForEach-Object { $_.Value })

                switch ($pair.Item1.Extent.Text) {
                    'Step'      { if ($values.Count -gt 0) { $entryStep = $values[0] } }
                    'DependsOn' { $entryDependsOn = $values }
                    'Artifacts' {
                        $entryArtifacts = $values
                        $script:planArtifacts += $values
                    }
                }
            }
            $script:planEntries += [pscustomobject]@{
                Step      = $entryStep
                DependsOn = $entryDependsOn
                Artifacts = $entryArtifacts
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
        #
        # Asserted over the AST, not the raw text. `$gateSource | Should -Match 'generatedFrom'`
        # -- what this test used to be -- also matches this very comment, the throw messages and
        # the Write-Host progress line, so it stayed green with the pin deleted outright. It
        # guarded the word, not the mechanism.
        #
        # The pin is two linked facts, and breaking either one unpins the run: $pinnedVersions
        # is READ from the committed capability map's generatedFrom, and the staging loop
        # ITERATES it. A gate that reads the pin but stages the whole cache is not pinned.
        $pinAssignment = $gateAst.Find({
            param($node)
            $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $node.Left.Extent.Text -eq '$pinnedVersions'
        }, $true)

        $pinAssignment | Should -Not -BeNullOrEmpty -Because 'without an assignment to $pinnedVersions there is no pin at all'
        $pinAssignment.Right.Extent.Text | Should -Match 'generatedFrom' -Because 'the pinned set must come from the committed map, not from whatever is in tools/specs'
        $pinAssignment.Right.Extent.Text | Should -Match 'CapabilityMap' -Because 'generatedFrom must be read off the committed capability map specifically'

        $stagingLoop = $gateAst.Find({
            param($node)
            $node -is [System.Management.Automation.Language.ForEachStatementAst] -and
            $node.Condition.Extent.Text -eq '$pinnedVersions'
        }, $true)

        $stagingLoop | Should -Not -BeNullOrEmpty -Because 'a pin nothing iterates over is decoration -- staging must walk the pinned versions'
        $stagingLoop.Body.Extent.Text | Should -Match 'Copy-Item' -Because 'the staging copy must happen once per pinned version, inside that loop'
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
        # SCOPE: this binds the ARGUMENT EXPRESSIONS in $stepArguments -- what each generator is
        # handed. It does NOT bind $ArtifactPlan's DependsOn column, which decides which steps a
        # subset run actually EXECUTES. Both are needed and they fail differently: a wrong
        # expression here points a generator at the committed tree, whereas a missing DependsOn
        # edge leaves the expression correct but never regenerates the file it names, so the
        # generator reads a stale or absent scratch upstream. The DependsOn edges have their own
        # guard in the next test.
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

    It 'declares the exact dependency edges that make a subset run regenerate its upstreams' {
        # THE SUBSET PATH IS THE LOCAL PATH. CI always runs the full set, so every step executes
        # there regardless of this column -- CI is a backstop. A developer running -Artifact
        # before pushing is the one who gets burned, and the whole reason this logic lives in
        # scripts/ rather than inline in the workflow is to be trustworthy at that moment.
        #
        # Worst case is ApiDriftReport -> ResponseShapeMap. Build-PfbApiDriftReport.ps1:141-156
        # treats a missing -ResponseShapeMapPath as an OPTIONAL degradation rather than an
        # error, so dropping that edge does not throw: the subset run simply never regenerates
        # the shape map, the drift report is built with empty response findings, and it is
        # compared against the committed copy. That reds today only because the committed report
        # happens to carry non-empty responseFieldRemovals. If those ever legitimately empty
        # out, it becomes a silent false pass on the subset path only.
        #
        # The other six edges fail safe -- their generators hard-throw on a missing upstream --
        # but they are asserted too, so the table is pinned as a whole rather than at one spot.
        $expectedEdges = @{
            'CapabilityMap'       = @()
            'ResponseShapeMap'    = @()
            'ValueEnumMap'        = @()
            'FieldCmdletMap'      = @()
            'PipelineSelectorMap' = @('ResponseShapeMap')
            'ApiDriftReport'      = @('CapabilityMap', 'ResponseShapeMap', 'FieldCmdletMap')
            'DeadKeyReport'       = @('CapabilityMap')
        }

        $planEntries.Count | Should -Be 7 -Because 'an empty or partial extraction would make the edge assertions vacuous'

        foreach ($step in $expectedEdges.Keys) {
            $entry = @($planEntries | Where-Object { $_.Step -eq $step })
            $entry.Count | Should -Be 1 -Because "step '$step' must appear exactly once in the plan"

            $expected = $expectedEdges[$step]
            $actual = $entry[0].DependsOn

            $missing = @($expected | Where-Object { $actual -notcontains $_ })
            $extra = @($actual | Where-Object { $expected -notcontains $_ })

            $missing -join ', ' | Should -BeExactly '' -Because "$step must regenerate these upstreams before it runs on the -Artifact subset path"
            $extra -join ', ' | Should -BeExactly '' -Because "$step declares a dependency it does not have, which needlessly slows a subset run"
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
        #
        # Asserted over the AST rather than against the throw messages -- this test used to
        # match the error prose, which means rewording a sentence silently disarms the guard on
        # the one code path that deletes directories with -Recurse -Force. Bind the CONDITIONS
        # instead: what each guard compares, and that it refuses rather than repairs.
        $guardIfs = @($gateAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.IfStatementAst]
        }, $true) | Where-Object {
            $_.Clauses[0].Item2.Extent.Text -match 'throw'
        })

        $containment = @($guardIfs | Where-Object { $_.Clauses[0].Item1.Extent.Text -match '\$resolvedWork' })
        $containment.Count | Should -BeGreaterThan 0 -Because 'a scratch path inside the repo must be refused outright, never repaired'
        $containment[0].Clauses[0].Item1.Extent.Text | Should -Match '\$resolvedRepo' -Because 'the refusal is meaningless unless it compares the scratch path against the repo root'

        $reuse = @($guardIfs | Where-Object { $_.Clauses[0].Item1.Extent.Text -match '\$stagedSpecsDir' })
        $reuse.Count | Should -BeGreaterThan 0 -Because 'a directory already holding specs/ or out/ must be refused -- cleanup deletes both'
        $reuse[0].Clauses[0].Item1.Extent.Text | Should -Match '\$outRoot' -Because 'both subtrees the cleanup deletes must be checked, not just the specs one'

        # Order matters as much as presence. A guard that fires after the directory exists has
        # already lost: staging would have written into the repo, and $createdWorkDirectory
        # would be set, which is what authorises the recursive delete in the finally block.
        $createIndex = $gateSource.IndexOf('$createdWorkDirectory = $true')
        $createIndex | Should -BeGreaterThan 0 -Because 'the anchor this ordering check depends on must still exist'
        foreach ($guard in @($containment[0], $reuse[0])) {
            $guard.Extent.StartOffset | Should -BeLessThan $createIndex -Because 'a guard cannot prevent a deletion that its own directory creation has already authorised'
        }
    }
}
