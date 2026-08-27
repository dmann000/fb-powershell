#Requires -Version 7.0
<#
.SYNOPSIS
    Row-level regression gate for a change to the Public/ wire-name resolver: reports every
    inventory row whose resolution tuple moved, or vanished, between a git ref and the
    working tree -- and fails unless every move was declared in advance.
.DESCRIPTION
    A resolver change can WITHDRAW a resolution as easily as add one, and no total shows it.
    Issue #141 Task 3 raised the Typed count by 61 while silently demoting
    Update-PfbBucketAuditFilter -BucketName from a confident 'bucket_names' to unresolved;
    the only thing that caught it was a human diffing rows by hand in a code review. This
    script is that diff, made runnable and repeatable.

    Both sides are inventoried by their OWN copy of tools/lib/PfbCmdletParamTools.ps1, each in
    a separate child process, so the baseline is resolved by the baseline's resolver rather
    than re-resolved by the new one. Public/ is taken from each side too, so a ref that
    predates a cmdlet is not accused of losing it.

    Exit code is 0 when the comparison is clean and 1 otherwise, so this is usable as a gate
    in a script or a workflow step. "Clean" means: nothing removed, every changed tuple
    matched a declaration, and every declaration matched a change. Added rows never fail --
    a new cmdlet legitimately adds rows.
.PARAMETER RepoPath
    The repository (or worktree) to compare. Defaults to this script's parent.
.PARAMETER BaselineRef
    Any git ref resolvable in -RepoPath. Defaults to origin/main -- but a declaration file is
    only valid against the ref it was MEASURED at, so when -DeclarationPath is supplied and this
    parameter is not explicitly passed, the file's own `baselineRef` is used instead, and the
    resolved ref plus its provenance are printed. Passing -BaselineRef explicitly always wins,
    which is what keeps "compare these declarations against some other ref" possible.

    Getting this wrong is not a cosmetic failure. On a stacked branch, origin/main is not an
    ancestor of the ref the declarations were measured at, so every improvement made by the
    branches in between is reported as an undeclared change. The next maintainer then either
    concludes the tool is broken or pastes those rows in to silence it -- pre-authorising
    movement nobody reviewed, which is the anti-rubber-stamp rail running in reverse.
.PARAMETER DeclarationPath
    Optional JSON file. An OBJECT, not a bare array, with two required keys:

        {
          "baselineRef":  "<git ref the tuples below were measured against>",
          "declarations": [ { "key": "<Cmdlet>|<Parameter>", "from": "<tuple>", "to": "<tuple>" } ]
        }

    A tuple is 'Surface|WireName|WireSurface|Method|Endpoint' with $null rendered as the empty
    string -- exactly what this script prints for an undeclared change, so a reviewed change can
    be pasted straight in. A bare array is REFUSED rather than quietly accepted, because an array
    cannot carry the ref it was measured at and that omission is the defect described under
    -BaselineRef. tools/inventory-tuple-baselines/issue-141-task4.json is the worked example.

    RETIREMENT, and why it is a documented step rather than a softer rail. A declaration file
    describes a change that has not landed yet. Once its commits ARE the baseline, every entry
    matches nothing and IsClean goes false with one STALE-DECL per entry. That is correct: a
    declaration matching nothing is exactly what the unused-declaration rail exists to catch, and
    teaching the rail to tolerate the expected case would also teach it to tolerate the typo'd
    key it was built to find. So retire the file when the change merges -- move it to
    tools/inventory-tuple-baselines/landed/, which this script never reads. The record is kept,
    the gate stops firing, and nothing is pre-authorised for a future run.
.EXAMPLE
    # Normal use. The ref comes from the declaration file, so this is correct even on a stacked
    # branch whose base is not an ancestor of origin/main.
    ./tools/Compare-PfbInventoryTuple.ps1 `
        -DeclarationPath ./tools/inventory-tuple-baselines/issue-141-task4.json
.EXAMPLE
    # No declarations: report every row that moved against origin/main. Exits 1 if any did.
    ./tools/Compare-PfbInventoryTuple.ps1 -BaselineRef origin/main
#>
[CmdletBinding()]
param(
    [string]$RepoPath,
    [string]$BaselineRef = 'origin/main',
    [string]$DeclarationPath
)

$ErrorActionPreference = 'Stop'

$scriptDir = $PSScriptRoot
if (-not $RepoPath) { $RepoPath = Split-Path -Parent $scriptDir }
$RepoPath = (Resolve-Path -Path $RepoPath).Path

. (Join-Path $scriptDir 'lib/PfbCmdletParamTools.ps1')

# The dump runs in a child process against a tree chosen at runtime, so it cannot be a
# committed script inside that tree -- the baseline ref generally predates this file.
$dumpSource = @'
param([Parameter(Mandatory)][string]$TreePath)
$ErrorActionPreference = 'Stop'
. (Join-Path $TreePath 'tools/lib/PfbCmdletParamTools.ps1')
foreach ($row in (Get-PfbCmdletParameterInventory -PublicDirectory (Join-Path $TreePath 'Public'))) {
    # Double-quoted deliberately: this text is carried here inside a LITERAL here-string, so
    # the backtick escapes survive verbatim and are interpreted as tabs by the child, which is
    # the only separator guaranteed absent from a cmdlet name, wire key, method or endpoint.
    ("{0}`t{1}`t{2}`t{3}`t{4}`t{5}`t{6}" -f $row.Cmdlet, $row.Parameter, $row.Surface, $row.WireName, $row.WireSurface, $row.Method, $row.Endpoint)
}
'@

$hostExe = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName

# Windows ships bsdtar as %SystemRoot%\System32\tar.exe, but PATH order decides which `tar` a
# bare invocation gets, and under a pwsh launched from Git Bash it gets GNU tar. GNU tar parses
# the leading `C:` of the archive path as a REMOTE HOST spec and aborts with
# "Cannot connect to C: resolve failed", so the extraction fails on a machine where the identical
# command works from a native PowerShell. Resolve the Windows binary by absolute path instead of
# trusting PATH.
$tarExe = if ($IsWindows) { Join-Path $env:SystemRoot 'System32\tar.exe' } else { 'tar' }

# Declarations are read BEFORE the archive, because the file carries the ref the archive must be
# taken at. Reading it afterwards would mean resolving the baseline from a default that the file
# is about to contradict.
$declarations = @()
if ($DeclarationPath) {
    # -NoEnumerate matters: without it a ONE-element JSON array is unrolled by the pipeline into
    # a bare PSCustomObject, so the array check below silently misses the single-declaration case
    # and the file falls through to the less specific 'no baselineRef' error instead.
    $declarationFile = Get-Content -Path $DeclarationPath -Raw | ConvertFrom-Json -NoEnumerate
    if ($declarationFile -is [array]) {
        throw ("Declaration file '$DeclarationPath' is a bare array. It must be an object with " +
            "'baselineRef' and 'declarations' keys -- an array cannot record the ref its tuples " +
            'were measured against, and comparing them against the wrong ref reports every ' +
            'intervening improvement as an undeclared change.')
    }
    if ([string]::IsNullOrWhiteSpace([string]$declarationFile.baselineRef)) {
        throw "Declaration file '$DeclarationPath' has no 'baselineRef'. See .PARAMETER DeclarationPath."
    }
    $declarations = @($declarationFile.declarations | ForEach-Object {
            [PSCustomObject]@{ Key = $_.key; From = $_.from; To = $_.to }
        })

    # An explicit -BaselineRef always wins; otherwise the file's ref beats the parameter default.
    if (-not $PSBoundParameters.ContainsKey('BaselineRef')) {
        $BaselineRef = [string]$declarationFile.baselineRef
        $refSource = "declaration file"
    }
    else {
        $refSource = '-BaselineRef (explicit; overrides the declaration file''s {0})' -f $declarationFile.baselineRef
    }
}
if (-not $refSource) { $refSource = if ($PSBoundParameters.ContainsKey('BaselineRef')) { '-BaselineRef' } else { 'parameter default' } }

function Read-PfbTupleDump {
    param([string]$TreePath, [string]$DumpScript)

    $output = & $hostExe -NoProfile -NonInteractive -File $DumpScript -TreePath $TreePath
    if ($LASTEXITCODE -ne 0) { throw "Inventory dump failed for '$TreePath' (exit $LASTEXITCODE)." }

    $rows = foreach ($line in @($output)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $f = $line -split "`t", 7
        [PSCustomObject]@{
            Cmdlet      = $f[0]
            Parameter   = $f[1]
            Surface     = $f[2]
            WireName    = $f[3]
            WireSurface = $f[4]
            Method      = $f[5]
            Endpoint    = $f[6]
        }
    }
    return @($rows)
}

# Created here, not earlier: the only cleanup is the finally below, so anything thrown before
# this point must be thrown before there is a directory to leak. The declaration-validation
# throws above are exactly that case.
$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("pfb-tuple-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch -Force | Out-Null

try {
    $dumpScript = Join-Path $scratch 'Dump-PfbInventoryTuple.ps1'
    Set-Content -Path $dumpScript -Value $dumpSource -Encoding UTF8

    $baselineTree = Join-Path $scratch 'baseline'
    New-Item -ItemType Directory -Path $baselineTree -Force | Out-Null

    # git archive, not `git worktree add`: it materialises a detached snapshot of exactly the
    # two paths that matter without touching the repository's worktree list, so a failure
    # here cannot leave a registered worktree behind for someone to prune.
    $archive = Join-Path $scratch 'baseline.tar'
    & git -C $RepoPath archive --format=tar --output=$archive $BaselineRef tools Public
    if ($LASTEXITCODE -ne 0) { throw "git archive failed for ref '$BaselineRef' in '$RepoPath'." }
    & $tarExe -x -f $archive -C $baselineTree
    if ($LASTEXITCODE -ne 0) { throw "Extracting the baseline archive with '$tarExe' failed." }

    $baselineRows = Read-PfbTupleDump -TreePath $baselineTree -DumpScript $dumpScript
    $currentRows = Read-PfbTupleDump -TreePath $RepoPath -DumpScript $dumpScript

    $result = Compare-PfbInventoryTupleSet -Baseline $baselineRows -Current $currentRows -DeclaredChange $declarations

    Write-Host "baseline ref     : $BaselineRef  (from $refSource)"
    Write-Host "baseline rows    : $($baselineRows.Count)"
    Write-Host "current rows     : $($currentRows.Count)"
    Write-Host "declarations     : $($declarations.Count)"
    Write-Host "removed          : $($result.Removed.Count)"
    Write-Host "added            : $($result.Added.Count)"
    Write-Host "changed          : $($result.Changed.Count)"
    Write-Host "undeclared       : $($result.Undeclared.Count)"
    Write-Host "unused declaration: $($result.UnusedDeclaration.Count)"

    foreach ($key in $result.Removed) { Write-Host "REMOVED    $key" }
    foreach ($change in $result.Undeclared) { Write-Host "UNDECLARED $($change.Key)  $($change.From)  =>  $($change.To)" }
    foreach ($declaration in $result.UnusedDeclaration) { Write-Host "STALE-DECL $($declaration.Key)  $($declaration.From)  =>  $($declaration.To)" }

    # The one expected way to reach an all-stale run is to have already merged the change the
    # file declares. Say so here rather than leaving the reader to infer it, because the fix is
    # to retire the file and NOT to edit it into agreement with a tree it no longer describes.
    if ($declarations.Count -gt 0 -and $result.UnusedDeclaration.Count -eq $declarations.Count -and $result.Changed.Count -eq 0) {
        Write-Host ("NOTE: every declaration is stale and nothing moved, which is what a LANDED change looks like. " +
            "Retire this file -- move it to tools/inventory-tuple-baselines/landed/ -- rather than editing it.")
    }

    if ($result.IsClean) {
        Write-Host 'RESULT: CLEAN' -ForegroundColor Green
        exit 0
    }
    Write-Host 'RESULT: REGRESSION' -ForegroundColor Red
    exit 1
}
finally {
    Remove-Item -Path $scratch -Recurse -Force -ErrorAction SilentlyContinue
}
