#Requires -Version 7.0

<#
.SYNOPSIS
    For each SHA-pinned action under .github/, says whether a newer release is out. Opens nothing.
.DESCRIPTION
    Reads every remote `uses:` reference (tools/lib/PfbActionPinTools.ps1), asks the GitHub
    REST API for each action repository's latest release, and returns one row per pinned
    version: Action, Pinned, Latest, Behind (yes/no). With -SummaryPath, also appends a
    Markdown table there (the job summary in CI).

    REPORT ONLY. It opens no issue and no pull request; bumping a pin is a person's decision
    in an ordinary PR. It fails only when the API call itself fails -- never because a pin is
    behind.

    Every request is a GET. The repository's actions are public, so a token only raises the
    rate limit (60 to 1,000 an hour).
.PARAMETER RepoRoot
    Default: the repository this script lives in.
.PARAMETER Token
    Optional. Defaults to GH_TOKEN, then GITHUB_TOKEN, else anonymous.
.PARAMETER SummaryPath
    Optional file to append the Markdown table to.
.EXAMPLE
    ./tools/Get-PfbActionPinStatus.ps1 | Format-Table
#>
[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$Token,
    [string]$SummaryPath
)

$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) { $RepoRoot = Split-Path -Parent $PSScriptRoot }
. (Join-Path (Join-Path $PSScriptRoot 'lib') 'PfbGitHubRead.ps1')
. (Join-Path (Join-Path $PSScriptRoot 'lib') 'PfbActionPinTools.ps1')

$bearer = $Token
if (-not $bearer) { $bearer = $env:GH_TOKEN }
if (-not $bearer) { $bearer = $env:GITHUB_TOKEN }

$references = @(foreach ($file in Get-PfbWorkflowFile -RepoRoot $RepoRoot) {
        Get-PfbActionReference -Text ([System.IO.File]::ReadAllText($file.FullName)) -File $file.Name
    }) | Where-Object { $_.Kind -eq 'remote' -and $_.Repository }

$pins = @($references | Group-Object { '{0}|{1}' -f $_.Repository, $_.Version } | ForEach-Object { $_.Group[0] })

$latestByRepository = @{}
$rows = foreach ($pin in $pins) {
    if (-not $latestByRepository.ContainsKey($pin.Repository)) {
        $release = Invoke-PfbGitHubApi -Path "repos/$($pin.Repository)/releases/latest" -UserAgent 'fb-powershell-action-pin-status' -BearerToken $bearer
        $latestByRepository[$pin.Repository] = [string]$release.tag_name
    }
    $latest = $latestByRepository[$pin.Repository]
    $pinned = [string]$pin.Version
    $behind = 'no'
    if (-not $pinned -or (Test-PfbPinBehind -Pinned $pinned -Latest $latest)) { $behind = 'yes' }
    [pscustomobject]@{ Action = $pin.Repository; Pinned = $pinned; Latest = $latest; Behind = $behind }
}
$rows = @($rows | Sort-Object Action, Pinned)

if ($SummaryPath) {
    $lines = @('## Action pin status', '', '| Action | Pinned | Latest | Behind |', '|---|---|---|---|')
    $lines += @($rows | ForEach-Object { '| {0} | {1} | {2} | {3} |' -f $_.Action, $_.Pinned, $_.Latest, $_.Behind })
    $lines += ''
    [System.IO.File]::AppendAllText($SummaryPath, ($lines -join "`n") + "`n", (New-Object System.Text.UTF8Encoding $false))
}

Write-Host ("{0} pinned action version(s), {1} behind." -f $rows.Count, @($rows | Where-Object Behind -eq 'yes').Count)
$rows
