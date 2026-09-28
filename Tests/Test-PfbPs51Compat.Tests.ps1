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
