#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Rail A -- fails on any pipeline selector that coerces an object into a query selector
    unless the (cmdlet, parameter) pair is waived with an issue reference and a reason.
.DESCRIPTION
    This is a re-measurement rail, not a snapshot-diff rail. It re-probes every pair the
    committed report describes and judges the outcome fresh, so a genuine fix turns a waiver
    stale rather than reddening CI, and a reintroduced coercion reds it immediately. A
    committed baseline would have done the opposite: enshrined every unfixed finding as
    expected state and defended it.

    It reads the committed report but NEVER tools/specs. That cache is gitignored, and its
    absence silently skips roughly 27 drift tests in this repo while still reporting a pass --
    exactly the failure mode a rail against silent reintroduction must not share. The probe
    object is rebuilt from the report's own ProbeProperties/ProbeTypes fields instead.

    Waivers are keyed by (cmdlet, parameter) PAIR, not by (cmdlet, parameter, producer)
    triple. The 264 finding rows are producer multiplicity over 101 real defects; a
    triple-keyed file would be 264 entries against psd1's hard 500-element parse cap for a
    single collection literal, and would list the same defect up to a dozen times. The rail
    still names the producing endpoint in its failure text as evidence.

    The tooling this dot-sources is #Requires -Version 7.0, so the Describes are edition-gated
    AND the file-level BeforeAll guards its own body: a skipped Describe does not stop a
    file-level BeforeAll from running, and dot-sourcing a 7-only script under 5.1 kills the
    whole container rather than one test.
#>

# Discovery-phase, deliberately at file scope: Rail B's -Skip: expressions are evaluated while
# Pester discovers the tests, so a count computed in any BeforeAll would still be $null by then
# and the skip would never fire. Rail A is NOT gated on this -- see its Describe.
# The filter matches the generator's own (Build-PfbPipelineSelectorMap.ps1 reads 'fb*.json'):
# counting every file would let a stray editor temp file stand in for a missing spec, and would
# fail the completeness check on a cache that is actually complete.
$specCountAtDiscovery = @(Get-ChildItem (Join-Path (Split-Path -Parent $PSScriptRoot) 'tools/specs') `
        -Filter 'fb*.json' -File -ErrorAction SilentlyContinue).Count

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:reportPath = Join-Path $script:repoRoot 'Reports/PfbPipelineSelectorMap.json'
    $script:waiverPath = Join-Path $script:repoRoot 'Tests/Fixtures/PfbSelectorWaivers.psd1'

    # Defined in BeforeAll, not at file scope: file-scope code runs during DISCOVERY, and a
    # function left behind there is not in scope when the run phase executes an It. Verified --
    # the file-scope form failed with "the term ... is not recognized".
    function Get-PfbSelectorArtifactHash {
        <#
        .SYNOPSIS
            Hashes a generated report with its line endings normalised, so Rail B measures drift
            in the report rather than the checkout's newline policy.
        .DESCRIPTION
            Git checks these artifacts out with the platform's endings -- core.autocrlf is true
            on the GitHub Windows runners -- while the generator joins the Markdown with a hard
            "`n". A raw byte hash therefore compares a CRLF working copy against LF regenerated
            output and fails on Windows while Linux and macOS pass on an identical report, which
            is what run 31830362870 did. The JSON leg only passed there by accident:
            ConvertTo-Json emits CRLF on Windows, so it happened to match the CRLF checkout, and
            it would have failed the other way round for anyone with core.autocrlf=false.
            Normalise both, not the one that happened to break.

            Reading through ReadAllText also drops a byte-order mark, so a BOM difference between
            editions is likewise not treated as drift. Content is what this rail asserts.
        #>
        [CmdletBinding()]
        param([Parameter(Mandatory)][string]$Path)

        $text = [System.IO.File]::ReadAllText($Path) -replace "`r`n", "`n"
        $stream = [System.IO.MemoryStream]::new([System.Text.Encoding]::UTF8.GetBytes($text))
        try {
            (Get-FileHash -InputStream $stream -Algorithm SHA256).Hash
        }
        finally {
            $stream.Dispose()
        }
    }

    if ($PSVersionTable.PSVersion.Major -ge 7) {
        . (Join-Path $script:repoRoot 'tools/lib/PfbPipelineSelectorTools.ps1')
        . (Join-Path $script:repoRoot 'tools/lib/PfbSelectorProbeHarness.ps1')

        $script:report = Get-Content $script:reportPath -Raw | ConvertFrom-Json
        $script:waivers = @((Import-PowerShellDataFile $script:waiverPath).Waivers)
        $script:module = Initialize-PfbSelectorHarness `
            -ManifestPath (Join-Path $script:repoRoot 'PureStorageFlashBladePowerShell.psd1')

        # One fresh measurement, shared by every assertion below. Re-probing per It would
        # multiply the sweep cost by the number of tests for no extra evidence.
        $script:measured = [System.Collections.Generic.List[PSCustomObject]]::new()
        $aliasCache = @{}
        foreach ($row in $script:report.results) {
            # ProbeTypes must not degrade to @{}: an all-string probe binds cleanly to an
            # object-typed field and would hide the exact stringification this rail catches.
            $probeTypes = @{}
            foreach ($property in $row.ProbeTypes.PSObject.Properties) {
                $probeTypes[$property.Name] = $property.Value
            }
            # Enforced, not merely documented. A degraded map is the one failure the rest of this
            # rail cannot see: an all-string probe binds cleanly to an object-typed field, and
            # forcing every type to string can turn an object-valued field into a clean
            # by-property-name bind and hide a Coerced row. Pair-level waiving can leave the same
            # pair defective through another producer, so no assertion below would catch it.
            if ($probeTypes.Count -ne @($row.ProbeProperties).Count) {
                throw ("Report row $($row.Cmdlet)/$($row.Parameter) via $($row.Producer) has " +
                    "degraded ProbeTypes ($($probeTypes.Count) of $(@($row.ProbeProperties).Count)); " +
                    'an all-string probe would hide object-field stringification.')
            }

            # Aliases come from the live module, not the report -- Get-PfbSelectorOutcome needs
            # them to tell Bound from WrongScalar (Get-PfbArrayConnectionPath's -RemoteName
            # carries the alias Name, so a piped `name` binds it correctly). Omitting them would
            # manufacture WrongScalar verdicts the generator never observed.
            $aliasKey = "$($row.Cmdlet)/$($row.Parameter)"
            if (-not $aliasCache.ContainsKey($aliasKey)) {
                $command = Get-Command -Name $row.Cmdlet -Module $script:module.Name -ErrorAction Stop
                $aliasCache[$aliasKey] = @($command.Parameters[$row.Parameter].Aliases)
            }

            $probe = New-PfbSelectorProbeObject -ItemProperty @($row.ProbeProperties) -ItemType $probeTypes
            $result = Invoke-PfbSelectorProbe -Module $script:module -Cmdlet $row.Cmdlet -ProbeObject $probe
            $outcome = Get-PfbSelectorOutcome -ProbeResult $result -Parameter $row.Parameter `
                -WireName $row.WireName -ProbeObject $probe -Alias $aliasCache[$aliasKey]

            $script:measured.Add([PSCustomObject]@{
                    Cmdlet    = $row.Cmdlet
                    Parameter = $row.Parameter
                    Producer  = $row.Producer
                    # IsPrimary is a property of the cmdlet/producer relation, not a verdict, so
                    # reading it from the report costs the rail no independence -- and without it
                    # a Family-scoped waiver silently absorbs an escalation onto the primary
                    # producer, which is the chain a user would actually write.
                    IsPrimary = [bool]$row.IsPrimary
                    Outcome   = $outcome.Outcome
                    Evidence  = $outcome.Evidence
                })
        }
    }
}

Describe 'Rail A - no unwaived selector coercion' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {

    It 'proves its own isolation before trusting a single verdict' {
        # The harness replaces the module's Invoke-PfbApiRequest. Its silent failure mode is a
        # real network call, and on a Remove-Pfb* probe with a live array in scope that is a
        # real DELETE. Assert the shim is in place, in the module's own scope.
        $definition = & $script:module { (Get-Command Invoke-PfbApiRequest).Definition }
        $definition | Should -Match 'PfbSelectorProbeCapture'
    }

    It 'measured every pair the committed report describes' {
        $script:measured.Count | Should -Be @($script:report.results).Count
    }

    It 'every waiver names a cmdlet, a parameter, an issue and a reason' {
        # An unjustified waiver is indistinguishable from a suppressed test. The Issue field is
        # what keeps an unfixed finding visible as debt with a name attached.
        $script:waivers.Count | Should -BeGreaterThan 0
        foreach ($waiver in $script:waivers) {
            $waiver.Cmdlet | Should -Not -BeNullOrEmpty
            $waiver.Parameter | Should -Not -BeNullOrEmpty
            $waiver.Issue | Should -Match '^#\d+$'
            $waiver.Why | Should -Not -BeNullOrEmpty
            $waiver.Scope | Should -BeIn @('Primary', 'Family')
        }
    }

    It 'waives each pair exactly once' {
        $keys = @($script:waivers | ForEach-Object { "$($_.Cmdlet)/$($_.Parameter)" })
        $duplicates = @($keys | Group-Object | Where-Object { $_.Count -gt 1 } |
                ForEach-Object { $_.Name })
        $duplicates -join ', ' | Should -BeNullOrEmpty
    }

    It 'no pipeline selector coerces an object or binds the wrong scalar' {
        $waived = @($script:waivers | ForEach-Object { "$($_.Cmdlet)/$($_.Parameter)" })
        $failures = [System.Collections.Generic.List[string]]::new()

        foreach ($row in $script:measured) {
            if ($row.Outcome -notin @('Coerced', 'WrongScalar')) { continue }
            $key = "$($row.Cmdlet)/$($row.Parameter)"
            if ($key -in $waived) { continue }
            $failures.Add("$key via $($row.Producer) -> $($row.Outcome): $($row.Evidence)")
        }

        $failures -join "`n" | Should -BeNullOrEmpty
    }

    It 'no Family-scoped waiver has escalated onto its primary producer' {
        # A pair-keyed waiver is blind to WHERE the coercion happens, and 100 of the 101 are
        # waived precisely because the obvious chain -- the cmdlet's own base-path GET -- is
        # safe. Without this, a change that breaks property-name binding on, say,
        # Remove-PfbFileSystem would turn `Get-PfbFileSystem | Remove-PfbFileSystem` into a
        # DELETE carrying a stringified object, and the existing waiver would wave it through.
        # 39 of those 100 are Remove-* cmdlets.
        $declared = @{}
        foreach ($waiver in $script:waivers) { $declared["$($waiver.Cmdlet)/$($waiver.Parameter)"] = $waiver }

        $escalated = [System.Collections.Generic.List[string]]::new()
        foreach ($row in $script:measured) {
            if ($row.Outcome -notin @('Coerced', 'WrongScalar')) { continue }
            if (-not $row.IsPrimary) { continue }
            $waiver = $declared["$($row.Cmdlet)/$($row.Parameter)"]
            if ($waiver -and $waiver.Scope -eq 'Family') {
                $escalated.Add("$($row.Cmdlet)/$($row.Parameter) now coerces on its PRIMARY producer $($row.Producer): $($row.Evidence)")
            }
        }

        $escalated -join "`n" | Should -BeNullOrEmpty
    }

    It 'each waiver still covers exactly the producer count it was granted for' {
        # A pair spreading from one producing endpoint to nine is new debt, not the debt that
        # was reviewed. Producers is the blast radius the waiver was granted against.
        $counts = @{}
        foreach ($row in $script:measured) {
            if ($row.Outcome -notin @('Coerced', 'WrongScalar')) { continue }
            $key = "$($row.Cmdlet)/$($row.Parameter)"
            $counts[$key] = 1 + [int]$counts[$key]
        }

        $mismatched = [System.Collections.Generic.List[string]]::new()
        foreach ($waiver in $script:waivers) {
            $key = "$($waiver.Cmdlet)/$($waiver.Parameter)"
            $actual = [int]$counts[$key]
            if ($actual -ne $waiver.Producers) {
                $mismatched.Add("$key waived for $($waiver.Producers) producer(s), measured $actual")
            }
        }

        $mismatched -join "`n" | Should -BeNullOrEmpty
    }

    It 'carries no waiver for a pair that no longer coerces' {
        # The other direction of the same contract: once a finding is fixed its waiver must go,
        # or the register stops describing the real debt and the next reintroduction is waved
        # through by a waiver nobody remembers granting.
        $defective = @($script:measured |
                Where-Object { $_.Outcome -in @('Coerced', 'WrongScalar') } |
                ForEach-Object { "$($_.Cmdlet)/$($_.Parameter)" } |
                Sort-Object -Unique)
        $stale = @($script:waivers |
                ForEach-Object { "$($_.Cmdlet)/$($_.Parameter)" } |
                Where-Object { $_ -notin $defective })
        $stale -join ', ' | Should -BeNullOrEmpty
    }

    It 'still measures every pair it used to: BindError stays at 4 rows' {
        # Only BindError means UNMEASURED -- Unbindable (PowerShell declined to bind at all)
        # and CmdletError (the cmdlet threw before the shim) are verdicts carrying evidence.
        # A rise here means the harness has started refusing cmdlets it used to measure, which
        # is precisely the regression that produced the original 33-pair blind spot.
        #
        # BindError is an OUTCOME, not an ErrorKind. ErrorKind is non-null on 359 rows (233
        # InputObjectNotBound, 122 CmdletError, 2 ParameterBindingError, 2 HarnessRefusal);
        # only the ParameterBindingError and HarnessRefusal rows classify as the BindError
        # outcome, and only that outcome means unmeasured. Asserting on
        # ErrorKind -eq 'BindError' matches nothing at all.
        #
        # RE-BASELINED 2 -> 4, with the movement accounted for rather than absorbed. The two
        # new rows are both Update-PfbLegalHoldEntity/Name, refused as "would prompt for an
        # unbound mandatory parameter" once -Released became mandatory (the required-query-key
        # fix for dmann000/fb-powershell#106 Part 2). They were Bound and Unbindable before.
        #
        # This is the honest cost of that fix and not a harness regression: the probe supplies
        # a selector and nothing else, so a REQUIRED parameter it does not know to supply
        # cannot be bound, and the row it replaces measured `names=PROBE-name` on a key that
        # cannot identify a held entity anyway (#139).
        #
        # It does generalise, which is what a future reader needs to know: any fix that
        # correctly makes a required parameter mandatory converts that cmdlet's
        # pipeline-selector coverage into a triage row. If this number climbs again for that
        # reason, the answer is probably to teach the probe generator to satisfy mandatory
        # parameters outside the selector under test -- not to keep re-baselining.
        @($script:measured | Where-Object { $_.Outcome -eq 'BindError' }).Count | Should -Be 4
    }
}

Describe 'Rail B - committed map matches regeneration' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {

    BeforeAll {
        $script:specsDirectory = Join-Path $script:repoRoot 'tools/specs'
        $script:specCount = @(Get-ChildItem $script:specsDirectory -Filter 'fb*.json' -File `
                -ErrorAction SilentlyContinue).Count
    }

    It 'sees the whole spec cache when it is present' -Skip:($specCountAtDiscovery -eq 0) {
        # Follows the existing drift-test convention: skip when the gitignored cache is absent,
        # but never quietly run against a partial one -- a short cache produces a smaller map
        # that would then be declared drift.
        $script:specCount | Should -Be 29
    }

    It 'regenerates the report identically, JSON and Markdown alike' -Skip:($specCountAtDiscovery -eq 0) {
        $temp = Join-Path $TestDrive 'regen.json'
        & (Join-Path $script:repoRoot 'tools/Build-PfbPipelineSelectorMap.ps1') -OutputPath $temp

        # Line-ending-normalised, not byte-for-byte -- see Get-PfbSelectorArtifactHash.
        Get-PfbSelectorArtifactHash $temp |
            Should -Be (Get-PfbSelectorArtifactHash (Join-Path $script:repoRoot 'Reports/PfbPipelineSelectorMap.json'))

        # The .md is written alongside the JSON with the same base name, and it is the artifact a
        # human reads -- drift there is just as much drift.
        Get-PfbSelectorArtifactHash ([System.IO.Path]::ChangeExtension($temp, '.md')) |
            Should -Be (Get-PfbSelectorArtifactHash (Join-Path $script:repoRoot 'Reports/PfbPipelineSelectorMap.md'))
    }
}
