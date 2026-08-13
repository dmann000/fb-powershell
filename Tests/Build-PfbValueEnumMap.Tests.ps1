#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Integration tests for tools/Build-PfbValueEnumMap.ps1 against small synthetic spec
    fixtures (no dependency on the real cached specs in tools/specs/), plus a shape/
    regression check of the real committed manifest when present.
.DESCRIPTION
    Every invocation below passes explicit -OutputPath AND -ReconciliationPath under
    TestDrive: — never let the script fall back to its real-repo defaults, or running
    these tests would overwrite Reports/PfbValueEnumMap.json and
    Reports/PfbValueEnumReconciliation.md as a side effect.
#>

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $script:builderScript = Join-Path $repoRoot 'tools/Build-PfbValueEnumMap.ps1'
}

Describe 'Build-PfbValueEnumMap: introduced-in diffing and value tracking' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
    BeforeAll {
        New-Item -ItemType Directory -Path 'TestDrive:\specs' -Force | Out-Null

        # v9.0: Widget.color has a two-value enum; a squash-mode-style pair of schemas
        # (WidgetA/WidgetB) share a property name with different value lists.
        $specV1 = [ordered]@{
            openapi    = '3.0.1'
            info       = @{ version = '9.0' }
            paths      = [ordered]@{}
            components = [ordered]@{
                schemas    = [ordered]@{
                    Widget  = [ordered]@{
                        type       = 'object'
                        properties = [ordered]@{
                            color = @{ type = 'string'; description = 'The widget color. Valid values are `red`, `blue`.' }
                        }
                    }
                    WidgetA = [ordered]@{
                        type       = 'object'
                        properties = [ordered]@{
                            mode = @{ type = 'string'; description = 'Valid values are `on`, `off`.' }
                        }
                    }
                    WidgetB = [ordered]@{
                        type       = 'object'
                        properties = [ordered]@{
                            mode = @{ type = 'string'; description = 'Valid values are `enabled`, `disabled`.' }
                        }
                    }
                }
                parameters = [ordered]@{}
            }
        }

        # v9.1: Widget.color gains a third value (green); a brand-new Gadget.kind enum
        # appears; a numeric-range description that matches the trigger phrase but is
        # not a real enum is introduced (must land in "unparsed", not silently dropped).
        $specV2 = [ordered]@{
            openapi    = '3.0.1'
            info       = @{ version = '9.1' }
            paths      = [ordered]@{}
            components = [ordered]@{
                schemas    = [ordered]@{
                    Widget  = [ordered]@{
                        type       = 'object'
                        properties = [ordered]@{
                            color = @{ type = 'string'; description = 'The widget color. Valid values are `red`, `blue`, and `green`.' }
                        }
                    }
                    WidgetA = [ordered]@{
                        type       = 'object'
                        properties = [ordered]@{
                            mode = @{ type = 'string'; description = 'Valid values are `on`, `off`.' }
                        }
                    }
                    WidgetB = [ordered]@{
                        type       = 'object'
                        properties = [ordered]@{
                            mode = @{ type = 'string'; description = 'Valid values are `enabled`, `disabled`.' }
                        }
                    }
                    Gadget  = [ordered]@{
                        type       = 'object'
                        properties = [ordered]@{
                            kind    = @{ type = 'string'; description = 'Valid values are `small`, `large`.' }
                            timeout = @{ type = 'integer'; description = "Valid values are`nin the range of 1000 and 60000." }
                        }
                    }
                }
                parameters = [ordered]@{}
            }
        }

        $specV1 | ConvertTo-Json -Depth 20 | Set-Content -Path 'TestDrive:\specs\fb9.0.json'
        $specV2 | ConvertTo-Json -Depth 20 | Set-Content -Path 'TestDrive:\specs\fb9.1.json'

        & $builderScript -SpecsDirectory 'TestDrive:\specs' -OutputPath 'TestDrive:\output\map.json' -ReconciliationPath 'TestDrive:\output\reconciliation.md'
        $script:manifest = Get-Content -Path 'TestDrive:\output\map.json' -Raw | ConvertFrom-Json -Depth 20
    }

    It 'records generatedFrom in ascending version order' {
        $manifest.generatedFrom | Should -Be @('9.0', '9.1')
    }

    It 'attributes an entry present since the earliest version to that version, but reports the newest values' {
        $manifest.entries.'Widget.color'.minVersion | Should -Be '9.0'
        $manifest.entries.'Widget.color'.values | Should -Be @('red', 'blue', 'green')
    }

    It 'attributes a brand-new entry to the version it first appears in' {
        $manifest.entries.'Gadget.kind'.minVersion | Should -Be '9.1'
        $manifest.entries.'Gadget.kind'.values | Should -Be @('small', 'large')
    }

    It 'never collapses two schemas sharing a property name into one entry (squash-mode gotcha)' {
        $manifest.entries.'WidgetA.mode'.values | Should -Be @('on', 'off')
        $manifest.entries.'WidgetB.mode'.values | Should -Be @('enabled', 'disabled')
    }

    It 'tracks a trigger-matching but non-enumerable description as unparsed rather than dropping it' {
        $manifest.unparsedCount | Should -BeGreaterThan 0
        $unparsedKeys = $manifest.unparsed | ForEach-Object { $_.key }
        $unparsedKeys | Should -Contain 'Gadget.timeout'
    }

    It 'reports entryCount matching the actual number of entries' {
        $manifest.entryCount | Should -Be $manifest.entries.PSObject.Properties.Name.Count
    }

    It 'reports unparsedCount matching the actual number of unparsed records' {
        $manifest.unparsedCount | Should -Be @($manifest.unparsed).Count
    }
}

Describe 'Build-PfbValueEnumMap: manifest shape' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
    BeforeAll {
        New-Item -ItemType Directory -Path 'TestDrive:\shapeSpecs' -Force | Out-Null
        $spec = [ordered]@{
            openapi    = '3.0.1'
            info       = @{ version = '9.0' }
            paths      = [ordered]@{}
            components = [ordered]@{
                schemas    = [ordered]@{
                    Widget = [ordered]@{
                        type       = 'object'
                        properties = [ordered]@{
                            color = @{ type = 'string'; description = 'Valid values are `red`, `blue`.' }
                        }
                    }
                }
                parameters = [ordered]@{}
            }
        }
        $spec | ConvertTo-Json -Depth 20 | Set-Content -Path 'TestDrive:\shapeSpecs\fb9.0.json'

        & $builderScript -SpecsDirectory 'TestDrive:\shapeSpecs' -OutputPath 'TestDrive:\shapeOutput\map.json' -ReconciliationPath 'TestDrive:\shapeOutput\reconciliation.md'
        $script:shapeManifest = Get-Content -Path 'TestDrive:\shapeOutput\map.json' -Raw | ConvertFrom-Json -Depth 20
    }

    It 'has the required top-level keys' {
        $shapeManifest.PSObject.Properties.Name | Should -Contain 'schemaVersion'
        $shapeManifest.PSObject.Properties.Name | Should -Contain 'generatedFrom'
        $shapeManifest.PSObject.Properties.Name | Should -Contain 'entryCount'
        $shapeManifest.PSObject.Properties.Name | Should -Contain 'unparsedCount'
        $shapeManifest.PSObject.Properties.Name | Should -Contain 'entries'
        $shapeManifest.PSObject.Properties.Name | Should -Contain 'unparsed'
    }

    It 'writes a reconciliation report file' {
        Test-Path 'TestDrive:\shapeOutput\reconciliation.md' | Should -BeTrue
        (Get-Content 'TestDrive:\shapeOutput\reconciliation.md' -Raw) | Should -Match 'Value-Enum Reconciliation Report'
    }

    It 'throws a clear error when no cached specs are present' {
        New-Item -ItemType Directory -Path 'TestDrive:\emptySpecs' -Force | Out-Null
        { & $builderScript -SpecsDirectory 'TestDrive:\emptySpecs' -OutputPath 'TestDrive:\emptyOutput\map.json' -ReconciliationPath 'TestDrive:\emptyOutput\reconciliation.md' } |
            Should -Throw '*No cached specs found*'
    }
}

Describe 'Build-PfbValueEnumMap: hand-written ValidateSet citations' {
    # The $handWritten table in the generator is the ONLY source of the File:Line values the
    # reconciliation report publishes, and nothing else in the suite asserted them -- so a
    # record could cite the line of the preceding [Parameter()] attribute (or any other line)
    # and stay green. This block pins every record's Line to the first line of the
    # ValidateSet attribute actually attached to that record's Parameter, resolved from the
    # source file's AST rather than by text search. Runs on both editions: it only parses
    # committed .ps1 files and needs neither the spec cache nor the generated manifest.
    BeforeAll {
        $repoRoot = Split-Path -Parent $PSScriptRoot
        $script:enumRepoRoot = $repoRoot
        $builderPath = Join-Path $repoRoot 'tools/Build-PfbValueEnumMap.ps1'

        $tokens = $null
        $errors = $null
        $builderAst = [System.Management.Automation.Language.Parser]::ParseFile($builderPath, [ref]$tokens, [ref]$errors)
        if ($errors -and $errors.Count -gt 0) {
            throw "Failed to parse '$builderPath': $($errors[0].Message)"
        }

        $assignment = $builderAst.Find({
                param($node)
                $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
                $node.Left.VariablePath.UserPath -eq 'handWritten'
            }, $true)

        if (-not $assignment) {
            throw "Could not locate the `$handWritten assignment in '$builderPath'."
        }

        # The right-hand side is a literal array of [PSCustomObject]@{...} entries (no commands),
        # so evaluating just that extent is the faithful way to read the table without running
        # the generator (which requires PS 7 and a spec cache).
        $script:handWrittenRecords = @([scriptblock]::Create($assignment.Right.Extent.Text).Invoke())
    }

    It 'has at least one hand-written record to check' {
        $handWrittenRecords.Count | Should -BeGreaterThan 0
    }

    It 'cites the line of the ValidateSet attribute attached to each recorded Parameter' {
        $problems = [System.Collections.Generic.List[string]]::new()

        foreach ($record in $handWrittenRecords) {
            $sourcePath = Join-Path $enumRepoRoot $record.File
            if (-not (Test-Path $sourcePath)) {
                $problems.Add("$($record.File):$($record.Line) $($record.Parameter): source file does not exist")
                continue
            }

            $srcTokens = $null
            $srcErrors = $null
            $srcAst = [System.Management.Automation.Language.Parser]::ParseFile($sourcePath, [ref]$srcTokens, [ref]$srcErrors)
            if ($srcErrors -and $srcErrors.Count -gt 0) {
                $problems.Add("$($record.File): failed to parse ($($srcErrors[0].Message))")
                continue
            }

            $paramName = $record.Parameter.TrimStart('-')
            $paramAsts = @($srcAst.FindAll({
                        param($node)
                        $node -is [System.Management.Automation.Language.ParameterAst]
                    }, $true) | Where-Object { $_.Name.VariablePath.UserPath -eq $paramName })

            if ($paramAsts.Count -ne 1) {
                $problems.Add("$($record.File): expected exactly 1 parameter named '$paramName', found $($paramAsts.Count)")
                continue
            }

            $validateSets = @($paramAsts[0].Attributes | Where-Object { $_.TypeName.Name -eq 'ValidateSet' })
            if ($validateSets.Count -ne 1) {
                $problems.Add("$($record.File): parameter '$paramName' has $($validateSets.Count) ValidateSet attributes, expected 1")
                continue
            }

            $actualLine = $validateSets[0].Extent.StartLineNumber
            if ($record.Line -ne $actualLine) {
                $problems.Add("$($record.File): $($record.Parameter) cites line $($record.Line) but its ValidateSet is on line $actualLine")
            }
        }

        $problems -join ' | ' | Should -BeNullOrEmpty -Because 'every published File:Line must land on the ValidateSet being reconciled'
    }
}

Describe 'Real committed value-enum map (skips gracefully if not yet generated)' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
    BeforeAll {
        $repoRoot = Split-Path -Parent $PSScriptRoot
        $script:realManifestPath = Join-Path $repoRoot 'Reports/PfbValueEnumMap.json'
        $script:realSpecsDir = Join-Path $repoRoot 'tools/specs'
    }

    It 'Bucket.versioning regression: extracts exactly [none, enabled, suspended] with no per-value version claim' {
        if (-not (Test-Path $realManifestPath)) {
            Set-ItResult -Skipped -Because 'Reports/PfbValueEnumMap.json not present (run Build-PfbValueEnumMap.ps1 first)'
            return
        }

        $manifest = Get-Content -Path $realManifestPath -Raw | ConvertFrom-Json -Depth 20
        $manifest.entries.'Bucket.versioning' | Should -Not -BeNullOrEmpty
        $manifest.entries.'Bucket.versioning'.values | Should -Be @('none', 'enabled', 'suspended')
    }

    It 'never collapses NfsExportPolicyRuleBase.access and the presets-only variant into one entry (squash-mode gotcha)' {
        if (-not (Test-Path $realManifestPath)) {
            Set-ItResult -Skipped -Because 'Reports/PfbValueEnumMap.json not present (run Build-PfbValueEnumMap.ps1 first)'
            return
        }

        $manifest = Get-Content -Path $realManifestPath -Raw | ConvertFrom-Json -Depth 20
        $base = $manifest.entries.'NfsExportPolicyRuleBase.access'
        $preset = $manifest.entries.'_presetWorkloadExportConfigurationNfsRule.access'

        $base | Should -Not -BeNullOrEmpty
        $preset | Should -Not -BeNullOrEmpty
        $base.values | Should -Contain 'no-squash'
        $preset.values | Should -Contain 'no-root-squash'
        ($base.values -join ',') | Should -Not -Be ($preset.values -join ',')
    }

    It 'meets the acceptance-criteria entry-count floor and reports unparsedCount as a first-class field' {
        if (-not (Test-Path $realManifestPath)) {
            Set-ItResult -Skipped -Because 'Reports/PfbValueEnumMap.json not present (run Build-PfbValueEnumMap.ps1 first)'
            return
        }

        $manifest = Get-Content -Path $realManifestPath -Raw | ConvertFrom-Json -Depth 20
        $manifest.entryCount | Should -BeGreaterOrEqual 100
        $manifest.PSObject.Properties.Name | Should -Contain 'unparsedCount'
        @($manifest.unparsed).Count | Should -Be $manifest.unparsedCount
    }

    It 'every (schema, property) value-enum extractable from the newest cached spec is represented in the manifest' {
        if (-not (Test-Path $realManifestPath) -or -not (Test-Path $realSpecsDir)) {
            Set-ItResult -Skipped -Because 'Reports/PfbValueEnumMap.json or tools/specs/ not present (run Update-PfbApiSpecs.ps1 and Build-PfbValueEnumMap.ps1 first)'
            return
        }

        . (Join-Path $repoRoot 'tools/lib/PfbSpecTools.ps1')
        . (Join-Path $repoRoot 'tools/lib/PfbValueEnumTools.ps1')

        $specFiles = Get-ChildItem -Path $realSpecsDir -Filter 'fb*.json' | Where-Object { $_.BaseName -match '^fb(\d+)\.(\d+)$' }
        if (-not $specFiles) {
            Set-ItResult -Skipped -Because 'No cached spec files found under tools/specs/'
            return
        }
        $newest = $specFiles | ForEach-Object {
            $null = $_.BaseName -match '^fb(\d+)\.(\d+)$'
            [PSCustomObject]@{ File = $_; Major = [int]$Matches[1]; Minor = [int]$Matches[2] }
        } | Sort-Object Major, Minor | Select-Object -Last 1

        $spec = Get-Content -Path $newest.File.FullName -Raw | ConvertFrom-Json -Depth 64
        $valueEnums = Get-PfbSpecValueEnums -Spec $spec
        $manifest = Get-Content -Path $realManifestPath -Raw | ConvertFrom-Json -Depth 20
        $entryKeys = [System.Collections.Generic.HashSet[string]]::new([string[]]$manifest.entries.PSObject.Properties.Name)
        $unparsedKeys = [System.Collections.Generic.HashSet[string]]::new([string[]]($manifest.unparsed | ForEach-Object { $_.key }))

        $missing = $valueEnums | ForEach-Object { $_.Key } | Where-Object { -not $entryKeys.Contains($_) -and -not $unparsedKeys.Contains($_) }

        $missing | Should -BeNullOrEmpty -Because "these value enums exist in the newest spec but are represented in neither entries nor unparsed: $($missing -join ', ')"
    }
}
