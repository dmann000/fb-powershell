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
}
