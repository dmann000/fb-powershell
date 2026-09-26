#Requires -Version 5.1
<#
.SYNOPSIS
    Says whether a commit on main is the merge of the automated capability-map PR.
.DESCRIPTION
    The gate in front of the Drift Issues workflow's push path
    (.github/workflows/drift-issues.yml). A push to main that changes a drift report runs
    the reconciler with -Apply only when the pushed commit merged the PR that
    update-api-capability-map.yml opens from automated/update-api-capability-map: the
    spec-release event. A feature merge that regenerates the reports is not.

    Asks GitHub which pull requests the commit belongs to
    (GET repos/<Repo>/commits/<Sha>/pulls) and hands the answer to
    Get-PfbCapabilityMapMergeVerdict in tools/lib/PfbDriftIssueTools.ps1, which decides.
    An empty answer is retried: the association can lag the push by a few seconds.

    Prints the verdict's reason, then 'true' or 'false' as the LAST line of stdout, and
    appends is_capability_map_merge=<true|false> to $env:GITHUB_OUTPUT when it is set.
    Exits 0 for either verdict. A failed gh call throws, so the workflow run goes red
    instead of silently skipping a release.
.PARAMETER Repo
    owner/name of the repository the commit is on.
.PARAMETER Sha
    The full 40-character commit SHA (github.sha on a push event).
.PARAMETER GhCommand
    The gh executable. CI passes gh; on a workstation pass ghx, which reads this clone's
    pinned GitHub identity.
.PARAMETER Attempts
    How many times to ask while the association comes back empty.
.PARAMETER RetryDelaySeconds
    Seconds between attempts.
.EXAMPLE
    ./tools/Test-PfbCapabilityMapMerge.ps1 -Repo dmann000/fb-powershell -Sha (git rev-parse HEAD) -GhCommand ghx
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')][string]$Repo,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{40}$')][string]$Sha,
    [ValidateNotNullOrEmpty()][string]$GhCommand = 'gh',
    [ValidateRange(1, 10)][int]$Attempts = 3,
    [ValidateRange(0, 120)][int]$RetryDelaySeconds = 15
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path (Join-Path $PSScriptRoot 'lib') 'PfbDriftIssueTools.ps1')

$endpoint = "repos/$Repo/commits/$Sha/pulls"
$pulls = @()
for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
    # From the repository root: ghx resolves the pinned account from the .git/config of the
    # current directory.
    Push-Location -LiteralPath $repoRoot
    try {
        $output = & $GhCommand 'api' $endpoint
        $exitCode = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }
    if ($exitCode -ne 0) { throw "$GhCommand api $endpoint failed with exit code $exitCode." }

    $text = @($output) -join "`n"
    $pulls = @()
    if (-not [string]::IsNullOrWhiteSpace($text)) {
        # Re-emitting through ForEach-Object unrolls the array: Windows PowerShell 5.1's
        # ConvertFrom-Json writes a JSON array as ONE object, so a lone @() would wrap it.
        $pulls = @($text | ConvertFrom-Json | ForEach-Object { $_ })
    }
    if ($pulls.Count -gt 0) { break }
    if ($attempt -lt $Attempts) {
        Write-Host "No pull request associated with $Sha yet (attempt $attempt of $Attempts); retrying in $RetryDelaySeconds s."
        Start-Sleep -Seconds $RetryDelaySeconds
    }
}

$verdict = Get-PfbCapabilityMapMergeVerdict -Pull $pulls -Repo $Repo
Write-Host $verdict.Reason

$answer = 'false'
if ($verdict.IsCapabilityMapMerge) { $answer = 'true' }
if ($env:GITHUB_OUTPUT) {
    [System.IO.File]::AppendAllText($env:GITHUB_OUTPUT, "is_capability_map_merge=$answer`n", (New-Object System.Text.UTF8Encoding $false))
}
$answer
