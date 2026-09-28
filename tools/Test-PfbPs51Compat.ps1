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
)
$script:Rules += @(
    [pscustomobject]@{ Id = 'c2-convertfrom-json-depth'; Class = 2; Message = 'ConvertFrom-Json -Depth (PS 6.2+). 5.1 throws "A parameter cannot be found that matches parameter name ''Depth''". ConvertTo-Json -Depth is fine.' }
    [pscustomobject]@{ Id = 'c2-convertfrom-json-ashashtable'; Class = 2; Message = 'ConvertFrom-Json -AsHashtable (PS 6+).' }
    [pscustomobject]@{ Id = 'c2-foreach-parallel'; Class = 2; Message = 'ForEach-Object -Parallel (PS 7+).' }
    [pscustomobject]@{ Id = 'c2-foreach-throttlelimit'; Class = 2; Message = 'ForEach-Object -ThrottleLimit (PS 7+).' }
    [pscustomobject]@{ Id = 'c2-content-asbytestream'; Class = 2; Message = '-AsByteStream (PS 6+). On 5.1 use -Encoding Byte.' }
    [pscustomobject]@{ Id = 'c2-test-json'; Class = 2; Message = 'Test-Json (PS 6+).' }
    [pscustomobject]@{ Id = 'c2-join-string'; Class = 2; Message = 'Join-String (PS 6.2+).' }
    [pscustomobject]@{ Id = 'c2-split-path-leafbase'; Class = 2; Message = 'Split-Path -LeafBase (PS 6+).' }
    [pscustomobject]@{ Id = 'c2-skipcertificatecheck'; Class = 2; Message = '-SkipCertificateCheck (PS 6+).' }
    [pscustomobject]@{ Id = 'c2-encoding-utf8nobom'; Class = 2; Message = '-Encoding utf8NoBOM/utf8BOM (PS 6+ encoding names; 5.1 accepts only UTF8).' }
    [pscustomobject]@{ Id = 'c2-psstyle'; Class = 2; Message = '$PSStyle (PS 7.2+).' }
    [pscustomobject]@{ Id = 'c3-sort-object-culture'; Class = 3; Message = 'Sort-Object -Culture: 5.1 (.NET Framework) and 7 (.NET/ICU) disagree on invariant linguistic order. Sort ordinally instead.' }
    [pscustomobject]@{ Id = 'c3-utf8-bom-write'; Class = 3; Message = 'Set-Content/Add-Content/Out-File -Encoding UTF8 writes a BOM on 5.1 and none on 7. Use [System.IO.File]::WriteAllText with UTF8Encoding($false).' }
    [pscustomobject]@{ Id = 'c3-is-platform-variable'; Class = 3; Message = '$IsWindows/$IsLinux/$IsMacOS/$IsCoreCLR are undefined on 5.1, so they read as $null and the branch silently takes the wrong path.' }
)

# Anchored to the COMMAND as well as the parameter: that is what keeps ConvertTo-Json -Depth
# out of the ConvertFrom-Json -Depth finding. Exact names only: a parameter abbreviation
# (-Dep) and the `foreach` alias are not matched, as in the hook. ONE deliberate difference:
# the `%` alias IS matched here, while the hook's \b(?:ForEach-Object|%)\b can never match a
# `%` between spaces. That makes the script stricter, and Cases.psd1 lists it under
# KnownDivergences.
$script:CommandRules = @(
    @{ Id = 'c2-convertfrom-json-depth'; Commands = @('ConvertFrom-Json'); Parameter = 'Depth' }
    @{ Id = 'c2-convertfrom-json-ashashtable'; Commands = @('ConvertFrom-Json'); Parameter = 'AsHashtable' }
    @{ Id = 'c2-foreach-parallel'; Commands = @('ForEach-Object', '%'); Parameter = 'Parallel' }
    @{ Id = 'c2-foreach-throttlelimit'; Commands = @('ForEach-Object', '%'); Parameter = 'ThrottleLimit' }
    @{ Id = 'c2-content-asbytestream'; Commands = @('Get-Content', 'Set-Content', 'Add-Content'); Parameter = 'AsByteStream' }
    @{ Id = 'c2-test-json'; Commands = @('Test-Json'); Parameter = $null }
    @{ Id = 'c2-join-string'; Commands = @('Join-String'); Parameter = $null }
    @{ Id = 'c2-split-path-leafbase'; Commands = @('Split-Path'); Parameter = 'LeafBase' }
    @{ Id = 'c2-skipcertificatecheck'; Commands = @('Invoke-RestMethod', 'Invoke-WebRequest'); Parameter = 'SkipCertificateCheck' }
    @{ Id = 'c3-sort-object-culture'; Commands = @('Sort-Object'); Parameter = 'Culture' }
)
$script:VariableRules = @(
    @{ Id = 'c2-psstyle'; Names = @('PSStyle') }
    @{ Id = 'c3-is-platform-variable'; Names = @('IsWindows', 'IsLinux', 'IsMacOS', 'IsCoreCLR') }
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

function Get-PfbCommandName {
    # GetCommandName() without a module qualifier, so Microsoft.PowerShell.Utility\ConvertFrom-Json
    # is read as ConvertFrom-Json -- as the hook's \b-anchored pattern also reads it.
    param([System.Management.Automation.Language.CommandAst]$Command)
    $name = $Command.GetCommandName()
    if (-not $name) { return $null }
    return ($name -replace '^.*\\', '')
}

function Get-PfbParameterArgument {
    # The value bound to -Name on a command: -Name:value (Argument) or -Name value (the next element).
    param([System.Management.Automation.Language.CommandAst]$Command, [string]$Name)
    $els = $Command.CommandElements
    for ($i = 0; $i -lt $els.Count; $i++) {
        $e = $els[$i]
        if ($e -isnot [System.Management.Automation.Language.CommandParameterAst] -or $e.ParameterName -ne $Name) { continue }
        if ($e.Argument) { return $e.Argument }
        if ($i + 1 -lt $els.Count -and $els[$i + 1] -isnot [System.Management.Automation.Language.CommandParameterAst]) { return $els[$i + 1] }
        return $null
    }
    return $null
}

function Test-PfbHasParameter {
    param([System.Management.Automation.Language.CommandAst]$Command, [string]$Name)
    return (@($Command.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -eq $Name }).Count -gt 0)
}

# Tokens that are real code: comments and strings excluded, exactly what the hook's
# stripInert blanks.
$script:InertKinds = @('Comment', 'StringLiteral', 'StringExpandable', 'HereStringLiteral', 'HereStringExpandable')

function Test-PfbSuppressedByPragma {
    # `# ps51-ok` on the finding's line or on any of the 6 lines before it.
    param([object[]]$Tokens, [int]$Line)
    return (@($Tokens | Where-Object {
                $_.Kind.ToString() -eq 'Comment' -and $_.Extent.StartLineNumber -ge ($Line - 6) -and
                $_.Extent.StartLineNumber -le $Line -and $_.Text -match '#\s*ps51-ok' }).Count -gt 0)
}

function Test-PfbSuppressedByVersionGate {
    # A $PSVersionTable / $PSVersion / PSEdition reference in the 6 lines BEFORE the finding
    # (not the finding's own line -- the hook's window, kept identical for parity). Matched on
    # the token TEXT, as the hook's \$PSVersionTable|\$PSVersion\b does: a variable token's
    # Name drops a scope qualifier, so $script:PSVersionTable -- a different, possibly unset
    # variable -- would otherwise count as a gate.
    param([object[]]$Tokens, [int]$Line)
    return (@($Tokens | Where-Object {
                $kind = $_.Kind.ToString()
                $_.Extent.StartLineNumber -ge ($Line - 6) -and $_.Extent.StartLineNumber -le ($Line - 1) -and
                ($script:InertKinds -notcontains $kind) -and
                (($kind -eq 'Variable' -and $_.Text -in '$PSVersionTable', '$PSVersion') -or $_.Text -eq 'PSEdition') }).Count -gt 0)
}

function Test-PfbPesterSkipGuard {
    # -Skip:<expr> reading PSVersion. Only the colon form carries a value: -Skip is a switch,
    # so in `Describe 'x' -Skip { ... }` the next element is the block body, not a guard, and
    # a body that merely mentions PSVersion must not read as one.
    param([System.Management.Automation.Language.CommandAst]$Block)
    foreach ($e in $Block.CommandElements) {
        if ($e -is [System.Management.Automation.Language.CommandParameterAst] -and $e.ParameterName -eq 'Skip' -and
            $e.Argument -and $e.Argument.Extent.Text -match 'PSVersion') { return $true }
    }
    return $false
}

function Test-PfbInSkippedBlock {
    # Class 2 only: inside the nearest enclosing Describe/Context whose -Skip reads PSVersion;
    # with no enclosing block, every Describe in the file must be so skipped.
    param([System.Management.Automation.Language.Ast]$Node, [System.Management.Automation.Language.Ast]$Root)
    for ($p = $Node.Parent; $null -ne $p; $p = $p.Parent) {
        if ($p -is [System.Management.Automation.Language.ScriptBlockExpressionAst] -and
            $p.Parent -is [System.Management.Automation.Language.CommandAst] -and
            (Get-PfbCommandName -Command $p.Parent) -in 'Describe', 'Context') {
            return (Test-PfbPesterSkipGuard -Block $p.Parent)
        }
    }
    $describes = @($Root.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and (Get-PfbCommandName -Command $n) -eq 'Describe' }, $true))
    if ($describes.Count -eq 0) { return $false }
    return (@($describes | Where-Object { -not (Test-PfbPesterSkipGuard -Block $_) }).Count -eq 0)
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
        $isTest = $rel -match '^Tests/'
        $hits = New-Object System.Collections.Generic.List[object]
        foreach ($cmd in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {
            $name = Get-PfbCommandName -Command $cmd
            if (-not $name) { continue }
            foreach ($rule in $script:CommandRules) {
                if ($rule.Commands -notcontains $name) { continue }
                if ($rule.Parameter -and -not (Test-PfbHasParameter -Command $cmd -Name $rule.Parameter)) { continue }
                $hits.Add(@{ Id = $rule.Id; Node = $cmd })
            }
            $enc = Get-PfbParameterArgument -Command $cmd -Name 'Encoding'
            if ($enc -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                if ($enc.Value -in 'utf8NoBOM', 'utf8BOM') { $hits.Add(@{ Id = 'c2-encoding-utf8nobom'; Node = $cmd }) }
                if ($enc.Value -eq 'UTF8' -and $name -in 'Set-Content', 'Add-Content', 'Out-File' -and -not $isTest) {
                    $hits.Add(@{ Id = 'c3-utf8-bom-write'; Node = $cmd })
                }
            }
        }
        foreach ($var in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.VariableExpressionAst] }, $true)) {
            foreach ($rule in $script:VariableRules) {
                if ($rule.Names -contains $var.VariablePath.UserPath) { $hits.Add(@{ Id = $rule.Id; Node = $var }) }
            }
        }
        foreach ($h in $hits) {
            $line = $h.Node.Extent.StartLineNumber
            $class = ($script:Rules | Where-Object { $_.Id -eq $h.Id } | Select-Object -First 1).Class
            if (Test-PfbSuppressedByPragma -Tokens $tokens -Line $line) { continue }
            if (Test-PfbSuppressedByVersionGate -Tokens $tokens -Line $line) { continue }
            if ($class -eq 2 -and (Test-PfbInSkippedBlock -Node $h.Node -Root $ast)) { continue }
            New-PfbCompatFinding -RelativePath $rel -Line $line -RuleId $h.Id
        }
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
