#Requires -Version 7.0
<#
.SYNOPSIS
    Rewrites every `Import-Module <manifest> -Force` in Tests/*.Tests.ps1 to load through
    Tests/PfbTestModule.ps1 instead.
.DESCRIPTION
    Run once to produce the 165-file diff, then kept tracked. It is NOT a build step and
    must not be wired into CI. It stays because (a) a 165-file diff must be reproducible
    and reviewable as generated output, and (b) it is the tool for the next bulk change of
    this shape. Its -WhatIf fixed-point test is what keeps it honest against a drifting
    tree (Tests/Update-PfbTestModuleImport.Tests.ps1).

    Only the import STATEMENT is replaced, in place, at its own indentation. Surrounding
    $moduleRoot / $manifest assignments are left alone: several files go on to use them
    (Tests/RemovedCmdlets.Tests.ps1 asserts against $manifest;
    Tests/ArrayConnection.ShouldProcessTarget.Tests.ps1 passes it to Get-PfbTargetRecorder).
    Deleting them would be a much larger, riskier diff for no gain.

    WHAT GETS REPLACED IS AN AST NODE, NOT A LINE. If the import is the right-hand side of
    a plain assignment, the enclosing AssignmentStatementAst is the replaced node and the
    emitted target is copied verbatim from that assignment's left-hand side. Otherwise the
    single-element pipeline containing the command is the replaced node and the target is
    $null. Nothing outside the replaced node's extent is ever touched: no leading
    indentation, no earlier statement on the same line, no trailing comment, no
    semicolon-joined following statement. An import the AST does not model as one of those
    two shapes is reported Unrecognised rather than rewritten -- hardcoding a target name
    would silently RENAME the caller's variable, and moving the left edge of the splice
    back to the line's indentation would silently DELETE whatever preceded it.

    An import carrying any parameter other than -Force/-PassThru/-Name is likewise
    Unrecognised, because Import-PfbTestModule has no way to honour it and emitting the
    helper call regardless would silently DROP it (-Global, -ErrorAction Stop). Zero such
    sites exist in this tree today; the point is that the next one stops the tool instead
    of changing behaviour quietly.

    Line endings are read, detected and preserved per file, and the newline spliced in is
    the one that terminates the preceding line rather than a per-file guess, so a file with
    mixed terminators neither loses its indentation nor gains a foreign terminator. Both LF
    and CRLF live in this tree because .gitattributes does not normalise .ps1, and splicing
    the wrong newline in makes every file differ, which reddens an idempotency test on one
    platform only.
.OUTPUTS
    Changed      - files this run changed, or would change under -WhatIf
    Unchanged    - count of files that already load through the helper, or that carry
                   nothing rewritable
    Excluded     - files never examined at all, per $script:ExcludedFileName below.
                   Reported, not silently absent: Changed.Count + Unchanged +
                   Excluded.Count accounts for every *.Tests.ps1 under -TestRoot.
    Unrecognised - manifest -Force imports whose spelling or syntactic position has no
                   rewrite arm. NEVER silently skipped: a silent skip reads as
                   "covered everything".
.EXAMPLE
    ./tools/Update-PfbTestModuleImport.ps1 -WhatIf
.EXAMPLE
    ./tools/Update-PfbTestModuleImport.ps1
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$TestRoot
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $repoRoot 'tools/lib/PfbTestImportTools.ps1')

if ([string]::IsNullOrWhiteSpace($TestRoot)) { $TestRoot = Join-Path $repoRoot 'Tests' }

# Files this rewriter must never examine. Checked before the file is read or parsed, so the
# rewriter is STRUCTURALLY incapable of touching them (spec 0.3, risk 6) rather than merely
# happening not to match them.
#
#   PfbTestModule.Tests.ps1 -- its raw `Import-Module -Name $script:manifest -Force -PassThru`
#   is not a redundant import, it is the fixture of the 'force-reimports after an unmarked
#   instance is installed by something else' test: it deliberately installs a module instance
#   carrying no prepared-marker so the test can prove Import-PfbTestModule notices and
#   rebuilds. Rewriting it to a helper call means no unmarked instance is ever installed and
#   the condition under test can never occur.
$script:ExcludedFileName = @(
    'PfbTestModule.Tests.ps1'
)

$dotSourceLine = ". (Join-Path `$PSScriptRoot 'PfbTestModule.ps1')"
$newlineChar = [char[]]@("`n", "`r")
$changed = @()
$excluded = @()
$unrecognised = @()
$unchanged = 0

# Parameters Import-PfbTestModule can stand in for. Anything else on the import (-Global,
# -ErrorAction Stop, -Scope, ...) has no equivalent in the emitted call, so the import goes
# to Unrecognised rather than being rewritten with the parameter silently dropped. Rejecting
# is the right direction: a spelling that would have rewritten cleanly now needs a human,
# whereas a dropped parameter changes behaviour with nothing on screen to say so.
$script:AllowedImportParameter = @('Force', 'PassThru', 'Name')

function Test-PfbSpliceStatementPosition {
    <#
        Is $Node itself in statement position -- i.e. would replacing its whole extent with
        two statements be legal? True only when its parent is a statement container, and
        never when that container is the body of an expression ($( ), @( ), ( )), where two
        spliced statements either fail to parse or silently discard the module.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Node)

    $parent = $Node.Parent
    $isStatementPosition =
        ($parent -is [System.Management.Automation.Language.StatementBlockAst]) -or
        ($parent -is [System.Management.Automation.Language.NamedBlockAst]) -or
        ($parent -is [System.Management.Automation.Language.ScriptBlockAst])
    if (-not $isStatementPosition) { return $false }

    if ($parent -is [System.Management.Automation.Language.StatementBlockAst]) {
        $grandparent = $parent.Parent
        if (($grandparent -is [System.Management.Automation.Language.SubExpressionAst]) -or
            ($grandparent -is [System.Management.Automation.Language.ArrayExpressionAst]) -or
            ($grandparent -is [System.Management.Automation.Language.ParenExpressionAst])) {
            return $false
        }
    }

    return $true
}

function Resolve-PfbImportSplice {
    <#
        Map an Import-Module CommandAst to the extent that should be replaced and the
        assignment target that should be emitted. Returns $null when the command sits in a
        syntactic position this rewriter does not model, which the caller turns into an
        Unrecognised record.

        Two modelled shapes, and only two:
          <indent>$target = Import-Module ...   -> replace the AssignmentStatementAst,
                                                   target = its Left extent text verbatim
          <indent>Import-Module ...             -> replace the PipelineAst, target = $null

        In BOTH arms the node whose extent will be replaced must itself be in statement
        position, checked identically by Test-PfbSpliceStatementPosition. Without that
        check `if ($m = Import-Module ... -PassThru) { }` emits a file that does not parse,
        and `$a = $b = ...` / `$m = $(...)` / `$m = @(...)` all parse but leave the caller's
        variable silently empty -- the exact failure class Unrecognised exists to prevent.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Command)

    foreach ($element in $Command.CommandElements) {
        if ($element -isnot [System.Management.Automation.Language.CommandParameterAst]) { continue }
        if ($script:AllowedImportParameter -notcontains $element.ParameterName) { return $null }
    }

    $pipeline = $Command.Parent
    if ($pipeline -isnot [System.Management.Automation.Language.PipelineAst]) { return $null }
    # A multi-element pipeline would put another command's extent inside the replaced node.
    if ($pipeline.PipelineElements.Count -ne 1) { return $null }

    $parent = $pipeline.Parent

    if ($parent -is [System.Management.Automation.Language.AssignmentStatementAst]) {
        # Only a plain `=`; a `+=` or `??=` around an import is not something to reproduce.
        if ($parent.Operator -ne [System.Management.Automation.Language.TokenKind]::Equals) { return $null }
        if (-not [object]::ReferenceEquals($parent.Right, $pipeline)) { return $null }
        if (-not (Test-PfbSpliceStatementPosition -Node $parent)) { return $null }
        return [PSCustomObject]@{
            StartOffset = $parent.Extent.StartOffset
            EndOffset   = $parent.Extent.EndOffset
            Target      = $parent.Left.Extent.Text
        }
    }

    if (-not (Test-PfbSpliceStatementPosition -Node $pipeline)) { return $null }

    return [PSCustomObject]@{
        StartOffset = $pipeline.Extent.StartOffset
        EndOffset   = $pipeline.Extent.EndOffset
        Target      = '$null'
    }
}

# Ordinal sort: 5.1 and 7 disagree on invariant linguistic order, so a culture-sensitive
# Sort-Object would make the reported order edition-dependent (issue #85 convention).
$filePath = [string[]]@(Get-ChildItem -Path $TestRoot -Filter '*.Tests.ps1' -File -Recurse |
    ForEach-Object { $_.FullName })
[Array]::Sort($filePath, [System.StringComparer]::Ordinal)

foreach ($path in $filePath) {
    $name = [System.IO.Path]::GetFileName($path)

    if ($script:ExcludedFileName -contains $name) {
        Write-Verbose ("Update-PfbTestModuleImport: {0} is on the exclusion list; not examined." -f $name)
        $excluded += $path
        continue
    }

    $content = [System.IO.File]::ReadAllText($path)
    $imports = @(Get-PfbTestManifestImport -Path $path)

    if ($imports.Count -eq 0) {
        $unchanged++
        continue
    }

    foreach ($item in @($imports | Where-Object { $_.Form -eq 'Unrecognised' })) {
        Write-Warning ("Update-PfbTestModuleImport: unrecognised manifest -Force import at {0}:{1} -- '{2}'. Not rewritten." -f
            $name, $item.Line, $item.Text)
        $unrecognised += [PSCustomObject]@{ File = $name; Line = $item.Line; Text = $item.Text }
    }

    # Re-walk the AST to recover each import's syntactic position. Get-PfbTestManifestImport
    # returns offsets, not nodes, and the enclosing assignment is what has to be replaced.
    $commandByOffset = @{}
    foreach ($command in (Get-PfbCommandAst -Ast (Get-PfbTestImportAst -Path $path))) {
        $commandByOffset[$command.Extent.StartOffset] = $command
    }

    $site = @()
    foreach ($item in @($imports | Where-Object { $_.Form -ne 'Unrecognised' })) {
        $command = $commandByOffset[$item.StartOffset]
        $splice = $null
        if ($null -ne $command) { $splice = Resolve-PfbImportSplice -Command $command }
        if ($null -eq $splice) {
            Write-Warning ("Update-PfbTestModuleImport: manifest -Force import at {0}:{1} is not a plain statement or assignment -- '{2}'. Not rewritten." -f
                $name, $item.Line, $item.Text)
            $unrecognised += [PSCustomObject]@{ File = $name; Line = $item.Line; Text = $item.Text }
            continue
        }
        $site += $splice
    }

    if ($site.Count -eq 0) {
        $unchanged++
        continue
    }

    # Detect from the file, not from [Environment]::NewLine: the platform does not decide
    # this, the checked-out file does. Only a fallback -- a site on line 1 has no preceding
    # terminator to copy.
    $nl = "`n"
    if ($content -match "`r`n") { $nl = "`r`n" }

    # Splice back-to-front so earlier offsets stay valid.
    $updated = $content
    foreach ($item in ($site | Sort-Object StartOffset -Descending)) {
        # Terminator-agnostic line start: LastIndexOf($nl, ...) skips lines ended with the
        # other convention, which recovers the indent of the wrong line in a mixed file.
        $lineStart = 0
        if ($item.StartOffset -gt 0) {
            $found = $updated.LastIndexOfAny($newlineChar, ($item.StartOffset - 1))
            if ($found -ge 0) { $lineStart = $found + 1 }
        }

        # The terminator that ends the PRECEDING line, so a mixed-ending file keeps its mix.
        $lineNl = $nl
        if ($lineStart -gt 0) {
            if ($updated[$lineStart - 1] -eq "`n" -and $lineStart -ge 2 -and $updated[$lineStart - 2] -eq "`r") {
                $lineNl = "`r`n"
            }
            else {
                $lineNl = [string]$updated[$lineStart - 1]
            }
        }

        # Indentation of the physical line the replaced node starts on, taken as characters
        # so tabs stay tabs.
        $indent = ''
        for ($i = $lineStart; $i -lt $item.StartOffset; $i++) {
            $ch = $updated[$i]
            if ($ch -ne ' ' -and $ch -ne "`t") { break }
            $indent += $ch
        }

        $replacement = $dotSourceLine + $lineNl + $indent + $item.Target + ' = Import-PfbTestModule'
        $head = $updated.Substring(0, $item.StartOffset)
        $tail = $updated.Substring($item.EndOffset)
        $updated = $head + $replacement + $tail
    }

    if ($updated -eq $content) {
        $unchanged++
        continue
    }

    $changed += $path
    if ($PSCmdlet.ShouldProcess($path, 'Rewrite manifest import to use Import-PfbTestModule')) {
        # WriteAllText with a BOM-less UTF8 encoding, not Set-Content: no test file has a
        # BOM, and Set-Content would append its own trailing newline.
        [System.IO.File]::WriteAllText($path, $updated, (New-Object System.Text.UTF8Encoding($false)))
    }
}

Write-Verbose ("Test-module imports: {0} changed, {1} already current, {2} excluded, {3} unrecognised (of {4} files)." -f
    $changed.Count, $unchanged, $excluded.Count, $unrecognised.Count, $filePath.Count)

[PSCustomObject]@{
    Changed      = $changed
    Unchanged    = $unchanged
    Excluded     = $excluded
    Unrecognised = $unrecognised
}
