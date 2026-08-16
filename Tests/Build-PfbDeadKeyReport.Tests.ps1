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
    The total It count is unchanged by the split, so 5.1 still contributes exactly six skips.

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
    # Sharing one BeforeAll made a throw anywhere red all six tests, so a broken FIXTURE would
    # have reported the real generator as broken. Splitting also stops the synthetic half
    # depending on a cache it never reads. Both halves keep the PS7 gate, and the total It
    # count is unchanged, so 5.1 still contributes exactly six skips.

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

    It 'regenerates byte-for-byte identically to the committed Reports/PfbDeadKeyReport.json' {
        # THE stale-artifact check. Reds when the generator, the Public/ cmdlets, or the pinned
        # spec moved without the artifact being regenerated and committed alongside them.
        $committedBytes = [System.IO.File]::ReadAllBytes($committedReportPath)
        $regeneratedBytes = [System.IO.File]::ReadAllBytes($regeneratedPath)
        $regeneratedBytes.Length | Should -Be $committedBytes.Length -Because "the committed artifact is stale: regenerating produced $($regeneratedBytes.Length) bytes against the committed $($committedBytes.Length). Re-run tools/Build-PfbDeadKeyReport.ps1 and commit the result."

        $firstDifference = -1
        for ($i = 0; $i -lt [Math]::Min($committedBytes.Length, $regeneratedBytes.Length); $i++) {
            if ($committedBytes[$i] -ne $regeneratedBytes[$i]) { $firstDifference = $i; break }
        }
        $firstDifference | Should -Be -1 -Because "the committed artifact is stale: it first diverges from a fresh regeneration at byte $firstDifference. Re-run tools/Build-PfbDeadKeyReport.ps1 and commit the result."
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
            }
            paths      = [PSCustomObject]@{
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
}
