#Requires -Version 5.1
<#
.SYNOPSIS
    Reconciles drift-report findings with GitHub issues. Dry run unless -Apply is given.
.DESCRIPTION
    Reads Reports/PfbApiDriftReport.json, Reports/PfbDeadKeyReport.json and the
    '**Drift keys:**' fields in docs/settled/, lists every issue on -Repo (open and closed),
    and plans the writes that make the issues match the findings: create an issue per new
    group, append new findings to a group's open issue, note findings that stop being
    reported, and label an issue status:resolved-upstream when none of its findings
    remain. It prints the plan as a table. Only with -Apply does it write, and it never
    closes an issue.

    GitHub issues are the only state. Each drift issue ends with a machine block of HTML
    comments naming its group and the fingerprints it carries; the reconciler rewrites only
    that block, and posts a visible comment whenever it changes it. There is no baseline
    file to keep in sync. A block counts only on an issue labelled source:drift, which only
    collaborators can apply; on anyone else's issue it is ignored (and named in a warning).

    All the decisions are in tools/lib/PfbDriftIssueTools.ps1, which is pure and tested
    against fixtures (Tests/PfbDriftIssueTools.Tests.ps1). This file owns the reads, the
    writes and the output (Tests/New-PfbDriftIssue.Tests.ps1 runs it against a fake gh).

    A CONTROL BEFORE ANY WRITE. With -Apply, every label the plan will add is checked
    against the repository's label list first, and a missing one stops the run before
    anything is written -- gh would otherwise fail halfway through, after some issues were
    already created.

    WHY gh, WHEN scripts/Assert-PfbAgentReadyBrief.ps1 AVOIDS IT. That script only reads a
    public repository, where Invoke-RestMethod needs no identity. This one writes, and on
    a workstation the right identity comes from ghx, the per-repository wrapper that reads
    this clone's pinned account; in Actions, gh is preinstalled and reads GH_TOKEN.

.PARAMETER Apply
    Make the planned writes. Without it nothing is written.
.PARAMETER MaxCreate
    At most this many new issues per run, most severe groups first. The rest are listed as
    queued and filed by later runs. Default 10; 0 creates none.
.PARAMETER Repo
    owner/name. Default dmann000/fb-powershell.
.PARAMETER GhCommand
    The gh executable. Default gh; on a workstation pass ghx, so the repository's pinned
    identity is used and gh auth switch is never needed.
.PARAMETER AcceptMassVanish
    Proceed even when more than 25% of the fingerprints recorded in open issues would stop
    being reported in one run. That guard exists because a spec restructuring looks like a
    burst of fixes; pass this only after checking the reports and deciding it is real.
.PARAMETER PassThru
    Also emit an object carrying the findings, the parsed issues, the settled keys and the
    plan -- the input a pairing pass needs, and what the tests inspect.
.PARAMETER DriftReportPath
    Default Reports/PfbApiDriftReport.json.
.PARAMETER DeadKeyReportPath
    Default Reports/PfbDeadKeyReport.json.
.PARAMETER SettledDirectory
    Default docs/settled. Every *.md except README.md is read for Drift keys.
.EXAMPLE
    ./tools/New-PfbDriftIssue.ps1 -GhCommand ghx
    Prints what a run would do against the upstream repository, and writes nothing.
.EXAMPLE
    ./tools/New-PfbDriftIssue.ps1 -GhCommand ghx -Apply
    Makes the writes the dry run printed.
#>
[CmdletBinding()]
param(
    [switch]$Apply,
    [ValidateRange(0, 100)][int]$MaxCreate = 10,
    [ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')][string]$Repo = 'dmann000/fb-powershell',
    [ValidateNotNullOrEmpty()][string]$GhCommand = 'gh',
    [switch]$AcceptMassVanish,
    [switch]$PassThru,
    [string]$DriftReportPath,
    [string]$DeadKeyReportPath,
    [string]$SettledDirectory
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path (Join-Path $PSScriptRoot 'lib') 'PfbDriftIssueTools.ps1')

if (-not $DriftReportPath) { $DriftReportPath = Join-Path (Join-Path $repoRoot 'Reports') 'PfbApiDriftReport.json' }
if (-not $DeadKeyReportPath) { $DeadKeyReportPath = Join-Path (Join-Path $repoRoot 'Reports') 'PfbDeadKeyReport.json' }
if (-not $SettledDirectory) { $SettledDirectory = Join-Path (Join-Path $repoRoot 'docs') 'settled' }

$issueLimit = 1000
$utf8NoBom = New-Object System.Text.UTF8Encoding $false

function Invoke-PfbDriftGh {
    <#
        One gh call. Returns stdout as one string; throws on a non-zero exit.

        Three things here are load-bearing:
        - Arguments go as an array, one flag or value per element. A comma list such as the
          --json field list must be ONE element: PowerShell hands a bare a,b,c to a native
          command as three arguments.
        - stdout is decoded as UTF-8 for the duration of the call. Issue bodies carry
          non-ASCII text, and this script writes bodies back: decoding them in a legacy
          console code page would rewrite a person's em dashes as mojibake on github.com.
        - The call runs from the repository root, because ghx resolves the pinned account
          from the .git/config of the CURRENT directory.
    #>
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    $previousEncoding = [Console]::OutputEncoding
    Push-Location -LiteralPath $repoRoot
    try {
        try { [Console]::OutputEncoding = $utf8NoBom }
        catch { Write-Verbose "Could not set the console output encoding: $($_.Exception.Message)" }
        $output = & $GhCommand @Arguments
        $exitCode = $LASTEXITCODE
    }
    finally {
        try { [Console]::OutputEncoding = $previousEncoding }
        catch { Write-Verbose "Could not restore the console output encoding: $($_.Exception.Message)" }
        Pop-Location
    }
    if ($exitCode -ne 0) { throw "$GhCommand $($Arguments[0]) $($Arguments[1]) failed with exit code $exitCode." }
    return (@($output) -join "`n")
}

function Invoke-PfbDriftGhWithBody {
    <#
        A gh write whose text goes through --body-file, never through argv. Bodies are
        multi-line markdown, and ghx is a .cmd shim: cmd.exe would reinterpret %, ^, &, |
        and newlines in an argument. The file is UTF-8 WITHOUT a byte-order mark; Windows
        PowerShell 5.1's Set-Content and Out-File write one, and gh would post it as a
        leading U+FEFF.
    #>
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$Text
    )

    $path = [System.IO.Path]::GetTempFileName()
    try {
        [System.IO.File]::WriteAllText($path, $Text, $utf8NoBom)
        return (Invoke-PfbDriftGh -Arguments (@($Arguments) + @('--body-file', $path)))
    }
    finally {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
}

function Read-PfbDriftJson {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Description
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Description not found at $Path." }
    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function ConvertFrom-PfbDriftGhJson {
    <#
        gh's JSON array, as a flat array of records.

        THE ASSIGNMENT IS LOAD-BEARING, for the reason scripts/Assert-PfbAgentReadyBrief.ps1
        records: Windows PowerShell 5.1's ConvertFrom-Json writes a JSON array to the
        pipeline as ONE object, so @($json | ConvertFrom-Json) is a one-element array whose
        element is the whole array. Assigning first and then unrolling flattens it. The
        check below turns the nested shape into a named failure instead of a silent one.
    #>
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Json, [Parameter(Mandatory = $true)][string]$Description)

    if ([string]::IsNullOrWhiteSpace($Json)) { throw "$Description returned nothing; expected a JSON array." }
    $parsed = $Json | ConvertFrom-Json
    $records = @(Get-PfbDriftItem $parsed)
    foreach ($record in $records) {
        if ($record -is [System.Collections.IEnumerable] -and $record -isnot [string]) {
            throw "$Description came back nested: an element is a collection rather than a record."
        }
    }
    return $records
}

if (-not (Get-Command -Name $GhCommand -ErrorAction SilentlyContinue)) {
    throw "'$GhCommand' is not on PATH. In Actions the runner provides gh; on a workstation pass -GhCommand ghx (this repository pins its GitHub identity, and bare gh may authenticate as the other account)."
}

# --- read ---
$driftReport = Read-PfbDriftJson -Path $DriftReportPath -Description 'The drift report'
$deadKeyReport = Read-PfbDriftJson -Path $DeadKeyReportPath -Description 'The dead-key report'
if (-not (Test-Path -LiteralPath $SettledDirectory -PathType Container)) {
    throw "The settled directory was not found at $SettledDirectory. The reconciler reads it before filing anything, so a declined finding is never filed again."
}

$settledKeys = @()
$settledNames = @(Get-ChildItem -LiteralPath $SettledDirectory -Filter '*.md' -File |
        Where-Object { $_.Name -cne 'README.md' } | ForEach-Object { $_.Name })
foreach ($name in @(Get-PfbDriftSortedString -Value $settledNames)) {
    $text = [string](Get-Content -LiteralPath (Join-Path $SettledDirectory $name) -Raw -Encoding UTF8)
    $settledKeys += @(ConvertFrom-PfbSettledDriftKey -Text $text -Source $name)
}

$findings = @(Get-PfbDriftFinding -DriftReport $driftReport -DeadKeyReport $deadKeyReport)
$sourceNote = 'Reports/PfbApiDriftReport.json (REST through {0}) and Reports/PfbDeadKeyReport.json (REST {1})' -f @($driftReport.analysedVersions)[-1], $deadKeyReport.specVersion

$issueJson = Invoke-PfbDriftGh -Arguments @('issue', 'list', '--repo', $Repo, '--state', 'all', '--limit', [string]$issueLimit, '--json', 'number,title,body,state,stateReason,labels')
$rawIssues = @(ConvertFrom-PfbDriftGhJson -Json $issueJson -Description 'gh issue list')
if ($rawIssues.Count -ge $issueLimit) {
    throw "gh issue list returned $($rawIssues.Count) issues, the --limit, so there may be more; planning against a truncated list could re-file a declined finding. Raise the limit in this script."
}
$issues = @(ConvertFrom-PfbDriftIssue -Issue $rawIssues)

$labelJson = Invoke-PfbDriftGh -Arguments @('label', 'list', '--repo', $Repo, '--limit', '1000', '--json', 'name')
$existingLabels = @(@(ConvertFrom-PfbDriftGhJson -Json $labelJson -Description 'gh label list') | ForEach-Object { [string]$_.name })

# --- plan ---
$plan = Get-PfbDriftPlan -Finding $findings -Issue $issues -SettledKey $settledKeys -MaxCreate $MaxCreate `
    -AcceptMassVanish:$AcceptMassVanish -SourceNote $sourceNote

$mode = 'DRY RUN'
if ($Apply) { $mode = 'APPLY' }
$stamped = @($issues | Where-Object { $null -ne $_.Marker }).Count
$ignored = @($issues | Where-Object { $_.IgnoredBlock } | ForEach-Object { '#' + $_.Number })
Write-Host "$mode against ${Repo}: $($findings.Count) finding(s); $($issues.Count) issue(s) read, $stamped with a trusted pfb-drift block, $($ignored.Count) untrusted block(s) ignored; $($settledKeys.Count) settled key(s)."
if ($ignored.Count -gt 0) {
    # Not an error: an untrusted block changes nothing, so it must not be able to stop a run.
    # Said out loud because a drift issue that LOST its source:drift label lands here too, and
    # its findings would then be filed again as new.
    Write-Warning "Ignored the pfb-drift block on $($ignored -join ', '): a block counts only on an issue labelled $($script:PfbDriftLabel.Source)."
}

if ($plan.Aborted) {
    if ($env:GITHUB_STEP_SUMMARY) {
        [System.IO.File]::AppendAllText($env:GITHUB_STEP_SUMMARY, "### Drift issues: aborted`n`n$($plan.AbortReason)`n", $utf8NoBom)
    }
    throw "Restructure guard: $($plan.AbortReason)"
}

$actions = @($plan.Actions)
$rows = @($actions | ForEach-Object {
        $issueText = ''
        if ($null -ne $_.IssueNumber) { $issueText = "#$($_.IssueNumber)" }
        [PSCustomObject]@{ Group = $_.GroupKey; Action = $_.Action; Issue = $issueText; FPs = @($_.Fingerprints).Count; Reason = $_.Reason }
    })
if ($rows.Count -gt 0) { Write-Host ($rows | Format-Table -AutoSize | Out-String -Width 240) }
$count = @{}
foreach ($name in 'Create', 'Comment', 'MarkResolved', 'Skip') { $count[$name] = @($actions | Where-Object { $_.Action -ceq $name }).Count }
Write-Host ("Already tracked: {0}. Create: {1} (cap {2}). Comment: {3}. MarkResolved: {4}. Skip: {5}." -f $plan.TrackedCount, $count['Create'], $MaxCreate, $count['Comment'], $count['MarkResolved'], $count['Skip'])

if ($env:GITHUB_STEP_SUMMARY) {
    $summary = [System.Collections.Generic.List[string]]::new()
    $summary.Add("### Drift issues ($mode)")
    $summary.Add('')
    $summary.Add('| Group | Action | Issue | FPs | Reason |')
    $summary.Add('|---|---|---|---|---|')
    foreach ($row in $rows) { $summary.Add("| $($row.Group) | $($row.Action) | $($row.Issue) | $($row.FPs) | $($row.Reason -replace '\|', '\|') |") }
    [System.IO.File]::AppendAllText($env:GITHUB_STEP_SUMMARY, (($summary -join "`n") + "`n"), $utf8NoBom)
}

# --- the control: every label the plan adds must already exist ---
$needed = @(Get-PfbDriftSortedString -Value @($actions | ForEach-Object { @($_.AddLabels) }))
$missingLabels = @($needed | Where-Object { $existingLabels -cnotcontains $_ })
if ($missingLabels.Count -gt 0) {
    $message = "$Repo has no label(s) $($missingLabels -join ', '). Provision them (the G1 label taxonomy) before applying."
    if ($Apply) { throw "$message Nothing was written." }
    Write-Warning $message
}

# --- write ---
if (-not $Apply) {
    Write-Host 'DRY RUN: nothing was written. Re-run with -Apply to make these changes.'
}
else {
    foreach ($action in $actions) {
        if ($action.Action -ceq 'Create') {
            $ghArguments = @('issue', 'create', '--repo', $Repo, '--title', $action.Title)
            foreach ($label in @($action.AddLabels)) { $ghArguments += @('--label', $label) }
            $url = Invoke-PfbDriftGhWithBody -Arguments $ghArguments -Text $action.Body
            if (-not ($url -match '/issues/(?<number>\d+)\s*$')) { throw "gh issue create did not return an issue URL: $url" }
            Write-Host "  created #$($Matches['number']) for $($action.GroupKey)"
        }
        elseif ($action.Action -ceq 'Comment' -or $action.Action -ceq 'MarkResolved') {
            $number = [string]$action.IssueNumber
            # The machine block first: it is the state. If the comment then fails, the next
            # run sees the change as already made and says nothing twice. If the label call
            # fails, the next run derives the status: label from the block again and plans
            # the fix on its own. A label-only fix has no Body, so there is no edit to make.
            if (-not [string]::IsNullOrEmpty($action.Body)) {
                $null = Invoke-PfbDriftGhWithBody -Arguments @('issue', 'edit', $number, '--repo', $Repo) -Text $action.Body
            }
            $null = Invoke-PfbDriftGhWithBody -Arguments @('issue', 'comment', $number, '--repo', $Repo) -Text $action.Comment
            if (@($action.AddLabels).Count -gt 0 -or @($action.RemoveLabels).Count -gt 0) {
                $labelArguments = @('issue', 'edit', $number, '--repo', $Repo)
                foreach ($label in @($action.AddLabels)) { $labelArguments += @('--add-label', $label) }
                foreach ($label in @($action.RemoveLabels)) { $labelArguments += @('--remove-label', $label) }
                $null = Invoke-PfbDriftGh -Arguments $labelArguments
            }
            Write-Host "  updated #$number ($($action.Reason))"
        }
    }
    Write-Host 'APPLY: done.'
}

if ($PassThru) {
    [PSCustomObject]@{
        Findings    = $findings
        Issues      = $issues
        SettledKeys = $settledKeys
        Plan        = $plan
    }
}
