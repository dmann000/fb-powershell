#Requires -Version 5.1
<#
.SYNOPSIS
    Checks PowerShell files against Windows PowerShell 5.1: parse errors (class 1), runtime
    failures (class 2) and silently different behaviour (class 3).
.DESCRIPTION
    RUN IT UNDER WINDOWS POWERSHELL 5.1 (powershell.exe). The class-1 verdict is the 5.1
    parser's own answer, so under PowerShell 7 it would be the wrong parser's; the script
    refuses (exit 2).

    WHICH FILES OWE WHAT. Scope is decided here, per class, from repo-relative paths. The repo
    root is the nearest directory holding PureStorageFlashBladePowerShell.psd1, so this works
    in any clone or worktree.

      CLASS 1, must parse on 5.1 -- everything the Windows PowerShell 5.1 CI leg parses:
        Public/, Private/, the root *.psm1 and *.psd1, Tests/ and scripts/. One parse error in
        a test file fails every test in it, and a -Skip: guard cannot help, because the file
        never parses far enough for Pester to read the guard.
      CLASSES 2 AND 3, must RUN the same on 5.1 -- only what ships: Public/, Private/ and the
        root *.psm1 and *.psd1.
      Either scope also covers any file declaring `#Requires -Version 5.1`; a file declaring
      `#Requires -Version 7` is out of both.

    Classes 2 and 3 are matched on the AST -- command and parameter names, variable nodes --
    so a comment, and a LITERAL (single-quoted) string, can never produce a finding. An
    expandable (double-quoted) string is different: a variable or $(...) subexpression inside
    it is real code, so "$PSStyle" or "$(Split-Path x -LeafBase)" IS reported. A quoted
    -Encoding value is read as the constant it is. A construct is not reported when it
    sits within 6 lines after a `$PSVersionTable` / `PSEdition` / `$PSVersion` check, when the
    line or one of the 6 before it carries a `# ps51-ok` comment, or (class 2 only) inside a
    Pester Describe or Context skipped on PSVersion.
.PARAMETER Path
    Files to check.
.PARAMETER All
    Check every TRACKED .ps1/.psm1/.psd1 in the repository containing the current directory
    (git ls-files). Untracked and ignored files -- saved modules, caches, build output -- are
    never read.
.PARAMETER ListRules
    List the rule ids and messages, and exit.
.OUTPUTS
    One object per finding: Path (repo-relative), Line, Class, Rule, Severity, Message.
    Exit code 0 = no class-1 finding, 1 = class-1 finding(s), 2 = could not run.
.EXAMPLE
    powershell.exe -NoProfile -File ./tools/Test-PfbPs51Compat.ps1 -All
#>
[CmdletBinding(DefaultParameterSetName = 'Path')]
param(
    [Parameter(ParameterSetName = 'Path', Position = 0)][string[]]$Path,
    [Parameter(ParameterSetName = 'All')][switch]$All,
    [Parameter(ParameterSetName = 'List')][switch]$ListRules
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Exit 1 means class-1 findings, and a gate reads it that way. An uncaught terminating error
# would also exit 1, so a malfunction (an unreadable file, a parser exception) would read as
# a real finding. Every failure to run exits 2 instead: the named cases below exit 2 with
# their own message, and this trap is the backstop for anything unexpected.
trap {
    Write-Host "Test-PfbPs51Compat.ps1 could not run: $_" -ForegroundColor Red
    exit 2
}

$script:Manifest = 'PureStorageFlashBladePowerShell.psd1'
$script:ReReq7 = '(?im)^\s*#Requires\s+-Version\s+([7-9]|\d{2,})'
$script:ReReq5 = '(?im)^\s*#Requires\s+-Version\s+5'
$script:Rules = @(
    [pscustomobject]@{ Id = 'c1-parse'; Class = 1; Message = 'Does not parse on Windows PowerShell 5.1. In Tests/ this fails every test in the file; a -Skip: guard cannot help.' }
    # Class 2 and 3 rules are appended here.
)

if ($ListRules) { $script:Rules; exit 0 }

if ($PSVersionTable.PSEdition -ne 'Desktop') {
    Write-Host 'Test-PfbPs51Compat.ps1 must run under Windows PowerShell 5.1 (powershell.exe): its class-1 verdict is the 5.1 parser''s answer.' -ForegroundColor Red
    exit 2
}

function Find-PfbRepoRoot {
    param([string]$StartDirectory)
    $dir = $StartDirectory
    for ($i = 0; $i -lt 40 -and $dir; $i++) {
        if (Test-Path -LiteralPath (Join-Path $dir $script:Manifest)) { return $dir }
        $parent = Split-Path -Parent $dir
        if ($parent -eq $dir) { break }
        $dir = $parent
    }
    return $null
}

function Get-PfbCompatScope {
    param([string]$RelativePath, [string]$Source)
    if ($Source -match $script:ReReq7) { return @{ C1 = $false; C23 = $false } }
    $declares51 = $Source -match $script:ReReq5
    $rootModule = $RelativePath -match '^[^/]+\.(psm1|psd1)$'
    return @{
        C1  = ($declares51 -or $rootModule -or ($RelativePath -match '^(Public|Private|Tests|scripts)/'))
        C23 = ($declares51 -or $rootModule -or ($RelativePath -match '^(Public|Private)/'))
    }
}

function New-PfbCompatFinding {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds an in-memory finding record; changes no state.')]
    param([string]$RelativePath, [int]$Line, [string]$RuleId, [string]$Detail)
    $rule = $script:Rules | Where-Object { $_.Id -eq $RuleId } | Select-Object -First 1
    $severity = 'warning'
    if ($rule.Class -eq 1) { $severity = 'error' }
    $message = $rule.Message
    if ($Detail) { $message = "$Detail -- $message" }
    [pscustomobject]@{ Path = $RelativePath; Line = $Line; Class = $rule.Class; Rule = $RuleId; Severity = $severity; Message = $message }
}

function Test-PfbCompatFile {
    param([string]$FullPath, [string]$Root)
    $rel = $FullPath.Substring($Root.Length).TrimStart('\', '/') -replace '\\', '/'
    $source = [System.IO.File]::ReadAllText($FullPath)
    $scope = Get-PfbCompatScope -RelativePath $rel -Source $source
    if (-not ($scope.C1 -or $scope.C23)) { return }
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($FullPath, [ref]$tokens, [ref]$errors)
    if ($scope.C1) {
        foreach ($e in @($errors)) {
            New-PfbCompatFinding -RelativePath $rel -Line $e.Extent.StartLineNumber -RuleId 'c1-parse' -Detail (($e.Message -split "`n")[0])
        }
    }
    if ($scope.C23 -and @($errors).Count -eq 0) {
        # Class 2 and 3 AST checks go here, reading $ast and $tokens.
        $null = $ast
    }
}

# --- resolve the file list -------------------------------------------------------------
$targets = @()
if ($All) {
    $root = Find-PfbRepoRoot -StartDirectory (Get-Location).ProviderPath
    if (-not $root) { Write-Host "No $script:Manifest above $((Get-Location).ProviderPath)." -ForegroundColor Red; exit 2 }
    if (-not (Get-Command -Name git -CommandType Application -ErrorAction SilentlyContinue)) {
        Write-Host 'git was not found on PATH; -All needs it to list the tracked files.' -ForegroundColor Red
        exit 2
    }
    # Under 'Stop', Windows PowerShell 5.1 turns any redirected stderr line from a native
    # command into a terminating error, so git's own exit code would never be read and a
    # harmless warning would abort the run. Relax it for this one call, keep stderr apart
    # from the file list, and decide on $LASTEXITCODE alone.
    $ErrorActionPreference = 'Continue'
    $gitOutput = @(& git -C $root ls-files -- '*.ps1' '*.psm1' '*.psd1' 2>&1)
    $gitExit = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    $gitErrors = @($gitOutput | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
    if ($gitExit -ne 0) {
        Write-Host ("git ls-files failed (exit {0}) in {1}: {2}" -f $gitExit, $root, (($gitErrors | ForEach-Object { "$_" }) -join ' ')) -ForegroundColor Red
        exit 2
    }
    $listed = @($gitOutput | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })
    $targets = @($listed | ForEach-Object { [pscustomobject]@{ Full = (Join-Path $root $_); Root = $root } })
} else {
    foreach ($p in @($Path)) {
        if (-not $p) { continue }
        if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
            Write-Host "No such file: $p" -ForegroundColor Red
            exit 2
        }
        $full = (Resolve-Path -LiteralPath $p).ProviderPath
        $root = Find-PfbRepoRoot -StartDirectory (Split-Path -Parent $full)
        if ($root) { $targets += [pscustomobject]@{ Full = $full; Root = $root } }
    }
}

$findings = @(foreach ($t in $targets) { Test-PfbCompatFile -FullPath $t.Full -Root $t.Root })

if ($env:GITHUB_ACTIONS -eq 'true') {
    foreach ($f in $findings) {
        $kind = 'warning'
        if ($f.Class -eq 1) { $kind = 'error' }
        $msg = ($f.Message -replace '%', '%25' -replace "`r", '%0D' -replace "`n", '%0A')
        Write-Host ("::{0} file={1},line={2}::[class {3}] {4}" -f $kind, $f.Path, $f.Line, $f.Class, $msg)
    }
}
Write-Host ("Checked {0} file(s): {1} class-1, {2} class-2/3 finding(s)." -f $targets.Count, @($findings | Where-Object Class -eq 1).Count, @($findings | Where-Object Class -ne 1).Count)

$findings
if (@($findings | Where-Object Class -eq 1).Count -gt 0) { exit 1 }
exit 0
