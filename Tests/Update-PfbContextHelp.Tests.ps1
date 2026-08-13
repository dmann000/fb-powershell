#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Tests for tools/Update-PfbContextHelp.ps1, the generator that writes the
    context-requirement .NOTES block into every non-default-scope cmdlet's
    comment-based help.
.DESCRIPTION
    Notes on deliberate choices here:

    * No Should -BeNullOrEmpty anywhere, in either polarity. This whole feature turns on
      the difference between $null (nothing recorded / nothing to emit) and an explicit
      empty value, and -BeNullOrEmpty cannot tell them apart. Assert `$null -eq $x`
      instead, or [string]::IsNullOrEmpty($x) when "neither null nor empty" really is the
      claim. The negated -Not -BeNullOrEmpty is unambiguous on its own, but it is still
      banned here so the rule needs no case analysis to apply.

    * Every path is derived from $PSScriptRoot. The Pester runner does not run with the
      repo root as its working directory, so CWD-relative paths would silently fail.

    * The idempotency assertion runs the generator with -WhatIf against the real,
      already-generated tree and asserts it reports zero would-be changes. That is a
      fixed-point assertion with exactly the same strength as write-twice-and-compare,
      but it cannot corrupt tracked Public/ files or leave the worktree dirty when it
      fails.

    * InModuleScope appears INSIDE the It that needs it, never wrapped around a Describe
      body (which fails at discovery time in this repo and silently never runs).
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:generator = Join-Path $script:repoRoot 'tools/Update-PfbContextHelp.ps1'
    $script:presetFile = Join-Path $script:repoRoot 'Public/Presets/New-PfbPresetWorkload.ps1'
    $script:manifest = Join-Path $script:repoRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $script:manifest -Force
}

Describe 'Update-PfbContextHelp' {
    It 'emits a fleet-context requirement line for a fleet-scoped endpoint' {
        $line = & $script:generator -EmitLineOnly -Scope 'fleet' -EndpointKey 'POST /presets/workload'
        $line | Should -BeLike '*fleet context*'
        $line | Should -BeLike '*Set-PfbContext*'
        # The endpoint key is quoted back so the reader can see which call is scoped.
        $line.Contains('POST /presets/workload') | Should -BeTrue
    }

    It 'emits a not-recorded / no-pre-validation line for an unknown-scoped endpoint' {
        $line = & $script:generator -EmitLineOnly -Scope 'unknown' -EndpointKey 'GET /realms'
        # Assert on substrings that do not straddle the block's own line wrapping --
        # "is not / recorded" is split across two lines in the rendered block.
        $line.Contains('recorded in the capability map') | Should -BeTrue
        $line.Contains('will not pre-validate') | Should -BeTrue
    }

    It 'emits nothing for an array-scoped endpoint' {
        $line = & $script:generator -EmitLineOnly -Scope 'array' -EndpointKey 'GET /file-systems'
        $null -eq $line | Should -BeTrue
    }

    It 'throws when -EmitLineOnly is used without -Scope' {
        { & $script:generator -EmitLineOnly -EndpointKey 'GET /realms' } |
            Should -Throw -ExpectedMessage '*-EmitLineOnly requires both -Scope and -EndpointKey*'
    }

    It 'wraps the emitted block in the do-not-edit delimiters' {
        $line = & $script:generator -EmitLineOnly -Scope 'fleet' -EndpointKey 'POST /presets/workload'
        # The exact opening form is pinned HERE and nowhere else, because Get-Help renders it
        # verbatim to the user -- so a reword is a user-visible change and should break one
        # named test rather than several. Contains() is case-sensitive, which is the point:
        # the lower-case wording is deliberate.
        $line.Contains('<!-- PfbContext (generated; do not edit) -->') | Should -BeTrue
        $line.Contains('<!-- /PfbContext -->') | Should -BeTrue
    }

    It 'is idempotent: a -WhatIf run against the generated tree reports zero changes' {
        # The block is delimited, so a second run REPLACES rather than appends. An
        # appending generator would grow the help on every regeneration and would show
        # up here as a non-zero would-change count.
        $summary = & $script:generator -WhatIf
        $summary.Changed.Count | Should -Be 0
    }

    It 'reports every non-default-scope endpoint that has no matching cmdlet file' {
        $summary = & $script:generator -WhatIf
        # Reported, never silently skipped: a silent skip reads as "covered everything".
        $summary.PSObject.Properties.Name | Should -Contain 'MissingCmdlet'
        foreach ($entry in $summary.MissingCmdlet) {
            [string]::IsNullOrEmpty($entry.EndpointKey) | Should -BeFalse
        }
    }

    It 'accounts for every non-default-scope endpoint as either generated or missing' {
        # The strong form of the reporting requirement: no non-default-scope endpoint may
        # fall off the end. Each must appear verbatim in a generated block or in
        # MissingCmdlet. Asserted as an invariant rather than a pinned count, because the
        # capability map is regenerated whenever the specs are refreshed.
        $summary = & $script:generator -WhatIf
        $mapPath = Join-Path $script:repoRoot 'Data/PfbCapabilityMap.json'
        $map = Get-Content $mapPath -Raw | ConvertFrom-Json

        $nonDefault = @(
            $map.endpoints.PSObject.Properties |
                Where-Object {
                    # Mirrors the generator's own selection exactly, including the explicit
                    # null test -- a truthiness test here would fold an empty scope in with
                    # an absent one and quietly stop asserting on it.
                    $null -ne $_.Value.contextScope.scope -and $_.Value.contextScope.scope -ne 'array'
                } |
                ForEach-Object { $_.Name }
        )
        $nonDefault.Count | Should -BeGreaterThan 0

        $generatedText = ($summary.Generated | ForEach-Object { Get-Content $_ -Raw }) -join "`n"
        $missingKeys = @($summary.MissingCmdlet | ForEach-Object { $_.EndpointKey })
        $unrenderedKeys = @($summary.UnrecognisedScope | ForEach-Object { $_.EndpointKey })

        foreach ($key in $nonDefault) {
            $accounted = $generatedText.Contains("($key)") -or
                ($missingKeys -contains $key) -or
                ($unrenderedKeys -contains $key)
            $accounted | Should -BeTrue -Because "$key must be documented, or reported as having no cmdlet or no render arm"
        }
    }

    It 'generates the line from contextScope, so help cannot drift from validation' {
        InModuleScope PureStorageFlashBladePowerShell {
            $map = Get-PfbCapabilityMap
            $map.endpoints.'POST /presets/workload'.contextScope.scope | Should -Be 'fleet'
        }
        (Get-Content $script:presetFile -Raw) | Should -BeLike '*fleet context*'
    }

    It 'renders a fleet-scoped GET differently from a fleet-scoped write' {
        # The runtime gate (Assert-PfbContextRequired) is narrower for GET than for the write
        # verbs, twice over, and both narrowings are measured. Emitting the write wording for a
        # GET told the reader an unfiltered list requires a fleet context, six lines below the
        # .EXAMPLE showing exactly that context-free call. So the two must not read alike.
        $write = & $script:generator -EmitLineOnly -Scope 'fleet' -EndpointKey 'POST /presets/workload'
        $get = & $script:generator -EmitLineOnly -Scope 'fleet' -EndpointKey 'GET /presets/workload'

        $null -eq $get | Should -BeFalse
        # Strip the endpoint key, which differs on its own, so this compares the WORDING.
        ($get -replace 'GET /presets/workload', 'X') -eq ($write -replace 'POST /presets/workload', 'X') |
            Should -BeFalse -Because 'a fleet-scoped GET must not inherit the write verbs'' wording'

        # The write arm states the requirement unconditionally; the GET arm must say the
        # unfiltered read needs no context.
        $write.Contains('requires a bare fleet context') | Should -BeTrue
        $get.Contains('An unfiltered list works with NO context') | Should -BeTrue
    }

    It 'requires a context for a name-scoped fleet GET only where that was measured' {
        # GET /presets/workload is on $script:PfbNameScopedContextRequiredEndpoints; the three
        # fleet-scoped topology-group GETs are deliberately NOT, because a name-scoped
        # context-free read returns 200 on them. The help must reflect that split rather than
        # asserting the requirement for every fleet-scoped GET -- and it must read the split
        # from the module's own allowlist, so adding an endpoint there changes the help.
        $onList = & $script:generator -EmitLineOnly -Scope 'fleet' -EndpointKey 'GET /presets/workload'
        $offList = & $script:generator -EmitLineOnly -Scope 'fleet' -EndpointKey 'GET /topology-groups'

        $onList.Contains('Filtering by name or id needs a') | Should -BeTrue
        $offList.Contains('None is required') | Should -BeTrue
        $offList.Contains('Filtering by name or id needs a') | Should -BeFalse
    }

    It 'covers every non-default-scope endpoint that maps to a cmdlet' {
        $summary = & $script:generator -WhatIf
        $summary.Generated.Count | Should -BeGreaterThan 0
        foreach ($file in $summary.Generated) {
            # Presence checks use the stable prefix, so rewording the delimiter's prose does
            # not require touching every assertion in this file.
            (Get-Content $file -Raw).Contains('<!-- PfbContext') | Should -BeTrue
        }
    }

    It 'leaves array-scoped cmdlets untouched' {
        $arrayScoped = Join-Path $script:repoRoot 'Public/FileSystem/Get-PfbFileSystem.ps1'
        (Get-Content $arrayScoped -Raw).Contains('<!-- PfbContext') | Should -BeFalse
    }

    Context 'line endings' {
        # THE BUG THESE EXIST FOR. The block was assembled with hardcoded CRLF and spliced
        # into whatever the target file already had. The repo commits LF blobs, so a Windows
        # checkout is CRLF (matches, green) while a Linux/macOS checkout is LF (mismatches on
        # EVERY file). The generator then reported all 24 files as changed and the idempotency
        # test above failed with "Expected 0, but got 24" -- on ubuntu and macos only, while
        # both Windows legs passed.
        #
        # That test cannot catch this on any single runner, because it only ever sees the
        # local platform's convention. These two build BOTH conventions explicitly, so they
        # fail everywhere when the splice stops adopting the target file's line ending.
        BeforeAll {
            function New-NewlineFixture {
                param([string]$Root, [string]$Newline)

                $publicRoot = Join-Path $Root 'Public'
                New-Item -ItemType Directory -Path $publicRoot -Force | Out-Null

                $utf8 = New-Object System.Text.UTF8Encoding($false)
                $mapPath = Join-Path $Root 'map.json'
                $map = @{ endpoints = @{ 'GET /zzz-gadgets' = @{ contextScope = @{ scope = 'fleet' } } } } |
                    ConvertTo-Json -Depth 6
                [System.IO.File]::WriteAllText($mapPath, $map, $utf8)

                # WriteAllText with an explicit join, NOT Set-Content: Set-Content would
                # impose the platform's newline and defeat the entire point of the fixture.
                $file = Join-Path $publicRoot 'Get-ZzzGadget.ps1'
                $lines = @(
                    '<#'
                    '.SYNOPSIS'
                    '    Synthetic fixture for Get-ZzzGadget.'
                    '#>'
                    'function Get-ZzzGadget {'
                    "    Invoke-PfbApiRequest -Method GET -Endpoint 'zzz-gadgets'"
                    '}'
                )
                [System.IO.File]::WriteAllText($file, ($lines -join $Newline) + $Newline, $utf8)

                return [PSCustomObject]@{ MapPath = $mapPath; PublicRoot = $publicRoot; File = $file }
            }
        }

        It 'adopts LF and is idempotent against an LF-only file' {
            $fx = New-NewlineFixture -Root (Join-Path $TestDrive 'lf') -Newline "`n"
            & $script:generator -CapabilityMapPath $fx.MapPath -PublicRoot $fx.PublicRoot -Confirm:$false | Out-Null

            $written = [System.IO.File]::ReadAllText($fx.File)
            $written.Contains('<!-- PfbContext') | Should -BeTrue
            # The block went in without dragging CRLF along with it.
            $written.Contains("`r`n") | Should -BeFalse

            $again = & $script:generator -WhatIf -CapabilityMapPath $fx.MapPath -PublicRoot $fx.PublicRoot
            $again.Changed.Count | Should -Be 0
        }

        It 'adopts CRLF and is idempotent against a CRLF file' {
            $fx = New-NewlineFixture -Root (Join-Path $TestDrive 'crlf') -Newline "`r`n"
            & $script:generator -CapabilityMapPath $fx.MapPath -PublicRoot $fx.PublicRoot -Confirm:$false | Out-Null

            $written = [System.IO.File]::ReadAllText($fx.File)
            $written.Contains('<!-- PfbContext') | Should -BeTrue
            # No BARE LF anywhere -- a lookbehind, because a plain -notmatch "`n" would also
            # reject the LF half of every legitimate CRLF pair.
            [regex]::IsMatch($written, "(?<!`r)`n") | Should -BeFalse

            $again = & $script:generator -WhatIf -CapabilityMapPath $fx.MapPath -PublicRoot $fx.PublicRoot
            $again.Changed.Count | Should -Be 0
        }
    }

    Context 'a scope value the generator has no render arm for' {
        BeforeAll {
            function New-ScopeFixture {
                <#
                    Builds a throwaway capability map and Public/ tree under $TestDrive. Two
                    endpoints, deliberately: one the generator renders and one it cannot, so
                    the tests can tell "the odd endpoint was reported" apart from "the run
                    aborted" or "its neighbour was collateral damage".

                    No -Encoding on the writes: the content is pure ASCII, and asking for
                    UTF8 would add a BOM under Windows PowerShell 5.1 that ConvertFrom-Json
                    then chokes on.
                #>
                param([string]$Root, [string]$OddScope)

                $publicRoot = Join-Path $Root 'Public'
                New-Item -ItemType Directory -Path $publicRoot -Force | Out-Null

                $mapPath = Join-Path $Root 'map.json'
                @{
                    endpoints = @{
                        'GET /zzz-widgets' = @{ contextScope = @{ scope = $OddScope } }
                        'GET /zzz-gadgets' = @{ contextScope = @{ scope = 'fleet' } }
                    }
                } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $mapPath

                foreach ($pair in @(@('Get-ZzzWidget', 'zzz-widgets'), @('Get-ZzzGadget', 'zzz-gadgets'))) {
                    @(
                        '<#'
                        '.SYNOPSIS'
                        "    Synthetic fixture for $($pair[0])."
                        '#>'
                        "function $($pair[0]) {"
                        "    Invoke-PfbApiRequest -Method GET -Endpoint '$($pair[1])'"
                        '}'
                    ) | Set-Content -LiteralPath (Join-Path $publicRoot "$($pair[0]).ps1")
                }

                return [PSCustomObject]@{ MapPath = $mapPath; PublicRoot = $publicRoot }
            }
        }

        It 'reports the endpoint rather than dropping it silently' {
            $fx = New-ScopeFixture -Root (Join-Path $TestDrive 'unrenderable') -OddScope 'quantum'
            $summary = & $script:generator -WhatIf -CapabilityMapPath $fx.MapPath -PublicRoot $fx.PublicRoot `
                -WarningVariable warnings -WarningAction SilentlyContinue

            @($summary.UnrecognisedScope).Count | Should -Be 1
            $summary.UnrecognisedScope[0].EndpointKey | Should -BeExactly 'GET /zzz-widgets'
            $summary.UnrecognisedScope[0].Scope | Should -BeExactly 'quantum'

            # A warning as well as a summary entry. A maintainer regenerating by hand reads
            # the console, not the returned object, and a clean-looking run over N silently
            # undocumented endpoints is exactly the "covered everything" illusion the
            # MissingCmdlet path already guards against.
            ($warnings -join "`n").Contains('quantum') | Should -BeTrue

            # The renderable neighbour still generated: this is a report, not an abort.
            @($summary.Generated).Count | Should -Be 1
            $summary.Generated[0] | Should -BeLike '*Get-ZzzGadget.ps1'
        }

        It 'treats an explicitly empty scope as unrecognised, not as the array default' {
            # The phase's tri-state ruling applied here: an ABSENT scope is unset, needs no
            # note, and stays out. A scope that is PRESENT and empty is a recorded value
            # that happens to say nothing -- so it is reported, never quietly read as the
            # 'array' default. Collapsing the two is what a truthiness test would do.
            $fx = New-ScopeFixture -Root (Join-Path $TestDrive 'emptyscope') -OddScope ''
            $summary = & $script:generator -WhatIf -CapabilityMapPath $fx.MapPath -PublicRoot $fx.PublicRoot `
                -WarningAction SilentlyContinue

            @($summary.UnrecognisedScope).Count | Should -Be 1
            $summary.UnrecognisedScope[0].EndpointKey | Should -BeExactly 'GET /zzz-widgets'
            $summary.UnrecognisedScope[0].Scope | Should -BeExactly ''
        }
    }

    Context 'a block whose opening delimiter was worded differently' {
        It 'replaces it rather than leaving two blocks behind' {
            # The opening delimiter is rendered to users by Get-Help, so its prose is expected
            # to change. This is the failure that would follow: strip keyed on the FULL
            # opening literal matches nothing after a reword, so the run inserts a second
            # block beside the first, and every later run adds another. The idempotency test
            # cannot catch it -- by then the tree is already current, so nothing needs
            # stripping. Fixture carries the previous real wording, which makes this the
            # migration proof as well as the regression guard.
            $legacyOpen = '<!-- PfbContext: generated from Data/PfbCapabilityMap.json contextScope. Do not edit. -->'

            $root = Join-Path $TestDrive 'reworded'
            $publicRoot = Join-Path $root 'Public'
            New-Item -ItemType Directory -Path $publicRoot -Force | Out-Null

            $mapPath = Join-Path $root 'map.json'
            @{ endpoints = @{ 'GET /zzz-gadgets' = @{ contextScope = @{ scope = 'fleet' } } } } |
                ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $mapPath

            $cmdletPath = Join-Path $publicRoot 'Get-ZzzGadget.ps1'
            @(
                '<#'
                '.SYNOPSIS'
                '    Synthetic fixture carrying a stale, differently-worded block.'
                '.NOTES'
                "    $legacyOpen"
                '    Stale prose that must not survive the run.'
                '    <!-- /PfbContext -->'
                '#>'
                'function Get-ZzzGadget {'
                "    Invoke-PfbApiRequest -Method GET -Endpoint 'zzz-gadgets'"
                '}'
            ) | Set-Content -LiteralPath $cmdletPath

            # Not -WhatIf: the strip-and-reinsert has to actually land on disk to be counted.
            & $script:generator -CapabilityMapPath $mapPath -PublicRoot $publicRoot |
                Out-Null

            $text = Get-Content $cmdletPath -Raw
            [regex]::Matches($text, [regex]::Escape('<!-- PfbContext')).Count | Should -Be 1
            [regex]::Matches($text, [regex]::Escape('<!-- /PfbContext -->')).Count | Should -Be 1
            $text.Contains($legacyOpen) | Should -BeFalse
            $text.Contains('Stale prose that must not survive the run.') | Should -BeFalse
            $text.Contains('<!-- PfbContext (generated; do not edit) -->') | Should -BeTrue
        }
    }
}
