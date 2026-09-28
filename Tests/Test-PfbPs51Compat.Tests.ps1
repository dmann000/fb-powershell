#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    tools/Test-PfbPs51Compat.ps1: the Windows PowerShell 5.1 compatibility check.
.DESCRIPTION
    Runs ONLY under Windows PowerShell 5.1 (-Skip:($PSVersionTable.PSEdition -ne 'Desktop')),
    because the class-1 verdict IS the 5.1 parser's answer. So winps51 pins 0 skips and every
    pwsh 7 leg pins the same N. The skip gates on the edition, not on whether powershell.exe
    exists: one pwsh7 skip map serves ubuntu, windows and macos, and a count that varied by
    OS could not be pinned.

    The fixtures are .txt, not .ps1, on purpose: a class-1 sample under Tests/ would break
    the analyzer's PSUseCompatibleSyntax gate and this script's own -All run.
#>

BeforeDiscovery {
    # $script:, as in this repo's other BeforeDiscovery blocks: a plain local read only by a
    # later -ForEach is "assigned but never used" to PSUseDeclaredVarsMoreThanAssignments,
    # which the analyze job gates at zero.
    $fixtureDir = Join-Path (Join-Path $PSScriptRoot 'Fixtures') 'Ps51Compat'
    $manifest = Import-PowerShellDataFile (Join-Path $fixtureDir 'Cases.psd1')
    $script:cases = @($manifest.Cases | ForEach-Object { $_ })
}

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:fixtureDir = Join-Path (Join-Path $PSScriptRoot 'Fixtures') 'Ps51Compat'
    $script:manifest = Import-PowerShellDataFile (Join-Path $script:fixtureDir 'Cases.psd1')
    $script:compat = Join-Path (Join-Path $script:repoRoot 'tools') 'Test-PfbPs51Compat.ps1'
}

Describe 'Ps51Compat fixture table covers the hook it replaces' -Skip:($PSVersionTable.PSEdition -ne 'Desktop') {
    It 'has a case for every hook construct' {
        $covered = @($script:manifest.Cases | ForEach-Object { $_.Construct; $_.Suppression }) | Sort-Object -Unique
        @($script:manifest.HookConstructs | Where-Object { $covered -notcontains $_ }) -join ', ' | Should -BeNullOrEmpty
    }
    It 'every case has both samples on disk' {
        $missing = foreach ($c in $script:manifest.Cases) {
            foreach ($f in $c.FlagsFile, $c.SuppressedFile) { if (-not (Test-Path -LiteralPath (Join-Path $script:fixtureDir $f))) { "$($c.Id): $f" } }
        }
        @($missing) -join ', ' | Should -BeNullOrEmpty
    }
    It 'the script declares exactly the rules the table exercises' {
        $rules = @(& $script:compat -ListRules | ForEach-Object Id) | Sort-Object -Unique
        $want = @($script:manifest.Cases | ForEach-Object Rule | Where-Object { $_ }) | Sort-Object -Unique
        ($rules -join ',') | Should -BeExactly ($want -join ',')
    }
}

Describe 'Test-PfbPs51Compat scope and class 1' -Skip:($PSVersionTable.PSEdition -ne 'Desktop') {
    BeforeAll {
        function New-TestFakeRepo {
            # Shaped like a PR worktree -- the path shape the old hook marker missed.
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Test helper writing a fake repo under $TestDrive; nothing to confirm.')]
            param()
            $root = Join-Path (Join-Path (Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))) 'worktrees') 'pr-x'
            $null = New-Item -ItemType Directory -Path $root -Force
            [System.IO.File]::WriteAllText((Join-Path $root 'PureStorageFlashBladePowerShell.psd1'), "@{ ModuleVersion = '0.0.1' }`n")
            return $root
        }
        function Set-TestSample {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Test helper writing one sample file under $TestDrive; nothing to confirm.')]
            param([string]$Root, [string]$RelativePath, [string]$Text)
            $full = Join-Path $Root $RelativePath
            $dir = Split-Path -Parent $full
            if (-not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
            [System.IO.File]::WriteAllText($full, $Text)
            return $full
        }
    }
    It 'flags a ternary in a worktree Tests/ file as class 1, with a repo-relative path' {
        $root = New-TestFakeRepo
        $f = Set-TestSample $root 'Tests/A.Tests.ps1' "`$v = (1 -eq 1) ? 'a' : 'b'`n"
        $out = @(& $script:compat -Path $f 6>$null)
        $LASTEXITCODE | Should -Be 1
        $out.Count | Should -BeGreaterThan 0
        $out[0].Class | Should -Be 1
        $out[0].Path | Should -BeExactly 'Tests/A.Tests.ps1'
        $out[0].Line | Should -Be 1
        $out[0].Severity | Should -BeExactly 'error'
    }
    It 'ignores a ternary in an undeclared tools/ file' {
        $root = New-TestFakeRepo
        @(& $script:compat -Path (Set-TestSample $root 'tools/A.ps1' "`$v = `$c ? 1 : 2`n") 6>$null).Count | Should -Be 0
        $LASTEXITCODE | Should -Be 0
    }
    It 'ignores a #Requires -Version 7 file entirely' {
        $root = New-TestFakeRepo
        @(& $script:compat -Path (Set-TestSample $root 'Tests/B.Tests.ps1' "#Requires -Version 7.0`n`$v = `$c ? 1 : 2`n") 6>$null).Count | Should -Be 0
    }
    It 'gives no findings for a file under no manifest' {
        $f = Join-Path $TestDrive 'loose.ps1'
        [System.IO.File]::WriteAllText($f, "`$v = `$c ? 1 : 2`n")
        @(& $script:compat -Path $f 6>$null).Count | Should -Be 0
        $LASTEXITCODE | Should -Be 0
    }
    It 'reports any other 5.1 parse error as class 1 too' {
        $root = New-TestFakeRepo
        @(& $script:compat -Path (Set-TestSample $root 'Public/A.ps1' "function f { if (`$true) { 1 }`n") 6>$null | Where-Object Class -eq 1).Count | Should -BeGreaterThan 0
    }
    It 'refuses to run under PowerShell 7, since its verdict would be the wrong parser''s (exit 2)' {
        $root = New-TestFakeRepo
        $f = Set-TestSample $root 'Tests/C.Tests.ps1' "'ok'`n"
        & pwsh -NoProfile -NonInteractive -File $script:compat -Path $f *> $null
        $LASTEXITCODE | Should -Be 2
    }
}
