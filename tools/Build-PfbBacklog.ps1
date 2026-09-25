#Requires -Version 7.0
<#
.SYNOPSIS
    Ranks this repository's open issues into lanes: what the next unit of work is, and why.
.DESCRIPTION
    Reads every open issue (paged), plus Reports/PfbApiDriftReport.json and
    Reports/PfbDeadKeyReport.json, and sorts the issues into seven lanes that follow
    docs/TRIAGE-ROLES.md's state machine. The build and design lanes are ranked by the
    human priority: label first, then by readiness, impact, size, live finding count and
    issue number, and every row names the key that placed it (decidedBy). A status:triage
    issue is not ranked. It carries a PROPOSED priority and size, and `differs` says
    whether its current labels agree.

    The rules are all in tools/lib/PfbBacklogTools.ps1, which is pure and tested against
    fixtures (Tests/PfbBacklogTools.Tests.ps1). This file owns the reads and the output;
    Tests/Build-PfbBacklog.Tests.ps1 runs it with the network mocked.

    READ-ONLY. It writes no label and no issue, needs only issues: read, and commits
    nothing. Output goes to -OutputPath or to the console. Reports/ and the derived-artifact
    gate are untouched. generatedAt makes the output non-reproducible on purpose, which is
    acceptable only because it is never committed.

    NO GITHUB CLI, AND NO CREDENTIAL REQUIRED. The repository is public, so the issue list
    answers anonymously. tools/lib/PfbGitHubRead.ps1 makes the GET with Invoke-RestMethod,
    as scripts/Assert-PfbAgentReadyBrief.ps1 does. A token only raises the rate limit.
.PARAMETER Repo
    owner/name. Default dmann000/fb-powershell.
.PARAMETER Token
    Optional. Defaults to GH_TOKEN, then GITHUB_TOKEN, else anonymous. It raises the rate
    limit from 60 to 1,000 requests an hour and grants nothing else.
.PARAMETER OutputPath
    A directory, created if absent. When given, the script writes PfbBacklog.json (every
    lane, every row) and PfbBacklog.md there. When omitted, it prints the Markdown to the
    console.
.PARAMETER Lane
    Restricts the Markdown and console output to these lanes. The JSON always holds all
    seven.
.PARAMETER First
    Rows per lane in the Markdown and console output. Default 10. The JSON always holds
    every row.
.PARAMETER DriftReportPath
    Default Reports/PfbApiDriftReport.json.
.PARAMETER DeadKeyReportPath
    Default Reports/PfbDeadKeyReport.json.
.EXAMPLE
    ./tools/Build-PfbBacklog.ps1 -Lane build -First 1
    The single next thing to build, read anonymously.
.EXAMPLE
    ./tools/Build-PfbBacklog.ps1 -OutputPath ./backlog
    Writes backlog/PfbBacklog.json and backlog/PfbBacklog.md.
#>
[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')][string]$Repo = 'dmann000/fb-powershell',
    [string]$Token,
    [string]$OutputPath,
    [ValidateSet('build', 'design', 'triage', 'inFlight', 'parked', 'confirmClose', 'labelErrors')]
    [string[]]$Lane = @('build', 'design', 'triage', 'inFlight', 'parked', 'confirmClose', 'labelErrors'),
    [ValidateRange(1, 1000)][int]$First = 10,
    [string]$DriftReportPath,
    [string]$DeadKeyReportPath
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path (Join-Path $PSScriptRoot 'lib') 'PfbGitHubRead.ps1')
. (Join-Path (Join-Path $PSScriptRoot 'lib') 'PfbBacklogTools.ps1')

if (-not $DriftReportPath) { $DriftReportPath = Join-Path (Join-Path $repoRoot 'Reports') 'PfbApiDriftReport.json' }
if (-not $DeadKeyReportPath) { $DeadKeyReportPath = Join-Path (Join-Path $repoRoot 'Reports') 'PfbDeadKeyReport.json' }

$userAgent = 'fb-powershell-backlog-scorer'

function Read-PfbBacklogJson {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Description
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Description was not found at $Path." }
    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

# --- read ---
$driftReport = Read-PfbBacklogJson -Path $DriftReportPath -Description 'The drift report'
$deadKeyReport = Read-PfbBacklogJson -Path $DeadKeyReportPath -Description 'The dead-key report'
# Throws on a missing category or an unknown schema (Get-PfbDriftFinding's own checks).
$findings = @(Get-PfbDriftFinding -DriftReport $driftReport -DeadKeyReport $deadKeyReport)

$bearer = $Token
if (-not $bearer) { $bearer = $env:GH_TOKEN }
if (-not $bearer) { $bearer = $env:GITHUB_TOKEN }
if ($bearer) { Write-Host "Reading $Repo authenticated (rate limit 1,000/hour)." }
else { Write-Host "Reading $Repo anonymously (rate limit 60/hour, counted per source IP). Set GITHUB_TOKEN to raise it." }

$issues = @(Invoke-PfbGitHubPagedList -Path "repos/$Repo/issues?state=open&per_page=$script:PfbPageSize" `
        -UserAgent $userAgent -BearerToken $bearer -Description "The open-issue list for $Repo")

# --- score ---
$generatedAt = [DateTime]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [System.Globalization.CultureInfo]::InvariantCulture)
$backlog = Get-PfbBacklog -Issue $issues -Finding $findings -Repo $Repo -SpecVersion ([string]$deadKeyReport.specVersion) -GeneratedAt $generatedAt
$markdown = Format-PfbBacklogMarkdown -Backlog $backlog -First $First -Lane $Lane
Write-Host ("{0} open issue(s) scored against {1} finding(s): {2}." -f `
        (@($script:PfbBacklogLane | ForEach-Object { [int]$backlog.counts.$_ }) | Measure-Object -Sum).Sum, $findings.Count,
    (@($script:PfbBacklogLane | ForEach-Object { '{0} {1}' -f $_, $backlog.counts.$_ }) -join ', '))

# --- write ---
if ($OutputPath) {
    # New-Item resolves a relative path against the PowerShell location. [System.IO.File]
    # would resolve it against the process directory, which is not the same thing once a
    # caller has cd'd, so everything below uses the resolved FullName.
    $directory = (New-Item -ItemType Directory -Path $OutputPath -Force).FullName
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText((Join-Path $directory 'PfbBacklog.json'), (($backlog | ConvertTo-Json -Depth 10) + "`n"), $utf8NoBom)
    [System.IO.File]::WriteAllText((Join-Path $directory 'PfbBacklog.md'), $markdown, $utf8NoBom)
    Write-Host "Wrote PfbBacklog.json and PfbBacklog.md to $directory."
}
else {
    $markdown
}
