#Requires -Version 5.1
<#
.SYNOPSIS
    Fails when a status:agent-ready issue does not carry an agent brief.
.DESCRIPTION
    docs/TRIAGE-ROLES.md defines `status:agent-ready` as "a brief is attached", not "this
    issue looks small". Nothing enforced that, and when the taxonomy was first applied,
    writing briefs against the five labelled issues demoted three of them -- the label was
    60% wrong and no check in the repo could say so. A scheduled worker pops from that
    label, so an unbriefed issue there costs a wasted unattended run. This asserts the
    label's promise.

    The decision logic is in tools/lib/PfbAgentBriefTools.ps1 and is pure text
    classification, so it is tested against fixtures with no network and no token
    (Tests/PfbAgentBriefTools.Tests.ps1). This file owns only the fetch, the reporting and
    the exit code.

    A CONTROL, BECAUSE A FILTERED QUERY RETURNING ZERO LOOKS LIKE SUCCESS. The natural
    implementation asks for issues carrying the label and passes when none come back. That
    is indistinguishable from a renamed label, a typo in the filter, a revoked token scope
    or an API change -- all of which report a clean build forever. So the label itself is
    fetched first and its absence is a failure, not a pass. This repo has already filed one
    wrong public issue by trusting an unaccompanied empty result.

    NOT A PR GATE. It asks a question about repository state, not about a diff, so there is
    no pull request on which it is the right answer and nothing a contributor could do to
    their branch to fix a red. It runs on a schedule and on workflow_dispatch.

    WHY `gh` AND NOT `ghx`. `ghx` is a local wrapper that resolves which of two stored
    accounts a repository belongs to; it does not exist on a runner, where GH_TOKEN is
    supplied by Actions and `gh` is the only client. To run this by hand against the real
    repository, fetch with ghx and pass the result to -InputPath rather than reaching for
    `gh` locally:

        ghx api "repos/dmann000/fb-powershell/issues?state=open&per_page=100" --paginate \
            --jq '[.[] | select(.pull_request == null)]' > issues.json
        # then add comments per issue, or just run the script with -Repository and a token

.PARAMETER Repository
    owner/name. Defaults to GITHUB_REPOSITORY when Actions supplies it, else the upstream.
.PARAMETER InputPath
    A JSON file of pre-fetched issues, for a local run or a dry run. Each element needs
    `number`, `title`, `labels` (objects with `name`, or bare strings) and `comments` (an
    array of bodies, or of objects with `body`). Skips all network access and, with it, the
    label control -- an offline run cannot verify the label still exists upstream.
.PARAMETER Quiet
    Suppress the per-issue pass lines. Violations and the summary still print.
.EXAMPLE
    ./scripts/Assert-PfbAgentReadyBrief.ps1
    Fetches from the upstream repository and exits non-zero on the first violation found.
#>
[CmdletBinding()]
param(
    [string]$Repository,
    [string]$InputPath,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'tools/lib/PfbAgentBriefTools.ps1')

$agentReadyLabel = 'status:agent-ready'

function Invoke-PfbGhJson {
    <#
        `gh api` with the two failure modes that otherwise read as an empty result: gh
        absent from PATH, and a non-zero exit whose stderr would otherwise be discarded by
        ConvertFrom-Json choking on an empty string.
    #>
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Get-Command -Name 'gh' -ErrorAction SilentlyContinue)) {
        throw "The GitHub CLI (gh) is not on PATH, so issue state cannot be read. On a runner this means the step is missing its setup; locally, pre-fetch with ghx and use -InputPath."
    }

    $raw = & gh api $Path 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "gh api $Path failed with exit code $LASTEXITCODE`: $($raw -join [Environment]::NewLine)"
    }
    return ($raw -join [Environment]::NewLine) | ConvertFrom-Json
}

function ConvertTo-PfbNormalisedIssue {
    <#
        One shape for the classifier regardless of where the data came from, because the
        API's label objects and a hand-written fixture's bare strings are both reasonable
        and the classifier should not have to know which it has.
    #>
    param([Parameter(Mandatory = $true)]$Raw)

    $labelNames = @()
    foreach ($label in @($Raw.labels)) {
        if ($null -eq $label) { continue }
        if ($label -is [string]) { $labelNames += $label; continue }
        if ($label.PSObject.Properties.Name -contains 'name') { $labelNames += [string]$label.name }
    }

    $commentBodies = @()
    foreach ($comment in @($Raw.comments)) {
        if ($null -eq $comment) { continue }
        if ($comment -is [string]) { $commentBodies += $comment; continue }
        if ($comment.PSObject.Properties.Name -contains 'body') { $commentBodies += [string]$comment.body }
    }

    return [PSCustomObject]@{
        Number   = [int]$Raw.number
        Title    = [string]$Raw.title
        Labels   = $labelNames
        Comments = $commentBodies
    }
}

# ---------------------------------------------------------------------------------------
# Gather
# ---------------------------------------------------------------------------------------

$issues = @()
$controlRan = $false

if ($InputPath) {
    if (-not (Test-Path -LiteralPath $InputPath)) {
        throw "Issue input file not found: $InputPath"
    }
    $raw = @((Get-Content -LiteralPath $InputPath -Raw) | ConvertFrom-Json)
    foreach ($item in $raw) { $issues += ConvertTo-PfbNormalisedIssue -Raw $item }
    Write-Host "Read $($issues.Count) issue(s) from $InputPath. Label control SKIPPED -- an offline run cannot confirm the label still exists upstream."
}
else {
    if (-not $Repository) {
        if ($env:GITHUB_REPOSITORY) { $Repository = $env:GITHUB_REPOSITORY }
        else { $Repository = 'dmann000/fb-powershell' }
    }

    # THE CONTROL. Proves the label exists under the name this gate filters on, before any
    # conclusion is drawn from a count of issues carrying it. Without this, a renamed or
    # deleted label produces zero issues and a permanently green check.
    $encodedLabel = [uri]::EscapeDataString($agentReadyLabel)
    try {
        $labelRecord = Invoke-PfbGhJson -Path "repos/$Repository/labels/$encodedLabel"
    }
    catch {
        throw "Control failed: the label '$agentReadyLabel' could not be read from $Repository, so a zero-violation result would be meaningless. Underlying error: $($_.Exception.Message)"
    }
    if (-not $labelRecord -or [string]$labelRecord.name -ne $agentReadyLabel) {
        throw "Control failed: $Repository has no label named exactly '$agentReadyLabel'. Either it was renamed -- in which case this gate and docs/TRIAGE-ROLES.md need updating together -- or the taxonomy was not applied."
    }
    $controlRan = $true
    Write-Host "Control passed: '$agentReadyLabel' exists on $Repository."

    # /issues returns pull requests as well as issues; a PR carries a `pull_request` key
    # and an issue does not. Left unfiltered, a labelled PR would be asked for a brief it
    # has no reason to have.
    $listed = @(Invoke-PfbGhJson -Path "repos/$Repository/issues?state=open&labels=$encodedLabel&per_page=100")
    foreach ($item in $listed) {
        if ($item.PSObject.Properties.Name -contains 'pull_request' -and $null -ne $item.pull_request) { continue }

        # Comments come from a second call per issue: the list endpoint returns a comment
        # COUNT under the same property name, which would normalise to zero comment bodies
        # and fail every issue. Cheap in practice -- the label is meant to hold a handful
        # of issues, and if it ever holds hundreds that is itself the finding.
        $comments = @(Invoke-PfbGhJson -Path "repos/$Repository/issues/$($item.number)/comments?per_page=100")
        $issues += [PSCustomObject]@{
            Number   = [int]$item.number
            Title    = [string]$item.title
            Labels   = @(@($item.labels) | ForEach-Object { [string]$_.name })
            Comments = @(@($comments) | ForEach-Object { [string]$_.body })
        }
    }
    Write-Host "$Repository has $($issues.Count) open issue(s) carrying '$agentReadyLabel'."
}

# ---------------------------------------------------------------------------------------
# Judge
# ---------------------------------------------------------------------------------------

$violations = @(Get-PfbAgentReadyViolation -Issue $issues)
$labelled = @($issues | Where-Object { @($_.Labels) -contains $agentReadyLabel })
$passing = @($labelled.Count - $violations.Count)[0]

if (-not $Quiet) {
    foreach ($issue in $labelled) {
        $isViolation = @($violations | Where-Object { $_.Number -eq $issue.Number }).Count -gt 0
        if (-not $isViolation) { Write-Host "  ok    #$($issue.Number) $($issue.Title)" }
    }
}

$lines = New-Object System.Collections.Generic.List[string]
foreach ($violation in $violations) {
    if ($violation.Reason -eq 'no-brief') {
        $detail = "no comment on this issue is an agent brief. Either write one (docs/AGENT-BRIEF.md) or move the issue back to status:triage or status:needs-design and say in a comment what is unresolved."
    }
    else {
        $detail = "its brief is missing: $(@($violation.MissingSections) -join ', '). See the template in docs/AGENT-BRIEF.md."
    }
    $line = "#$($violation.Number) [$($violation.Reason)] $($violation.Title) -- $detail"
    $lines.Add($line)
    Write-Host "  FAIL  $line"
}

if ($env:GITHUB_STEP_SUMMARY) {
    $summary = New-Object System.Collections.Generic.List[string]
    $summary.Add("### ``$agentReadyLabel`` brief check")
    $summary.Add('')
    $summary.Add("$($labelled.Count) labelled issue(s); **$passing** carry a brief, **$($violations.Count)** do not.")
    if ($violations.Count -gt 0) {
        $summary.Add('')
        foreach ($line in $lines) { $summary.Add("- $line") }
    }
    ($summary -join [Environment]::NewLine) | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append
}

if ($violations.Count -gt 0) {
    throw "$($violations.Count) of $($labelled.Count) issue(s) labelled '$agentReadyLabel' do not carry a usable agent brief. The label promises a brief is attached; an unattended worker popping one of these wastes a run."
}

if ($controlRan -and $labelled.Count -eq 0) {
    # Not a failure. The label existing while holding nothing is a real and healthy state:
    # it means the queue is drained, not that the check is broken. Said out loud because a
    # silent zero is the thing the control exists to make readable.
    Write-Host "No issues currently carry '$agentReadyLabel'. The label exists and the queue is empty."
}

Write-Host "PASS: every '$agentReadyLabel' issue carries a brief ($($labelled.Count) checked)."
