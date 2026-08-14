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
    triple. The 389 finding rows are producer multiplicity over 127 real defects; a
    triple-keyed file would be 389 entries against psd1's hard 500-element parse cap for a
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
$specCountAtDiscovery = @(Get-ChildItem (Join-Path (Split-Path -Parent $PSScriptRoot) 'tools/specs') `
        -File -ErrorAction SilentlyContinue).Count

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:reportPath = Join-Path $script:repoRoot 'Reports/PfbPipelineSelectorMap.json'
    $script:waiverPath = Join-Path $script:repoRoot 'Tests/Fixtures/PfbSelectorWaivers.psd1'

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

    It 'still measures every pair it used to: BindError stays at 2 rows' {
        # Only BindError means UNMEASURED -- Unbindable (PowerShell declined to bind at all)
        # and CmdletError (the cmdlet threw before the shim) are verdicts carrying evidence.
        # A rise here means the harness has started refusing cmdlets it used to measure, which
        # is precisely the regression that produced the original 33-pair blind spot.
        #
        # BindError is an OUTCOME, not an ErrorKind: Get-PfbSelectorOutcome classifies the
        # refusal, and $result.ErrorKind is null on every row of the committed report.
        @($script:measured | Where-Object { $_.Outcome -eq 'BindError' }).Count | Should -Be 2
    }
}

Describe 'Rail B - committed map matches regeneration' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {

    BeforeAll {
        $script:specsDirectory = Join-Path $script:repoRoot 'tools/specs'
        $script:specCount = @(Get-ChildItem $script:specsDirectory -File -ErrorAction SilentlyContinue).Count
    }

    It 'sees the whole spec cache when it is present' -Skip:($specCountAtDiscovery -eq 0) {
        # Follows the existing drift-test convention: skip when the gitignored cache is absent,
        # but never quietly run against a partial one -- a short cache produces a smaller map
        # that would then be declared drift.
        $script:specCount | Should -Be 29
    }

    It 'regenerates the report byte for byte, JSON and Markdown alike' -Skip:($specCountAtDiscovery -eq 0) {
        $temp = Join-Path $TestDrive 'regen.json'
        & (Join-Path $script:repoRoot 'tools/Build-PfbPipelineSelectorMap.ps1') -OutputPath $temp

        (Get-FileHash $temp).Hash |
            Should -Be (Get-FileHash (Join-Path $script:repoRoot 'Reports/PfbPipelineSelectorMap.json')).Hash

        # The .md is written alongside the JSON with the same base name, and it is the artifact a
        # human reads -- drift there is just as much drift.
        (Get-FileHash ([System.IO.Path]::ChangeExtension($temp, '.md'))).Hash |
            Should -Be (Get-FileHash (Join-Path $script:repoRoot 'Reports/PfbPipelineSelectorMap.md')).Hash
    }
}
