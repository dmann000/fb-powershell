#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
    Gated to PS7 for consistency with every other tooling test in this suite. The
    file-level BeforeAll guards its OWN body as well: a skipped Describe does not stop a
    file-level BeforeAll, and dot-sourcing a 7-only script under 5.1 kills the whole
    container rather than one test. That mistake has cost this repo 65 tests before --
    see the header of Tests/CommittedDriftReport.Tests.ps1.
#>

BeforeAll {
    $script:isPwsh7 = $PSVersionTable.PSVersion.Major -ge 7
    if ($script:isPwsh7) {
        $script:repoRoot = Split-Path -Parent $PSScriptRoot
        $script:rewriter = Join-Path $script:repoRoot 'tools/Update-PfbTestModuleImport.ps1'
    }
}

Describe 'Update-PfbTestModuleImport rewrites each known form' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
    BeforeEach {
        $script:sandbox = Join-Path $TestDrive ((New-Guid).Guid)
        $null = New-Item -ItemType Directory -Path $script:sandbox -Force
    }

    It 'replaces only the import statement and keeps the surrounding assignments' {
        $path = Join-Path $script:sandbox 'A.Tests.ps1'
        $original = "BeforeAll {`n" +
            "    `$moduleRoot = Split-Path -Parent `$PSScriptRoot`n" +
            "    `$manifest   = Join-Path `$moduleRoot 'PureStorageFlashBladePowerShell.psd1'`n" +
            "    Import-Module `$manifest -Force`n" +
            "}`n"
        [System.IO.File]::WriteAllText($path, $original)

        $summary = & $script:rewriter -TestRoot $script:sandbox
        $summary.Changed.Count | Should -Be 1

        $updated = [System.IO.File]::ReadAllText($path)
        $updated | Should -Match '\$moduleRoot = Split-Path'
        $updated | Should -Match "\`$manifest   = Join-Path"
        $updated | Should -Not -Match 'Import-Module \$manifest -Force'
        $updated | Should -Match "    \. \(Join-Path \`$PSScriptRoot 'PfbTestModule\.ps1'\)"
        $updated | Should -Match '    \$null = Import-PfbTestModule'
    }

    It 'preserves the -PassThru assignment target and its indentation' {
        $path = Join-Path $script:sandbox 'B.Tests.ps1'
        $original = "BeforeAll {`n    if (`$script:isPwsh7) {`n" +
            "        `$script:module = Import-Module (Join-Path `$script:repoRoot 'PureStorageFlashBladePowerShell.psd1') -Force -PassThru`n" +
            "    }`n}`n"
        [System.IO.File]::WriteAllText($path, $original)

        $null = & $script:rewriter -TestRoot $script:sandbox
        $updated = [System.IO.File]::ReadAllText($path)
        $updated | Should -Match "        \. \(Join-Path \`$PSScriptRoot 'PfbTestModule\.ps1'\)"
        $updated | Should -Match '        \$script:module = Import-PfbTestModule'
    }

    It 'does not touch the separate-runspace AddCommand call' {
        $path = Join-Path $script:sandbox 'C.Tests.ps1'
        $original = "BeforeAll {`n" +
            "    `$null = `$ps.AddCommand('Import-Module').AddParameter('Name', `$Manifest).AddParameter('Force', `$true)`n}`n"
        [System.IO.File]::WriteAllText($path, $original)

        $summary = & $script:rewriter -TestRoot $script:sandbox
        $summary.Changed.Count | Should -Be 0
        [System.IO.File]::ReadAllText($path) | Should -Be $original
    }

    It 'does not touch Import-Module passed as an argument to Mock' {
        $path = Join-Path $script:sandbox 'D.Tests.ps1'
        $original = "BeforeAll {`n" +
            "    Mock -ModuleName PureStorageFlashBladePowerShell Import-Module { } -ParameterFilter { `$Name -eq 'Posh-SSH' }`n}`n"
        [System.IO.File]::WriteAllText($path, $original)

        $summary = & $script:rewriter -TestRoot $script:sandbox
        $summary.Changed.Count | Should -Be 0
        [System.IO.File]::ReadAllText($path) | Should -Be $original
    }

    It 'reports an unknown spelling in Unrecognised and warns, rather than skipping it silently' {
        $path = Join-Path $script:sandbox 'E.Tests.ps1'
        $original = "BeforeAll {`n" +
            "    Import-Module (Resolve-Path './PureStorageFlashBladePowerShell.psd1') -Force`n}`n"
        [System.IO.File]::WriteAllText($path, $original)

        $summary = & $script:rewriter -TestRoot $script:sandbox -WarningAction SilentlyContinue
        $summary.Unrecognised.Count | Should -Be 1
        $summary.Changed.Count | Should -Be 0
        # An Unrecognised-only file is still a file: it must land in a summary bucket, or the
        # census cannot be reconciled against the file count.
        $summary.Unchanged | Should -Be 1
        [System.IO.File]::ReadAllText($path) | Should -Be $original
    }

    It 'is idempotent: a second run reports zero changes' {
        $path = Join-Path $script:sandbox 'F.Tests.ps1'
        [System.IO.File]::WriteAllText($path, "BeforeAll {`n    Import-Module `$manifest -Force`n}`n")
        $null = & $script:rewriter -TestRoot $script:sandbox
        (& $script:rewriter -TestRoot $script:sandbox).Changed | Should -BeNullOrEmpty
    }

    It '-WhatIf reports the change without writing' {
        $path = Join-Path $script:sandbox 'G.Tests.ps1'
        $original = "BeforeAll {`n    Import-Module `$manifest -Force`n}`n"
        [System.IO.File]::WriteAllText($path, $original)
        (& $script:rewriter -TestRoot $script:sandbox -WhatIf).Changed.Count | Should -Be 1
        [System.IO.File]::ReadAllText($path) | Should -Be $original
    }

    It 'preserves <Name> line endings and stays idempotent under them' -ForEach @(
        @{ Name = 'LF';   Newline = "`n" }
        @{ Name = 'CRLF'; Newline = "`r`n" }
    ) {
        $path = Join-Path $script:sandbox "H-$Name.Tests.ps1"
        $lines = @('BeforeAll {', '    Import-Module $manifest -Force', '}')
        [System.IO.File]::WriteAllText($path, ($lines -join $Newline) + $Newline)

        $null = & $script:rewriter -TestRoot $script:sandbox
        $updated = [System.IO.File]::ReadAllText($path)
        if ($Newline -eq "`n") {
            $updated | Should -Not -Match "`r"
        }
        else {
            ([regex]::Matches($updated, "`r`n")).Count | Should -Be 4
            $updated | Should -Not -Match "(?<!`r)`n"
        }
        (& $script:rewriter -TestRoot $script:sandbox).Changed | Should -BeNullOrEmpty
    }

    It 'rewrites the <Name> call-site form to exactly the expected two lines' -ForEach @(
        @{ Name = 'Manifest'; Target = '$null'
            Statement = '    Import-Module $manifest -Force' }
        @{ Name = 'ScriptManifest'; Target = '$null'
            Statement = '    Import-Module $script:manifest -Force' }
        @{ Name = 'PSScriptRoot'; Target = '$null'
            Statement = '    Import-Module "$PSScriptRoot/../PureStorageFlashBladePowerShell.psd1" -Force' }
        @{ Name = 'JoinPath'; Target = '$null'
            Statement = "    Import-Module (Join-Path `$moduleRoot 'PureStorageFlashBladePowerShell.psd1') -Force" }
        @{ Name = 'PassThru'; Target = '$script:module'
            Statement = "    `$script:module = Import-Module `$manifest -Force -PassThru" }
        # The only form whose extent spans two physical lines (a backtick continuation), so
        # the only one where the head/tail arithmetic is non-trivial. Two lines in, two out.
        @{ Name = 'NestedJoinPath'; Target = '$null'
            Statement = "    Import-Module (Join-Path (Split-Path -Parent `$PSScriptRoot) ``" + "`n" +
                "            'PureStorageFlashBladePowerShell.psd1') -Force" }
    ) {
        $path = Join-Path $script:sandbox "$Name.Tests.ps1"
        [System.IO.File]::WriteAllText($path, "BeforeAll {`n$Statement`n}`n")

        $summary = & $script:rewriter -TestRoot $script:sandbox
        $summary.Changed.Count | Should -Be 1
        [System.IO.File]::ReadAllText($path) | Should -Be (
            "BeforeAll {`n" +
            "    . (Join-Path `$PSScriptRoot 'PfbTestModule.ps1')`n" +
            "    $Target = Import-PfbTestModule`n" +
            "}`n")
    }

    It 'never examines a file on the exclusion list, and reports it in Excluded' {
        # Tests/PfbTestModule.Tests.ps1:126 force-imports the manifest ON PURPOSE, to install
        # an unmarked module instance for the helper to notice. Rewriting it deletes the
        # condition under test, so the rewriter must not even look at the file.
        $path = Join-Path $script:sandbox 'PfbTestModule.Tests.ps1'
        $original = "BeforeAll {`n        `$null = Import-Module -Name `$script:manifest -Force -PassThru`n}`n"
        [System.IO.File]::WriteAllText($path, $original)

        $summary = & $script:rewriter -TestRoot $script:sandbox
        $summary.Changed.Count | Should -Be 0
        $summary.Excluded.Count | Should -Be 1
        $summary.Excluded[0] | Should -BeLike '*PfbTestModule.Tests.ps1'
        [System.IO.File]::ReadAllText($path) | Should -Be $original
    }

    It 'Changed + Unchanged + Excluded accounts for every test file examined' {
        [System.IO.File]::WriteAllText((Join-Path $script:sandbox 'J1.Tests.ps1'),
            "BeforeAll {`n    Import-Module `$manifest -Force`n}`n")
        [System.IO.File]::WriteAllText((Join-Path $script:sandbox 'J2.Tests.ps1'),
            "BeforeAll {`n    . (Join-Path `$PSScriptRoot 'PfbTestModule.ps1')`n    `$null = Import-PfbTestModule`n}`n")
        [System.IO.File]::WriteAllText((Join-Path $script:sandbox 'PfbTestModule.Tests.ps1'),
            "BeforeAll {`n    Import-Module `$manifest -Force`n}`n")

        $summary = & $script:rewriter -TestRoot $script:sandbox
        $summary.Changed.Count | Should -Be 1
        $summary.Unchanged | Should -Be 1
        $summary.Excluded.Count | Should -Be 1
        ($summary.Changed.Count + $summary.Unchanged + $summary.Excluded.Count) |
            Should -Be @(Get-ChildItem -Path $script:sandbox -Filter '*.Tests.ps1' -File -Recurse).Count
    }

    It 'keeps the real assignment target and any statement earlier on the same line' {
        # Hardcoding $script:module silently RENAMES the target (a throw under StrictMode);
        # moving the splice left edge back to the indentation silently DELETES the sentinel.
        $path = Join-Path $script:sandbox 'K.Tests.ps1'
        [System.IO.File]::WriteAllText($path,
            "BeforeAll {`n    `$script:sentinel = 42; `$myOwnName = Import-Module `$manifest -Force -PassThru`n}`n")

        $null = & $script:rewriter -TestRoot $script:sandbox
        [System.IO.File]::ReadAllText($path) | Should -Be (
            "BeforeAll {`n" +
            "    `$script:sentinel = 42; . (Join-Path `$PSScriptRoot 'PfbTestModule.ps1')`n" +
            "    `$myOwnName = Import-PfbTestModule`n" +
            "}`n")
    }

    It 'does not emit a dot-source as the right-hand side of an existing assignment' {
        # `$null = . (Join-Path ...)` parses, so no parse check catches it -- assert the shape.
        $path = Join-Path $script:sandbox 'L.Tests.ps1'
        [System.IO.File]::WriteAllText($path, "BeforeAll {`n    `$null = Import-Module `$manifest -Force`n}`n")

        $null = & $script:rewriter -TestRoot $script:sandbox
        [System.IO.File]::ReadAllText($path) | Should -Be (
            "BeforeAll {`n" +
            "    . (Join-Path `$PSScriptRoot 'PfbTestModule.ps1')`n" +
            "    `$null = Import-PfbTestModule`n" +
            "}`n")
    }

    It 'preserves a trailing comment and a tab indent' {
        $path = Join-Path $script:sandbox 'M.Tests.ps1'
        [System.IO.File]::WriteAllText($path,
            "BeforeAll {`n`t`tImport-Module `$manifest -Force  # keep me: issue #999`n}`n")

        $null = & $script:rewriter -TestRoot $script:sandbox
        [System.IO.File]::ReadAllText($path) | Should -Be (
            "BeforeAll {`n" +
            "`t`t. (Join-Path `$PSScriptRoot 'PfbTestModule.ps1')`n" +
            "`t`t`$null = Import-PfbTestModule  # keep me: issue #999`n" +
            "}`n")
    }

    It 'recovers the indent and the newline from the local line in a mixed-ending file' {
        # LastIndexOf($nl, ...) skips lines ended with the other convention and recovers the
        # indent of the wrong line -- an 8-space indent collapses to 4.
        $path = Join-Path $script:sandbox 'N.Tests.ps1'
        [System.IO.File]::WriteAllText($path,
            "BeforeAll {`r`n    if (`$true) {`n        Import-Module `$manifest -Force`n    }`r`n}`r`n")

        $null = & $script:rewriter -TestRoot $script:sandbox
        [System.IO.File]::ReadAllText($path) | Should -Be (
            "BeforeAll {`r`n" +
            "    if (`$true) {`n" +
            "        . (Join-Path `$PSScriptRoot 'PfbTestModule.ps1')`n" +
            "        `$null = Import-PfbTestModule`n" +
            "    }`r`n}`r`n")
    }

    It 'rewrites every import in a file that carries more than one' {
        $path = Join-Path $script:sandbox 'O.Tests.ps1'
        [System.IO.File]::WriteAllText($path,
            "BeforeAll {`n    Import-Module `$manifest -Force`n}`nDescribe 'x' {`n    BeforeAll {`n        Import-Module `$script:manifest -Force`n    }`n}`n")

        $null = & $script:rewriter -TestRoot $script:sandbox
        $updated = [System.IO.File]::ReadAllText($path)
        ([regex]::Matches($updated, [regex]::Escape('Import-PfbTestModule'))).Count | Should -Be 2
        $updated | Should -Not -Match 'Import-Module'
        $updated | Should -Match "    \. \(Join-Path \`$PSScriptRoot 'PfbTestModule\.ps1'\)"
        $updated | Should -Match "        \. \(Join-Path \`$PSScriptRoot 'PfbTestModule\.ps1'\)"
    }

    It 'reports an import in an unmodelled syntactic position as Unrecognised' {
        $path = Join-Path $script:sandbox 'P.Tests.ps1'
        $original = "BeforeAll {`n    Import-Module `$manifest -Force | Out-Null`n}`n"
        [System.IO.File]::WriteAllText($path, $original)

        $summary = & $script:rewriter -TestRoot $script:sandbox -WarningAction SilentlyContinue
        $summary.Changed.Count | Should -Be 0
        $summary.Unrecognised.Count | Should -Be 1
        [System.IO.File]::ReadAllText($path) | Should -Be $original
    }

    It 'finds a test file in a subfolder, because Pester Run.Path is recursive' {
        $nested = Join-Path $script:sandbox 'Nested'
        $null = New-Item -ItemType Directory -Path $nested -Force
        [System.IO.File]::WriteAllText((Join-Path $nested 'Q.Tests.ps1'),
            "BeforeAll {`n    Import-Module `$manifest -Force`n}`n")

        (& $script:rewriter -TestRoot $script:sandbox).Changed.Count | Should -Be 1
    }

    It 'splices character offsets, not byte offsets, with multi-byte text ahead of the import' {
        # 14 bytes of char/byte divergence BEFORE the import: an em dash, an e-acute, a CJK
        # ideograph and an astral emoji (surrogate pair). Byte-indexing corrupts both sides.
        $path = Join-Path $script:sandbox 'R.Tests.ps1'
        $prose = "# tests $([char]0x2014) caf$([char]0xE9) $([char]0x4E2D) $([char]::ConvertFromUtf32(0x1F600))"
        [System.IO.File]::WriteAllText($path,
            "$prose`nBeforeAll {`n    Import-Module `$manifest -Force`n}`n",
            (New-Object System.Text.UTF8Encoding($false)))

        $null = & $script:rewriter -TestRoot $script:sandbox
        [System.IO.File]::ReadAllText($path) | Should -Be (
            "$prose`n" +
            "BeforeAll {`n" +
            "    . (Join-Path `$PSScriptRoot 'PfbTestModule.ps1')`n" +
            "    `$null = Import-PfbTestModule`n" +
            "}`n")
    }

    It 'preserves a semicolon-joined statement that FOLLOWS the import' {
        # The mirror of K.Tests.ps1. Nothing outside the replaced node's extent may move, so
        # a following statement has to survive verbatim on the second emitted line.
        $path = Join-Path $script:sandbox 'S.Tests.ps1'
        [System.IO.File]::WriteAllText($path,
            "BeforeAll {`n    Import-Module `$manifest -Force; `$script:after = 7`n}`n")

        $null = & $script:rewriter -TestRoot $script:sandbox
        [System.IO.File]::ReadAllText($path) | Should -Be (
            "BeforeAll {`n" +
            "    . (Join-Path `$PSScriptRoot 'PfbTestModule.ps1')`n" +
            "    `$null = Import-PfbTestModule; `$script:after = 7`n" +
            "}`n")
    }

    It 'reports <Name> as Unrecognised and leaves the file byte-identical' -ForEach @(
        # The replaced node is not itself in statement position. Splicing two statements over
        # its extent either fails to parse (the `if` condition) or parses while silently
        # emptying the caller's variable (the other three) -- the failure class Unrecognised
        # exists to prevent. Zero sites in the real tree; the guard is what keeps it that way.
        @{ Name = 'AssignmentInIfCondition'
            Statement = "    if (`$m = Import-Module `$manifest -Force -PassThru) { }" }
        @{ Name = 'ChainedAssignment'
            Statement = "    `$a = `$b = Import-Module `$manifest -Force -PassThru" }
        @{ Name = 'SubExpressionBody'
            Statement = "    `$m = `$(Import-Module `$manifest -Force -PassThru)" }
        @{ Name = 'ArrayExpressionBody'
            Statement = "    `$m = @(Import-Module `$manifest -Force -PassThru)" }
        # Import-PfbTestModule cannot honour these, and emitting the helper call anyway would
        # drop them with nothing on screen to say so. Reject instead of rewriting.
        @{ Name = 'ExtraParameterErrorAction'
            Statement = "    Import-Module `$manifest -Force -ErrorAction Stop" }
        @{ Name = 'ExtraParameterGlobal'
            Statement = "    `$m = Import-Module `$manifest -Force -PassThru -Global" }
    ) {
        $path = Join-Path $script:sandbox "$Name.Tests.ps1"
        $original = "BeforeAll {`n$Statement`n}`n"
        [System.IO.File]::WriteAllText($path, $original)

        $summary = & $script:rewriter -TestRoot $script:sandbox -WarningAction SilentlyContinue
        $summary.Changed.Count | Should -Be 0
        $summary.Unrecognised.Count | Should -Be 1
        $summary.Unchanged | Should -Be 1
        [System.IO.File]::ReadAllText($path) | Should -Be $original
    }

    It 'never emits -Fresh or a PfbTestModulePrepared assignment' {
        $source = [System.IO.File]::ReadAllText($script:rewriter)
        $source.Contains('PfbTestModulePrepared') | Should -BeFalse
        $source.Contains('-Fresh') | Should -BeFalse
    }
}
