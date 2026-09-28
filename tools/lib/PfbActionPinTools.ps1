<#
.SYNOPSIS
    Reads the `uses:` references out of this repository's workflows and composite actions.
.DESCRIPTION
    Shared by Tests/WorkflowPins.Tests.ps1 (every remote reference is SHA-pinned) and
    tools/Get-PfbActionPinStatus.ps1 (is each pin behind its latest release).

    A REMOTE reference is owner/repo[/path]@ref. Here it must be pinned to a full 40-hex
    commit SHA followed by a `# vX.Y.Z` comment naming the release that SHA came from. A
    LOCAL reference (./...) is part of this repository and is never pinned. A docker://
    reference is reported as its own kind so the pin rule can reject it by name.

    Line-oriented regex, not a YAML parser: PowerShell has none built in, and the only shape
    that matters is `uses: <value>` on one line, as a step key or a job key.

    5.1-SAFE ON PURPOSE: the pin tests run on every CI leg, Windows PowerShell 5.1
    included. Pure ASCII.
#>

$script:PfbUsesPattern = '(?m)^[ \t]*(?:-[ \t]+)?uses:[ \t]*(?<value>[^\s#]+)(?<rest>[^\r\n]*)'
$script:PfbPinnedPattern = '^[^@\s]+@[0-9a-f]{40}\s+#\s*v\d'
$script:PfbRemotePattern = '^(?<owner>[A-Za-z0-9_.-]+)/(?<repo>[A-Za-z0-9_.-]+)(?:/(?<sub>[^@]+))?@(?<ref>.+)$'

function Get-PfbWorkflowFile {
    <#
    .SYNOPSIS
        The workflow and composite-action files under <RepoRoot>/.github, sorted by path.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param([Parameter(Mandatory = $true)][string]$RepoRoot)

    $github = Join-Path $RepoRoot '.github'
    $found = @()
    $workflows = Join-Path $github 'workflows'
    if (Test-Path -LiteralPath $workflows) {
        $found += @(Get-ChildItem -LiteralPath $workflows -File | Where-Object { $_.Extension -in '.yml', '.yaml' })
    }
    $actions = Join-Path $github 'actions'
    if (Test-Path -LiteralPath $actions) {
        $found += @(Get-ChildItem -LiteralPath $actions -File -Recurse | Where-Object { $_.Name -in 'action.yml', 'action.yaml' })
    }
    return @($found | Sort-Object FullName)
}

function Get-PfbActionReference {
    <#
    .SYNOPSIS
        One record per `uses:` line in -Text.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
        [string]$File = ''
    )

    foreach ($m in [regex]::Matches($Text, $script:PfbUsesPattern)) {
        $uses = $m.Groups['value'].Value.Trim('"', "'")
        $rest = $m.Groups['rest'].Value
        # Quoted values keep their closing quote in `value` when a comment follows; strip it
        # from the start of `rest` too so `Uses + Rest` reads as the author wrote it, unquoted.
        $rest = $rest -replace '^["'']', ''
        $record = [ordered]@{
            File = $File
            Line = [regex]::Matches($Text.Substring(0, $m.Index), "`n").Count + 1
            Uses = $uses
            Rest = $rest
            Kind = 'remote'
            Repository = $null
            SubPath = ''
            Ref = $null
            Sha = $null
            Version = $null
        }
        if ($uses.StartsWith('./')) { $record.Kind = 'local' }
        elseif ($uses.StartsWith('docker://')) { $record.Kind = 'docker' }
        else {
            $r = [regex]::Match($uses, $script:PfbRemotePattern)
            if ($r.Success) {
                $record.Repository = '{0}/{1}' -f $r.Groups['owner'].Value, $r.Groups['repo'].Value
                $record.SubPath = $r.Groups['sub'].Value
                $record.Ref = $r.Groups['ref'].Value
                if ($record.Ref -cmatch '^[0-9a-f]{40}$') { $record.Sha = $record.Ref }
            }
            $v = [regex]::Match($rest, '#\s*(?<v>v\d[^\s]*)')
            if ($v.Success) { $record.Version = $v.Groups['v'].Value }
        }
        [pscustomobject]$record
    }
}

function Test-PfbActionPinned {
    <#
    .SYNOPSIS
        True when a reference is pinned to a 40-hex SHA and carries a `# vX...` comment.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory = $true)]$Reference)

    return (('{0}{1}' -f $Reference.Uses, $Reference.Rest) -cmatch $script:PfbPinnedPattern)
}

function Test-PfbPinBehind {
    <#
    .SYNOPSIS
        True when -Latest is a newer release than -Pinned.
    .DESCRIPTION
        Compared as [version] after stripping a leading 'v', so v7.0.10 is newer than v7.0.9.
        A tag that does not parse as a version falls back to "behind when not identical",
        which reports a difference rather than hiding one.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)][string]$Pinned,
        [Parameter(Mandatory = $true)][string]$Latest
    )

    $p = $null
    $l = $null
    if ([version]::TryParse($Pinned.TrimStart('v'), [ref]$p) -and [version]::TryParse($Latest.TrimStart('v'), [ref]$l)) {
        return ($l -gt $p)
    }
    return ($Pinned -ne $Latest)
}
