#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    AST checks for PowerShell traps that pass every test while proving nothing.
.DESCRIPTION
    Each rule has a bad-form fixture that must be flagged and a good-form fixture that must
    pass, so no rule can be green vacuously, and a sweep of the tracked tree.

    UNGATED on edition: parse only, 5.1-safe. Listed in RequiredDescribes for both editions.

    DEFERRED, not encoded here: "a local assigned under the name of a parameter of the
    enclosing function" (variable names are case-insensitive, so it IS the parameter and
    coerces to its declared type). It has hits in Public/ today, and fixing shipped code
    would need live FlashBlade verification, which is out of scope for a test-only change.
    Tracked as a follow-up.
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    function Get-TestAst {
        param([string]$Source)
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseInput($Source, [ref]$tokens, [ref]$errors)
    }
    function Get-TestTrackedFile {
        # Throws rather than returning nothing when git fails: an empty list would make every
        # tree sweep below green without reading a single file.
        param([string[]]$Prefix)
        $ErrorActionPreference = 'Continue'
        $listed = @(& git -C $script:repoRoot ls-files -- '*.ps1' '*.psm1' 2>&1)
        $gitExit = $LASTEXITCODE
        if ($gitExit -ne 0) { throw "git ls-files failed (exit $gitExit): $($listed -join ' ')" }
        $files = @($listed | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] } | Where-Object { $f = [string]$_; @($Prefix | Where-Object { $f.StartsWith($_) }).Count -gt 0 })
        if ($files.Count -eq 0) { throw "git ls-files listed no tracked file under $($Prefix -join ', ')" }
        $files
    }

    # Rule 1: $PSBoundParameters inside -ParameterFilter is EMPTY there, so any assertion on it
    # is vacuous (e.g. -not $PSBoundParameters.ContainsKey('Body') is always true).
    function Find-TestBoundParametersInFilter {
        param([System.Management.Automation.Language.Ast]$Ast)
        foreach ($cmd in $Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {
            $els = $cmd.CommandElements
            for ($i = 0; $i -lt $els.Count; $i++) {
                $e = $els[$i]
                if ($e -isnot [System.Management.Automation.Language.CommandParameterAst] -or $e.ParameterName -ne 'ParameterFilter') { continue }
                $arg = $e.Argument
                if (-not $arg -and $i + 1 -lt $els.Count) { $arg = $els[$i + 1] }
                if (-not $arg) { continue }
                foreach ($v in $arg.FindAll({ param($n) $n -is [System.Management.Automation.Language.VariableExpressionAst] -and $n.VariablePath.UserPath -eq 'PSBoundParameters' }, $true)) {
                    $v.Extent.StartLineNumber
                }
            }
        }
    }

    # Rule 2: -like/-notlike treat backtick as an escape and [ ] as a character class, so a
    # pattern copied from markdown silently never matches. Only the LITERAL text of the
    # pattern counts: a `[` inside a $(...) subexpression is code, not pattern.
    function Find-TestLikeLiteralTrap {
        param([System.Management.Automation.Language.Ast]$Ast)
        $ops = 'Ilike', 'Clike', 'Inotlike', 'Cnotlike'
        foreach ($b in $Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.BinaryExpressionAst] }, $true)) {
            if ($ops -notcontains $b.Operator.ToString()) { continue }
            $r = $b.Right
            $literal = $null
            if ($r -is [System.Management.Automation.Language.StringConstantExpressionAst]) { $literal = $r.Value }
            elseif ($r -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) {
                $literal = $r.Value
                foreach ($nested in $r.NestedExpressions) { $literal = $literal.Replace($nested.Extent.Text, '') }
            }
            if ($null -ne $literal -and ($literal.Contains('`') -or $literal.Contains('['))) { $b.Extent.StartLineNumber }
        }
    }
}

Describe 'Convention: no $PSBoundParameters inside a -ParameterFilter' {
    It 'flags the vacuous form (control)' {
        @(Find-TestBoundParametersInFilter (Get-TestAst "Should -Invoke Foo -ParameterFilter { -not `$PSBoundParameters.ContainsKey('Body') }")).Count | Should -Be 1
    }
    It 'passes an assertion on the bound variable (control)' {
        @(Find-TestBoundParametersInFilter (Get-TestAst 'Should -Invoke Foo -ParameterFilter { $null -eq $Body }')).Count | Should -Be 0
    }
    It 'no test file does it' {
        $hits = foreach ($f in Get-TestTrackedFile -Prefix 'Tests/') {
            foreach ($line in @(Find-TestBoundParametersInFilter ([System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:repoRoot $f), [ref]$null, [ref]$null)))) { "${f}:$line" }
        }
        @($hits) -join "`n" | Should -BeNullOrEmpty -Because 'inside -ParameterFilter the arguments arrive as plain variables; assert on $Body, not on $PSBoundParameters'
    }
}

Describe 'Convention: no backtick or [ in a -like pattern literal' {
    It 'flags <Why> (control)' -ForEach @(
        @{ Why = 'a backtick in a single-quoted pattern'; Src = '$l -like ''*`AuthorizationModel` capture.*''' }
        @{ Why = 'a markdown checkbox'; Src = '$l -like ''- [ ] **Step*''' }
        @{ Why = '-notlike too'; Src = '$l -notlike ''*[x]*''' }
        @{ Why = 'a [ in a double-quoted pattern'; Src = '$l -like "*[$n*"' }
    ) {
        @(Find-TestLikeLiteralTrap (Get-TestAst $Src)).Count | Should -Be 1
    }
    It 'passes <Why> (control)' -ForEach @(
        @{ Why = 'a plain wildcard'; Src = '$l -like ''*capture*''' }
        @{ Why = 'a [ that lives in a $(...) subexpression, not the pattern'; Src = '$e -like "*$([System.Management.Automation.WildcardPattern]::Escape($m))*"' }
        @{ Why = '-match, which is regex'; Src = '$l -match ''\[ \]''' }
    ) {
        @(Find-TestLikeLiteralTrap (Get-TestAst $Src)).Count | Should -Be 0
    }
    It 'no tracked source file does it' {
        $hits = foreach ($f in Get-TestTrackedFile -Prefix 'Public/', 'Private/', 'Tests/', 'tools/', 'scripts/') {
            foreach ($line in @(Find-TestLikeLiteralTrap ([System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:repoRoot $f), [ref]$null, [ref]$null)))) { "${f}:$line" }
        }
        @($hits) -join "`n" | Should -BeNullOrEmpty -Because 'use .Contains() / .StartsWith(), or -match with [regex]::Escape()'
    }
}
