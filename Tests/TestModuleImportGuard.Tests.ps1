#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
    UNGATED on edition, on purpose: pure AST plus file IO, 5.1-safe, no spec cache, and
    no graceful-skip path. It must contribute executed tests on both legs, which is why it
    is listed in RequiredDescribes in BOTH blocks of coverage-baseline.psd1 -- MaxSkipped
    cannot see a Describe that vanishes without skipping.

    Deliberately does NOT try to detect a leaked shim. A test asserting "the module I can
    see right now is pristine" would pass or fail depending on container order and would be
    a flaky red. Shim detection belongs in Tests/PfbTestModule.ps1, at runtime, per call.
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $script:repoRoot 'tools/lib/PfbTestImportTools.ps1')
    $script:exported = @(Get-PfbExportedFunctionName -ManifestPath (
        Join-Path $script:repoRoot 'PureStorageFlashBladePowerShell.psd1'))
    # -Recurse so all three enumerations of Tests/ agree: the rewriter recurses, and the CI
    # runner's Run.Path = 'Tests' is recursive too. There are no test files in subdirectories
    # today, so this changes nothing observable -- it closes a future hole. The asymmetry that
    # makes it worth closing: the second It below catches a file that uses the module without
    # loading it through the helper, a failure invisible in a full-suite run and visible only
    # in a standalone single-file run. A subdirectory file would escape that check silently.
    $script:testFiles = @(Get-ChildItem -Path (Join-Path $script:repoRoot 'Tests') -Filter '*.Tests.ps1' -File -Recurse)

    # Files that legitimately force-import in their OWN process or runspace, or need a
    # genuinely virgin module and cannot use -Fresh. Kept as short as it can possibly be:
    # the separate-runspace call and the Mock argument are excluded STRUCTURALLY by the AST
    # predicate, not by being listed here.
    #
    # PfbTestModule.Tests.ps1 is the helper's own test file. It installs an UNMARKED module
    # instance with a raw -Force import on purpose -- that import is the fixture proving the
    # helper rebuilds when something outside it loads the module, which is the single most
    # important behaviour the helper has. Converting it would mean testing the detector
    # without ever triggering the condition it detects. This entry must stay in lockstep
    # with the rewriter's own exclusion set in tools/Update-PfbTestModuleImport.ps1: a file
    # the rewriter refuses to convert still contains a raw import, so if the two lists ever
    # diverge, one of them is wrong.
    $script:allowlist = @('PfbTestModule.Tests.ps1')
}

Describe 'Test-module import guard (AST, no spec cache required, every edition)' {
    It 'finds no raw -Force manifest import in any test file' {
        $offenders = @()
        foreach ($file in $script:testFiles) {
            if ($script:allowlist -contains $file.Name) { continue }
            foreach ($import in @(Get-PfbTestManifestImport -Path $file.FullName)) {
                $offenders += ("{0}:{1} -- {2}" -f $file.Name, $import.Line, $import.Text)
            }
        }
        # A bare list of offending lines says what is wrong and not what to do, so the
        # correct shape ships with the failure. These are the exact two lines
        # tools/Update-PfbTestModuleImport.ps1 emits.
        $message = ''
        if ($offenders.Count -gt 0) {
            $message = ($offenders -join "`n") + "`n`n" + (@(
                'Load the module through the shared helper instead. Inside BeforeAll:'
                ''
                "    . (Join-Path `$PSScriptRoot 'PfbTestModule.ps1')"
                '    $null = Import-PfbTestModule'
                ''
                'Both lines must be INSIDE BeforeAll. ./tools/Update-PfbTestModuleImport.ps1'
                'performs this rewrite automatically; run it with -WhatIf first.'
            ) -join "`n")
        }
        $message | Should -BeNullOrEmpty
    }

    It 'finds no test file that uses the module without loading it through the helper' {
        # A file that DELETES its import and then rides whatever a previous container left
        # loaded is a WORSE failure than the one this change fixes, and it is invisible in a
        # full-suite run because the module is always loaded by the time it matters. This
        # half of the guard is what protects the standalone single-file run.
        $offenders = @()
        foreach ($file in $script:testFiles) {
            if ($script:allowlist -contains $file.Name) { continue }
            $usage = Test-PfbTestModuleUsage -Path $file.FullName -ExportedFunction $script:exported
            if ($usage.Uses -and -not $usage.CallsHelper) {
                $offenders += ("{0} -- {1}" -f $file.Name, ($usage.Reasons -join '; '))
            }
        }
        $offenders -join "`n" | Should -BeNullOrEmpty
    }

    It 'pins the set of VOLATILE module-scope variables so a new one cannot appear unnoticed' {
        # Risk 2 from the spec, in its real form. Scanning only the .psm1 preamble is NOT
        # enough and would be close to vacuous: $script:PfbCachedCredential is never
        # declared there -- it springs into existence on first write inside
        # Set-PfbCredential / Get-PfbCredential -- and the spec's original five-variable
        # enumeration missed it for exactly that reason.
        #
        # The distinction that matters is WHERE the assignment lives, not which file:
        #   - inside a function body  => runs whenever that function is called => VOLATILE
        #   - at dot-source scope     => runs once per import => a constant, safe to leave
        # That correctly excludes $script:PfbAllArraysSuffix (Private/PfbContext.ps1) and the
        # three constants in Private/PfbContextConstants.ps1.
        #
        # This is a CHANGE DETECTOR, not a correctness assertion: the helper resets EVERY
        # variable on this list unconditionally -- the connection pair, the credential cache,
        # and both JSON caches. An earlier revision left the two JSON caches warm on the
        # grounds that they were safe to reuse; commit d649d6d reversed exactly that, and
        # Tests/PfbTestModule.ps1 argues at length that the reset must never become
        # conditional again. If this list changes, decide whether the newcomer is volatile
        # (per the assignment-position rule above) and update Tests/PfbTestModule.ps1 to
        # reset it too.
        $sources = @()
        $sources += Get-Item (Join-Path $script:repoRoot 'PureStorageFlashBladePowerShell.psm1')
        $sources += Get-ChildItem (Join-Path $script:repoRoot 'Private') -Filter '*.ps1' -Recurse -File
        $sources += Get-ChildItem (Join-Path $script:repoRoot 'Public') -Filter '*.ps1' -Recurse -File

        $volatile = @()
        foreach ($source in $sources) {
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $source.FullName, [ref]$tokens, [ref]$errors)
            if ($null -ne $errors -and $errors.Count -gt 0) {
                throw ("{0} failed to parse: {1}" -f $source.Name, $errors[0].Message)
            }
            $assignments = @($ast.FindAll({
                param($node)
                return ($node -is [System.Management.Automation.Language.AssignmentStatementAst])
            }, $true))
            foreach ($assignment in $assignments) {
                # Key on the target's ROOT VARIABLE PATH, not on the raw extent text.
                # $script:PfbArrays is only ever assigned through an indexer
                # ($script:PfbArrays[$Array.Endpoint] = ..., $script:PfbArrays[$Endpoint] = ...),
                # so the raw extent yields '$script:PfbArrays[$Endpoint]' and a pin written
                # against plain variable names could never match. This pin is a change detector
                # over which VARIABLES are volatile, so the variable is the right key -- and
                # keying on the expression would also red spuriously the first time someone
                # rewrites an index expression.
                $left = $assignment.Left
                $variable = $left
                if (-not ($variable -is [System.Management.Automation.Language.VariableExpressionAst])) {
                    $variable = @($left.FindAll({
                        param($node)
                        return ($node -is [System.Management.Automation.Language.VariableExpressionAst])
                    }, $true))[0]
                }
                if ($null -eq $variable) { continue }
                $target = '$' + $variable.VariablePath.UserPath
                if ($target -notlike '$script:Pfb*') { continue }
                $node = $assignment.Parent
                $inFunction = $false
                while ($null -ne $node) {
                    if ($node -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
                        $inFunction = $true
                        break
                    }
                    $node = $node.Parent
                }
                if ($inFunction) { $volatile += $target }
            }
        }

        @($volatile | Sort-Object -Unique) | Should -Be @(
            '$script:PfbArrays'
            '$script:PfbCachedCredential'
            '$script:PfbCapabilityMap'
            '$script:PfbDefaultArray'
            '$script:PfbVersionMap'
        )
    }

    It 'keeps the guard allowlist and the rewriter exclusion set in lockstep' {
        # Both lists name files that legitimately keep a raw -Force import, and the comment on
        # $script:allowlist says they must stay in lockstep. This asserts it instead. The
        # dangerous direction is an entry added to the allowlist but NOT to the rewriter's
        # exclusion set: the rewriter would then convert a file this guard has stopped
        # watching, or a real offender would sit permanently unexamined. Both are literal
        # string arrays in tracked files, so the assertion is cheap and exact.
        #
        # Parsed with the AST rather than dot-sourced on purpose: the rewriter declares
        # `#Requires -Version 7.0` and this file is deliberately ungated on edition, so
        # dot-sourcing it would kill the whole container under Windows PowerShell 5.1.
        $rewriterPath = Join-Path $script:repoRoot 'tools/Update-PfbTestModuleImport.ps1'
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $rewriterPath, [ref]$tokens, [ref]$errors)
        if ($null -ne $errors -and $errors.Count -gt 0) {
            throw ("Update-PfbTestModuleImport.ps1 failed to parse: {0}" -f $errors[0].Message)
        }

        $assignments = @($ast.FindAll({
            param($node)
            if (-not ($node -is [System.Management.Automation.Language.AssignmentStatementAst])) {
                return $false
            }
            $left = $node.Left
            if (-not ($left -is [System.Management.Automation.Language.VariableExpressionAst])) {
                return $false
            }
            return ($left.VariablePath.UserPath -eq 'script:ExcludedFileName')
        }, $true))

        # Asserted as exactly one, not "at least one": if the variable is renamed or split,
        # this must fail loudly rather than compare the allowlist against an empty set and
        # report a false lockstep.
        $assignments.Count | Should -Be 1 -Because 'ExcludedFileName must remain a single literal assignment in tools/Update-PfbTestModuleImport.ps1'

        $exclusions = [string[]]@($assignments[0].Right.FindAll({
            param($node)
            return ($node -is [System.Management.Automation.Language.StringConstantExpressionAst])
        }, $true) | ForEach-Object { $_.Value })
        [Array]::Sort($exclusions, [System.StringComparer]::Ordinal)

        $allowed = [string[]]@($script:allowlist)
        [Array]::Sort($allowed, [System.StringComparer]::Ordinal)

        ($exclusions -join ', ') | Should -Be ($allowed -join ', ')
    }
}
