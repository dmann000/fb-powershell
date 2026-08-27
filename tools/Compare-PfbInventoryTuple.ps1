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
    Any git ref resolvable in -RepoPath. Defaults to origin/main.
.PARAMETER DeclarationPath
    Optional JSON file: an array of { "key": "<Cmdlet>|<Parameter>", "from": "<tuple>",
    "to": "<tuple>" }, where a tuple is 'Surface|WireName|WireSurface|Method|Endpoint' with
    $null rendered as the empty string -- exactly what this script prints for an undeclared
    change, so a reviewed change can be pasted straight in.
    tools/inventory-tuple-baselines/issue-141-task4.json is the worked example.
.EXAMPLE
    ./tools/Compare-PfbInventoryTuple.ps1 -BaselineRef origin/main `
        -DeclarationPath ./tools/inventory-tuple-baselines/issue-141-task4.json
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
$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("pfb-tuple-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch -Force | Out-Null

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
    & tar -x -f $archive -C $baselineTree
    if ($LASTEXITCODE -ne 0) { throw "Extracting the baseline archive failed." }

    $baselineRows = Read-PfbTupleDump -TreePath $baselineTree -DumpScript $dumpScript
    $currentRows = Read-PfbTupleDump -TreePath $RepoPath -DumpScript $dumpScript

    $declarations = @()
    if ($DeclarationPath) {
        $declarations = @(Get-Content -Path $DeclarationPath -Raw | ConvertFrom-Json | ForEach-Object {
                [PSCustomObject]@{ Key = $_.key; From = $_.from; To = $_.to }
            })
    }

    $result = Compare-PfbInventoryTupleSet -Baseline $baselineRows -Current $currentRows -DeclaredChange $declarations

    Write-Host "baseline ref     : $BaselineRef"
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
