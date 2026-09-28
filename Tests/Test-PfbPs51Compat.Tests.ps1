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
    It 'names only hook constructs in every case''s Construct and Suppression' {
        $known = @($script:manifest.HookConstructs)
        $unknown = foreach ($c in $script:manifest.Cases) {
            if (-not $c.Construct -or $known -notcontains $c.Construct) { "$($c.Id): Construct '$($c.Construct)'" }
            if ($c.Suppression -and $known -notcontains $c.Suppression) { "$($c.Id): Suppression '$($c.Suppression)'" }
        }
        @($unknown) -join ', ' | Should -BeNullOrEmpty
    }
    It 'gives every case a unique Id' {
        @($script:manifest.Cases | ForEach-Object { $_.Id } | Group-Object | Where-Object Count -gt 1 | ForEach-Object Name) -join ', ' | Should -BeNullOrEmpty
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
        $LASTEXITCODE | Should -Be 0
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
    Context 'when it cannot run' {
        # Exit 1 means class-1 findings, so a malfunction must never exit 1. Each It runs the
        # script in a child powershell.exe, as CI does, so the exit code is the process's own.
        It 'exits 2 for -All under a manifest that is not a git work tree' {
            $root = New-TestFakeRepo
            $savedCeiling = $env:GIT_CEILING_DIRECTORIES
            # Stops git searching above the fake repo, so the answer cannot depend on where
            # the test drive happens to live.
            $env:GIT_CEILING_DIRECTORIES = Split-Path -Parent $root
            try {
                & powershell.exe -NoProfile -NonInteractive -Command "Set-Location -LiteralPath '$root'; & '$($script:compat)' -All; exit `$LASTEXITCODE" *> $null
                $LASTEXITCODE | Should -Be 2
            } finally {
                $env:GIT_CEILING_DIRECTORIES = $savedCeiling
            }
        }
        It 'exits 2 for a -Path that does not exist' {
            $missing = Join-Path (New-TestFakeRepo) 'Public/Missing.ps1'
            & powershell.exe -NoProfile -NonInteractive -File $script:compat -Path $missing *> $null
            $LASTEXITCODE | Should -Be 2
        }
    }
}

Describe 'Test-PfbPs51Compat against every fixture case' -Skip:($PSVersionTable.PSEdition -ne 'Desktop') {
    BeforeAll {
        function New-TestCaseRepo {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Test helper materializing one fixture under $TestDrive; nothing to confirm.')]
            param([string]$RelativePath, [string]$SampleFile)
            $root = Join-Path (Join-Path (Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))) 'worktrees') 'pr-x'
            $null = New-Item -ItemType Directory -Path $root -Force
            [System.IO.File]::WriteAllText((Join-Path $root 'PureStorageFlashBladePowerShell.psd1'), "@{ ModuleVersion = '0.0.1' }`n")
            $full = Join-Path $root $RelativePath
            $dir = Split-Path -Parent $full
            if (-not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
            Copy-Item -LiteralPath (Join-Path $script:fixtureDir $SampleFile) -Destination $full
            return $full
        }
    }
    It '<Id>: the flags sample is reported under <Rule>' -ForEach $script:cases {
        $out = @(& $script:compat -Path (New-TestCaseRepo -RelativePath $FlagsPath -SampleFile $FlagsFile) 6>$null)
        @($out | Where-Object Rule -eq $Rule).Count | Should -BeGreaterThan 0 -Because ($out | Out-String)
    }
    It '<Id>: the suppressed sample is not reported under <Rule> (<Suppression>)' -ForEach $script:cases {
        $out = @(& $script:compat -Path (New-TestCaseRepo -RelativePath $SuppressedPath -SampleFile $SuppressedFile) 6>$null)
        # Exit 2 (could not run) also reports nothing, so rule it out before trusting the zero.
        $LASTEXITCODE | Should -Not -Be 2
        @($out | Where-Object Rule -eq $Rule).Count | Should -Be 0 -Because ($out | Out-String)
    }
}

Describe "Test-PfbPs51Compat on shapes outside the hook's fixture table" -Skip:($PSVersionTable.PSEdition -ne 'Desktop') {
    # Not hook constructs, so not in Cases.psd1: these pin where the script must NOT be laxer
    # than the hook (a string or comment never suppresses; a lookalike gate is not a gate) and
    # the AST shapes the script reports although the hook's line regexes cannot see them.
    # Samples sit under Public/, in class 2/3 scope with no #Requires line needed.
    BeforeAll {
        function New-TestInlineSample {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Test helper writing one sample under $TestDrive; nothing to confirm.')]
            param([string]$Text)
            $root = Join-Path (Join-Path (Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))) 'worktrees') 'pr-x'
            $null = New-Item -ItemType Directory -Path (Join-Path $root 'Public') -Force
            [System.IO.File]::WriteAllText((Join-Path $root 'PureStorageFlashBladePowerShell.psd1'), "@{ ModuleVersion = '0.0.1' }`n")
            $full = Join-Path (Join-Path $root 'Public') 'X.ps1'
            [System.IO.File]::WriteAllText($full, $Text)
            return $full
        }
    }
    It '<Id>: reported under <Rule> at line <Line>' -ForEach @(
        @{ Id = 'skip-guard-psversion-in-string'; Rule = 'c2-convertfrom-json-depth'; Line = 3; Text = @'
Describe 'x' -Skip:('PSVersion' -eq 'nope') {
    It 'y' {
        $null = '{}' | ConvertFrom-Json -Depth 5
    }
}
'@ }
        @{ Id = 'skip-guard-psversion-in-comment'; Rule = 'c2-convertfrom-json-depth'; Line = 3; Text = @'
Describe 'x' -Skip:(<# PSVersion #> $false) {
    It 'y' {
        $null = '{}' | ConvertFrom-Json -Depth 5
    }
}
'@ }
        @{ Id = 'skip-bare-switch-is-not-a-guard'; Rule = 'c2-convertfrom-json-depth'; Line = 3; Text = @'
Describe 'x' -Skip {
    It 'y' {
        $null = '{}' | ConvertFrom-Json -Depth 5
        $m = $PSVersionTable
    }
}
'@ }
        @{ Id = 'pragma-on-a-later-line-of-a-block-comment'; Rule = 'c2-convertfrom-json-depth'; Line = 1; Text = @'
$o = '{}' | ConvertFrom-Json -Depth 5 <#
# ps51-ok
#>
'@ }
        @{ Id = 'scope-qualified-psversiontable-is-not-a-gate'; Rule = 'c2-convertfrom-json-depth'; Line = 2; Text = @'
if ($script:PSVersionTable.PSVersion.Major -ge 6) {
    '{}' | ConvertFrom-Json -Depth 5
}
'@ }
        @{ Id = 'module-qualified-command'; Rule = 'c2-convertfrom-json-depth'; Line = 1; Text = "Microsoft.PowerShell.Utility\ConvertFrom-Json -Depth 5 -InputObject '{}'`n" }
        @{ Id = 'string-constant-command-name'; Rule = 'c2-convertfrom-json-depth'; Line = 1; Text = "& 'ConvertFrom-Json' '{}' -Depth 5`n" }
        @{ Id = 'encoding-colon-utf8nobom'; Rule = 'c2-encoding-utf8nobom'; Line = 1; Text = "Set-Content x -Encoding:utf8NoBOM`n" }
        @{ Id = 'encoding-colon-utf8'; Rule = 'c3-utf8-bom-write'; Line = 1; Text = "Set-Content x -Encoding:UTF8`n" }
        @{ Id = 'braced-iswindows'; Rule = 'c3-is-platform-variable'; Line = 1; Text = "if (`${IsWindows}) { 1 }`n" }
        @{ Id = 'braced-psstyle'; Rule = 'c2-psstyle'; Line = 1; Text = "`${PSStyle}.Reset`n" }
        @{ Id = 'parameter-after-paren-continuation'; Rule = 'c2-convertfrom-json-depth'; Line = 1; Text = @'
ConvertFrom-Json -InputObject (
    '{}'
) -Depth 5
'@ }
        @{ Id = 'parameter-after-backtick-continuation'; Rule = 'c2-convertfrom-json-depth'; Line = 1; Text = @'
'{}' | ConvertFrom-Json `
    -Depth 5
'@ }
    ) {
        $out = @(& $script:compat -Path (New-TestInlineSample -Text $Text) 6>$null)
        @($out | Where-Object { $_.Rule -eq $Rule -and $_.Line -eq $Line }).Count | Should -BeGreaterThan 0 -Because ($out | Out-String)
    }
    It '<Id>: not reported under <Rule>' -ForEach @(
        @{ Id = 'pragma-on-an-inner-block-comment-line-in-the-window'; Rule = 'c2-convertfrom-json-depth'; Text = @'
<#
 a
 b
 c
 d
 e
 f
 g
 # ps51-ok
#>
'{}' | ConvertFrom-Json -Depth 5
'@ }
        @{ Id = 'skip-guard-on-the-fourth-line-of-a-wrapped-opener'; Rule = 'c2-convertfrom-json-depth'; Text = @'
Describe 'x' `
    -Tag 'a' `
    -AllowNullOrEmptyForEach `
    -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
    It 'y' {
        # filler: keeps the finding more than 6 lines below the guard's line
        # filler
        # filler
        # filler
        # filler
        # filler
        $null = '{}' | ConvertFrom-Json -Depth 5
    }
}
'@ }
    ) {
        $out = @(& $script:compat -Path (New-TestInlineSample -Text $Text) 6>$null)
        $LASTEXITCODE | Should -Not -Be 2
        @($out | Where-Object Rule -eq $Rule).Count | Should -Be 0 -Because ($out | Out-String)
    }
}

Describe 'Test-PfbPs51Compat -All' -Skip:($PSVersionTable.PSEdition -ne 'Desktop') {
    It 'reads tracked files only: an untracked .psmodules/ copy is never scanned' {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path (Join-Path $root 'Public'), (Join-Path $root '.psmodules') -Force
        [System.IO.File]::WriteAllText((Join-Path $root 'PureStorageFlashBladePowerShell.psd1'), "@{}`n")
        [System.IO.File]::WriteAllText((Join-Path $root 'Public/A.ps1'), "`$v = `$c ? 1 : 2`n")
        # Both untracked samples are IN scope, so only the tracked-files rule can keep them out:
        # a .psmodules/ path alone is outside every class, and would pass even if scanned.
        [System.IO.File]::WriteAllText((Join-Path $root '.psmodules/Foo.ps1'), "#Requires -Version 5.1`n`$v = `$c ? 1 : 2`n")
        [System.IO.File]::WriteAllText((Join-Path $root 'Public/Untracked.ps1'), "`$v = `$c ? 1 : 2`n")
        # Under a caller's $ErrorActionPreference = 'Stop', Windows PowerShell 5.1 turns git's
        # stderr (an autocrlf "LF will be replaced by CRLF" warning) into a terminating error,
        # so relax it for the setup calls and decide on git's exit code instead.
        $ErrorActionPreference = 'Continue'
        & git -C $root init -q 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 0 -Because 'git init must succeed for the fixture'
        & git -C $root add -- PureStorageFlashBladePowerShell.psd1 Public/A.ps1 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 0 -Because 'git add must succeed for the fixture'
        Push-Location $root
        try { $out = @(& $script:compat -All 6>$null); $code = $LASTEXITCODE } finally { Pop-Location }
        @($out | ForEach-Object Path | Sort-Object -Unique) -join ',' | Should -BeExactly 'Public/A.ps1'
        $code | Should -Be 1
    }
    It 'emits ::error file=,line= for class 1 under GitHub Actions' {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path (Join-Path $root 'Tests') -Force
        [System.IO.File]::WriteAllText((Join-Path $root 'PureStorageFlashBladePowerShell.psd1'), "@{}`n")
        $f = Join-Path $root 'Tests/A.Tests.ps1'
        [System.IO.File]::WriteAllText($f, "`n`$v = `$c ? 1 : 2`n")
        $had = Test-Path Env:GITHUB_ACTIONS
        $saved = $env:GITHUB_ACTIONS
        try {
            $env:GITHUB_ACTIONS = 'true'
            $info = @(& $script:compat -Path $f 6>&1 | Where-Object { $_ -is [System.Management.Automation.InformationRecord] } | ForEach-Object { [string]$_.MessageData })
        } finally { if ($had) { $env:GITHUB_ACTIONS = $saved } else { Remove-Item Env:GITHUB_ACTIONS } }
        @($info | Where-Object { $_ -like '::error file=Tests/A.Tests.ps1,line=2::*' }).Count | Should -Be 1
    }
    It 'the real tree has no class-1 finding (measured 0 on main when this landed)' {
        Push-Location $script:repoRoot
        try { $out = @(& $script:compat -All 6>$null); $code = $LASTEXITCODE } finally { Pop-Location }
        @($out | Where-Object Class -eq 1 | ForEach-Object { '{0}:{1} {2}' -f $_.Path, $_.Line, $_.Message }) -join "`n" | Should -BeNullOrEmpty
        # An exit 2 (could not run) also returns no class-1 finding, so the exit code is what
        # proves the tree was actually scanned.
        $code | Should -Be 0
    }
}

Describe 'cross-platform-tests.yml runs the 5.1 compatibility check on the 5.1 leg' {
    BeforeAll {
        $script:xp = [System.IO.File]::ReadAllText((Join-Path $script:repoRoot '.github/workflows/cross-platform-tests.yml'))
        $script:job = [regex]::Match($script:xp, '(?ms)^  test-windows-powershell-5-1:\r?\n(.*?)(?=^  \S|\z)').Groups[1].Value
    }
    It 'runs ./tools/Test-PfbPs51Compat.ps1 -All directly, under shell: powershell, straight after checkout' {
        $script:job | Should -Not -BeNullOrEmpty -Because 'the 5.1 job must be found before its text is checked'
        $script:job | Should -Match '(?ms)- name: Checkout\s*\r?\n\s+uses: actions/checkout@\S+[^\r\n]*\r?\n\s*\r?\n(?:\s*#[^\r\n]*\r?\n)*\s+- name: Check Windows PowerShell 5\.1 compatibility\s*\r?\n\s+shell: powershell\s*\r?\n\s+run: \./tools/Test-PfbPs51Compat\.ps1 -All\s*$'
        $script:job | Should -Not -Match 'powershell(\.exe)? -File'
    }
    It 'lets a finding fail the job: nothing in the 5.1 job sets continue-on-error' {
        $script:job | Should -Not -Match 'continue-on-error'
    }
}
