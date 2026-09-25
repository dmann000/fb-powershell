#Requires -Version 7.0
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

    TARGETS POWERSHELL 7, like the other scripts under scripts/ that CI invokes. The
    5.1/7 compatibility rules in this repo bind what ships to the Gallery; this never
    ships and never runs anywhere but a runner or a maintainer's shell.

    NO GITHUB CLI, AND NO CREDENTIAL REQUIRED. This makes three plain GETs -- one label,
    one issue list, one comment list per labelled issue -- so it uses Invoke-RestMethod,
    which is already how everything under tools/ reaches the network. `gh api` would add a
    PATH dependency to a runner for nothing but a base URL and a JSON parse, and no
    workflow in this repository uses it. The GETs themselves live in
    tools/lib/PfbGitHubRead.ps1, shared with tools/Build-PfbBacklog.ps1.

    The repository is public, so all three endpoints answer without a token; that is
    verified, not assumed. A token is therefore optional and is used only for the rate
    limit: unauthenticated callers get 60 requests an hour counted per source IP, and
    hosted runners share egress IPs with everyone else, so an unlucky window would surface
    as a 403 that reads like a gate failure rather than like a quota. Authenticated with
    the workflow's own GITHUB_TOKEN it is 1,000 an hour, scoped to this repository. The
    script says which mode it used, because "403" and "the label is missing" must not
    arrive looking the same.

.PARAMETER Token
    Optional. Defaults to GH_TOKEN, then GITHUB_TOKEN. Raises the rate limit; grants no
    access this repository does not already give anonymously.
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
    [string]$Token,
    [string]$InputPath,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'tools/lib/PfbAgentBriefTools.ps1')
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'tools/lib/PfbGitHubRead.ps1')

$agentReadyLabel = 'status:agent-ready'

# Every request names this gate. tools/lib/PfbGitHubRead.ps1 makes -UserAgent mandatory,
# with no shared default, so an abuse-detection response stays traceable to one caller.
$userAgent = 'fb-powershell-agent-ready-brief-gate'

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

    $bearer = $Token
    if (-not $bearer) { $bearer = $env:GH_TOKEN }
    if (-not $bearer) { $bearer = $env:GITHUB_TOKEN }

    # Stated rather than left to be inferred from a later failure. Anonymous is a
    # supported mode against a public repository, not a misconfiguration -- but it is the
    # mode in which a 403 means "wait an hour", and that is worth knowing before reading
    # one.
    if ($bearer) {
        Write-Host "Reading $Repository authenticated (rate limit 1,000/hour)."
    }
    else {
        Write-Host "Reading $Repository anonymously (rate limit 60/hour, counted per source IP). Set GITHUB_TOKEN to raise it."
    }

    # THE CONTROL. Proves the label exists under the name this gate filters on, before any
    # conclusion is drawn from a count of issues carrying it. Without this, a renamed or
    # deleted label produces zero issues and a permanently green check.
    $encodedLabel = [uri]::EscapeDataString($agentReadyLabel)
    try {
        $labelRecord = Invoke-PfbGitHubApi -Path "repos/$Repository/labels/$encodedLabel" -UserAgent $userAgent -BearerToken $bearer
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
    $listed = @(Invoke-PfbGitHubList -BearerToken $bearer -UserAgent $userAgent -Description "The issue list for '$agentReadyLabel'" `
            -Path "repos/$Repository/issues?state=open&labels=$encodedLabel&per_page=$script:PfbPageSize")
    foreach ($item in $listed) {
        if ($item.PSObject.Properties.Name -contains 'pull_request' -and $null -ne $item.pull_request) { continue }

        # Comments come from a second call per issue: the list endpoint returns a comment
        # COUNT under the same property name, which would normalise to zero comment bodies
        # and fail every issue. Cheap in practice -- the label is meant to hold a handful
        # of issues, and if it ever holds hundreds that is itself the finding.
        $comments = @(Invoke-PfbGitHubList -BearerToken $bearer -UserAgent $userAgent -Description "Comments on #$($item.number)" `
                -Path "repos/$Repository/issues/$($item.number)/comments?per_page=$script:PfbPageSize")
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
