#Requires -Version 7.0

<#
.SYNOPSIS
    Decides whether a diff can change what this module sends to, or parses from, a FlashBlade.
.DESCRIPTION
    Changes that can alter a request the module sends or a response it parses are verified
    against a real FlashBlade before they merge, because mocked tests encode our belief about
    the REST API rather than the API itself. This script decides, mechanically, whether a
    diff is exempt from that: it is exempt when no EXECUTABLE line changed in any of

        Public/   Private/   PureStorageFlashBladePowerShell.psd1   PureStorageFlashBladePowerShell.psm1

    "Executable" is decided by the PowerShell tokeniser, not by eye and not by regex. A
    changed line is inert only when every token overlapping it is a comment. That is
    deliberately STRICTER than "reaches the wire": an executable change that provably cannot
    reach the wire (adding a Write-Verbose, renaming a local) still counts, because erring
    toward a live check is the recoverable direction.

    Why the tokeniser and not a regex: a '#' inside a here-string, and a string literal
    containing '<#', both defeat text matching. The tokeniser resolves them.

    #Requires tokenises as a Comment yet still populates ScriptRequirements, so it changes
    what the module loads under. It is forced to executable here.

    A comment reworded on a line that also holds code counts as executable: git is
    line-granular, so that edit cannot be told apart from a code edit.

    Both sides of the diff are parsed. Deleted lines do not exist at -HeadRef, so they are
    classified against the merge-base revision of the file. An added, deleted or renamed
    in-scope file is never inert.

    The script only runs `git` and tokenises blobs. It never executes code from the diff, so
    it is safe to run against an untrusted pull request.

    TRUSTING THE VERDICT. A pull_request CI run executes the workflow file from the PR's own
    merge commit, so a PR that edits that workflow controls what the CI job prints. Nothing
    may gate on the CI job's conclusion or its summary. A gate that needs this verdict
    recomputes it outside the PR's control:

        git fetch origin
        git show origin/main:tools/Test-PfbWireExemption.ps1 > <temp>/Test-PfbWireExemption.ps1
        <temp>/Test-PfbWireExemption.ps1 -RepoPath <clone> -BaseRef <main tip SHA> -HeadRef <PR head SHA>

    It uses the main TIP (not pull_request.base.sha, which can be stale), passes both SHAs
    explicitly, and branches on the returned Decision. It never reads a check conclusion or a
    job summary.
.PARAMETER BaseRef
    Revision to diff against. Default 'origin/main'. The comparison is three-dot (from the
    merge-base of -BaseRef and -HeadRef).
.PARAMETER HeadRef
    Revision to classify. Default 'HEAD'. Need not be checked out.
.PARAMETER RepoPath
    Repository or worktree to inspect. Defaults to the current directory.
.OUTPUTS
    Exactly one object: Decision ('Exempt' | 'NotExempt' | 'Undecided'); Files, one record
    per in-scope file (Path, Verdict 'Inert' | 'Executable', FirstExecutableLine, Reason);
    Basis, a line ready to paste into the PR body, or $null unless exempt. Everything
    human-readable goes to Write-Host.

    Exit code 0 = exempt, 1 = not exempt, 2 = could not decide (treat as not exempt).
.EXAMPLE
    ./tools/Test-PfbWireExemption.ps1 -BaseRef origin/main
.EXAMPLE
    $v = ./tools/Test-PfbWireExemption.ps1 -BaseRef $baseSha -HeadRef $headSha 6>$null
    if ($v.Decision -ne 'Exempt') { 'live verification required' }
#>
[CmdletBinding()]
param(
    [string]$BaseRef = 'origin/main',
    [string]$HeadRef = 'HEAD',
    [string]$RepoPath = '.'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# The four in-scope locations, verbatim from the rule.
$script:ScopePrefixes = @('Public/', 'Private/')
$script:ScopeExact = @(
    'PureStorageFlashBladePowerShell.psd1',
    'PureStorageFlashBladePowerShell.psm1'
)

function Test-InScope {
    param([string]$Path)
    foreach ($p in $script:ScopePrefixes) { if ($Path.StartsWith($p)) { return $true } }
    return ($script:ScopeExact -contains $Path)
}

function Invoke-Git {
    param([string[]]$Arguments, [switch]$AllowFailure)
    $out = & git -C $RepoPath @Arguments 2>&1
    if ($LASTEXITCODE -ne 0 -and -not $AllowFailure) {
        throw "git $($Arguments -join ' ') failed: $out"
    }
    return $out
}

# Lines carrying any token that is not a comment. Everything else -- blank lines,
# whole-line comments, help blocks -- is inert.
#
# A line with a trailing comment ('$x = 1  # note') counts as EXECUTABLE, because
# git is line-granular: we cannot tell a comment-only edit on that line from a
# code edit, so we must assume the latter.
function Get-ExecutableLine {
    param([string]$Source)

    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($Source, [ref]$tokens, [ref]$errors)

    if ($errors -and $errors.Count -gt 0) {
        throw "source does not parse: $($errors[0].Message)"
    }

    $executable = New-Object 'System.Collections.Generic.HashSet[int]'
    foreach ($t in $tokens) {
        $kind = $t.Kind.ToString()
        if ($kind -eq 'NewLine' -or $kind -eq 'EndOfInput' -or $kind -eq 'LineContinuation') { continue }

        $isInert = $false
        if ($kind -eq 'Comment') {
            $isInert = $true
            # #Requires is a Comment token that changes load behaviour. Not inert.
            if ($t.Text -match '^\s*#\s*requires\b') { $isInert = $false }
        }
        if ($isInert) { continue }

        for ($n = $t.Extent.StartLineNumber; $n -le $t.Extent.EndLineNumber; $n++) {
            [void]$executable.Add($n)
        }
    }
    # Comma operator is load-bearing: a bare 'return $executable' unrolls the set
    # into the pipeline, and a single-element set collapses to a bare [int] whose
    # .Contains() then throws. Cost an hour once.
    return ,$executable
}

# Changed line numbers per side, from a -U0 diff of one file.
function Get-ChangedLine {
    param([string]$Path, [string]$Base, [string]$Head)

    $added = New-Object 'System.Collections.Generic.List[int]'
    $removed = New-Object 'System.Collections.Generic.List[int]'

    $diff = Invoke-Git @('diff', '-U0', '--no-color', "$Base..$Head", '--', $Path)
    foreach ($line in $diff) {
        if ($line -notmatch '^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@') { continue }

        $oldStart = [int]$Matches[1]
        $oldCount = 1
        if ($Matches[2]) { $oldCount = [int]$Matches[2] }
        $newStart = [int]$Matches[3]
        $newCount = 1
        if ($Matches[4]) { $newCount = [int]$Matches[4] }

        for ($n = 0; $n -lt $oldCount; $n++) { $removed.Add($oldStart + $n) }
        for ($n = 0; $n -lt $newCount; $n++) { $added.Add($newStart + $n) }
    }
    return @{ Added = $added; Removed = $removed }
}

function Get-Blob {
    param([string]$Rev, [string]$Path)
    $content = Invoke-Git @('show', "${Rev}:${Path}") -AllowFailure
    if ($LASTEXITCODE -ne 0) { return $null }
    return ($content -join "`n")
}

# The ONE object this script puts on the success stream. Everything human-readable goes
# through Write-Host, so a caller can do `$v = & ./tools/Test-PfbWireExemption.ps1 ...` and
# branch on $v.Decision without filtering text out of it.
function New-PfbWireVerdict {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Constructs an in-memory object; changes no state.')]
    param([string]$Decision, [object[]]$Files = @(), [string]$Basis = '')
    $b = $null
    if ($Basis) { $b = $Basis }
    [pscustomobject]@{ Decision = $Decision; Files = @($Files); Basis = $b }
}

# --- resolve revisions -------------------------------------------------------

try {
    $head = ([string](Invoke-Git @('rev-parse', '--verify', "$HeadRef^{commit}"))).Trim()
    $mergeBase = ([string](Invoke-Git @('merge-base', $BaseRef, $head))).Trim()
} catch {
    Write-Host "Could not resolve revisions: $_" -ForegroundColor Red
    New-PfbWireVerdict -Decision 'Undecided'
    exit 2
}

Write-Host ""
Write-Host "base  $BaseRef @ $($mergeBase.Substring(0,10))"
Write-Host "head  $HeadRef @ $($head.Substring(0,10))"
Write-Host ""

# --- collect in-scope changes ------------------------------------------------

$nameStatus = Invoke-Git @('diff', '--name-status', '--no-color', "$mergeBase..$head")

$inScope = @()
foreach ($line in $nameStatus) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $parts = $line -split "`t"
    $status = $parts[0]
    $path = $parts[-1]
    if (-not (Test-InScope $path)) { continue }
    $inScope += [pscustomobject]@{ Status = $status; Path = $path }
}

if ($inScope.Count -eq 0) {
    Write-Host "No in-scope file changed." -ForegroundColor Green
    Write-Host ""
    Write-Host "VERDICT: EXEMPT" -ForegroundColor Green
    Write-Host ""
    # States what the diff does not touch; names no tooling, so it reads correctly in any PR body.
    Write-Host "Basis for the PR body:"
    Write-Host "  The diff leaves the module source and the manifest entirely untouched,"
    Write-Host "  so nothing here can alter a request the module sends or a response it"
    Write-Host "  parses."
    New-PfbWireVerdict -Decision 'Exempt' -Basis 'The diff leaves the module source and the manifest entirely untouched, so nothing here can alter a request the module sends or a response it parses.'
    exit 0
}

# --- classify ----------------------------------------------------------------

$verdicts = @()
$failed = $false

foreach ($file in $inScope) {
    $path = $file.Path
    $reasons = @()
    # First executable changed line: head side if any, else base side. $null when the file
    # is inert or was rejected as a whole (added, deleted, renamed).
    $firstLine = $null

    # An added or deleted file changes the exported surface. Never inert.
    if ($file.Status -eq 'A') { $reasons += 'file added' }
    elseif ($file.Status -eq 'D') { $reasons += 'file deleted' }
    elseif ($file.Status -like 'R*') { $reasons += "file renamed ($($file.Status))" }
    else {
        $changed = Get-ChangedLine -Path $path -Base $mergeBase -Head $head

        if ($changed.Added.Count -gt 0) {
            $headSource = Get-Blob -Rev $head -Path $path
            if ($null -eq $headSource) {
                $reasons += 'could not read head blob'
            } else {
                try {
                    $exec = Get-ExecutableLine -Source $headSource
                    $hits = @($changed.Added | Where-Object { $exec.Contains($_) } | Sort-Object -Unique)
                    if ($hits.Count -gt 0) { $firstLine = [int]$hits[0] }
                    if ($hits.Count -gt 0) {
                        $shown = ($hits | Select-Object -First 6) -join ', '
                        $suffix = ''
                        if ($hits.Count -gt 6) { $suffix = " (+$($hits.Count - 6) more)" }
                        $reasons += "executable line(s) added: $shown$suffix"
                    }
                } catch { $reasons += "head side: $_" }
            }
        }

        if ($changed.Removed.Count -gt 0) {
            $baseSource = Get-Blob -Rev $mergeBase -Path $path
            if ($null -eq $baseSource) {
                $reasons += 'could not read base blob'
            } else {
                try {
                    $exec = Get-ExecutableLine -Source $baseSource
                    $hits = @($changed.Removed | Where-Object { $exec.Contains($_) } | Sort-Object -Unique)
                    if ($hits.Count -gt 0 -and $null -eq $firstLine) { $firstLine = [int]$hits[0] }
                    if ($hits.Count -gt 0) {
                        $shown = ($hits | Select-Object -First 6) -join ', '
                        $suffix = ''
                        if ($hits.Count -gt 6) { $suffix = " (+$($hits.Count - 6) more)" }
                        $reasons += "executable line(s) removed: $shown$suffix"
                    }
                } catch { $reasons += "base side: $_" }
            }
        }
    }

    $isInert = ($reasons.Count -eq 0)
    if (-not $isInert) { $failed = $true }

    $verdicts += [pscustomobject]@{
        Path                = $path
        Verdict             = $(if ($isInert) { 'Inert' } else { 'Executable' })
        FirstExecutableLine = $firstLine
        Reason              = $(if ($isInert) { 'comment-only' } else { $reasons -join '; ' })
    }
}

# --- report ------------------------------------------------------------------

Write-Host "In-scope files changed: $($inScope.Count)"
Write-Host ""
foreach ($v in $verdicts) {
    if ($v.Verdict -eq 'Inert') {
        Write-Host ("  inert      {0}" -f $v.Path) -ForegroundColor Green
    } else {
        Write-Host ("  EXECUTABLE {0}" -f $v.Path) -ForegroundColor Red
        Write-Host ("             {0}" -f $v.Reason) -ForegroundColor Red
    }
}
Write-Host ""

if ($failed) {
    Write-Host "VERDICT: NOT EXEMPT -- live verification required" -ForegroundColor Red
    Write-Host ""
    Write-Host "One executable line anywhere in scope disqualifies the whole PR."
    Write-Host "There is no partial exemption."
    New-PfbWireVerdict -Decision 'NotExempt' -Files $verdicts
    exit 1
}

Write-Host "VERDICT: EXEMPT" -ForegroundColor Green
Write-Host ""
# The basis line states the substance -- what did and did not change -- so it can be pasted into a PR body as-is.
Write-Host "Basis for the PR body:"
Write-Host "  Every in-scope change is inside a comment -- no executable line changed in"
Write-Host "  the module source or the manifest, confirmed by comparing the parsed token"
Write-Host "  stream on both sides of the diff."
New-PfbWireVerdict -Decision 'Exempt' -Files $verdicts -Basis 'Every in-scope change is inside a comment -- no executable line changed in the module source or the manifest, confirmed by comparing the parsed token stream on both sides of the diff.'
exit 0
