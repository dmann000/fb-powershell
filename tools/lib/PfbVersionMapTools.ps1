<#
.SYNOPSIS
    Shared helpers for tools/Update-PfbVersionMap.ps1. Split out from that script so the
    pure, fully-specified pieces (URI construction, HTML table parsing) are unit-testable
    independent of the network-dependent orchestration.
#>

function Get-PfbSsotVersionMapUri {
    <#
    .SYNOPSIS
        Builds the SSOT (Single Source of Truth) API URI for the FlashBlade REST API
        version <-> Purity//FB mapping topic.
    .DESCRIPTION
        Each FlashBlade REST API version has a corresponding row in a single "FlashBlade
        Management REST API Reference" table. This one endpoint returns the full
        REST-version-to-Purity//FB mapping table as HTML in a single call - no per-
        version fetches needed. Auth is an `x-api-key` header (see
        tools/Update-PfbVersionMap.ps1), not a bearer token.

        -BaseUri and -TopicId are both required, are internal details and are not
        hardcoded in this repo. Callers should source both from their own configuration
        (e.g. environment variables), the same way tools/Update-PfbVersionMap.ps1 sources
        the API key from $env:SSOT_API_KEY.
    .EXAMPLE
        Get-PfbSsotVersionMapUri -BaseUri $env:SSOT_BASE_URI -TopicId $env:SSOT_TOPIC_ID
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$BaseUri,

        [Parameter()]
        [string]$TopicId
    )

    # Deliberately not [Parameter(Mandatory)]: PowerShell's mandatory-parameter binder
    # prompts interactively for a missing value when the host supports it (a real
    # console), rather than throwing - which would hang a script or corrupt a terminal
    # session instead of failing fast. Explicit checks guarantee a deterministic throw
    # in every host.
    if ([string]::IsNullOrEmpty($BaseUri)) { throw [System.Management.Automation.PSArgumentException]::new('BaseUri is required.', 'BaseUri') }
    if ([string]::IsNullOrEmpty($TopicId)) { throw [System.Management.Automation.PSArgumentException]::new('TopicId is required.', 'TopicId') }

    return "$BaseUri/v1/topics/$TopicId/content"
}

function ConvertFrom-PfbSsotVersionMapHtml {
    <#
    .SYNOPSIS
        Parses the SSOT version-mapping topic's HTML into a REST-version -> { purity }
        map covering every row in the table.
    .DESCRIPTION
        The table has (at least) four columns: REST API Version | HTML | Introduced in
        Purity//FB | Ships with Purity//FB. This uses the "Introduced in" column, matching
        the existing hand-maintained Data/PfbVersionMap.json convention. Rows that don't
        have a "REST API X.Y" first cell (e.g. the header row) or that have fewer than 4
        cells are skipped rather than erroring.

        Note: the table also carries the legacy REST 1.x line (e.g. "REST API 1.11"),
        which matches the same "REST API X.Y" pattern and so IS included in the returned
        map - this function doesn't filter by major version. Callers that only care about
        the 2.x line (e.g. Update-PfbVersionMap.ps1, which only requests versions found in
        tools/specs/) simply never ask for those keys; they aren't dropped here.

        Parsed with regex rather than a DOM parser so this runs identically on Windows and
        the ubuntu-latest CI runner (no HTMLFile COM object, which is Windows-only).
    .OUTPUTS
        [ordered] hashtable keyed by bare REST version (e.g. '2.27') -> @{ purity = '4.8.3' }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Html
    )

    $map = [ordered]@{}

    $rowMatches = [regex]::Matches($Html, '<tr[^>]*>(.*?)</tr>', 'Singleline, IgnoreCase')
    foreach ($rowMatch in $rowMatches) {
        $cellMatches = [regex]::Matches($rowMatch.Groups[1].Value, '<t[dh][^>]*>(.*?)</t[dh]>', 'Singleline, IgnoreCase')
        if ($cellMatches.Count -lt 4) {
            continue
        }

        $cells = $cellMatches | ForEach-Object {
            $text = [regex]::Replace($_.Groups[1].Value, '<[^>]+>', '')
            $text = [System.Net.WebUtility]::HtmlDecode($text)
            $text.Trim()
        }

        $versionMatch = [regex]::Match($cells[0], 'REST API (\d+\.\d+)')
        if (-not $versionMatch.Success) {
            continue
        }

        $map[$versionMatch.Groups[1].Value] = [PSCustomObject]@{
            purity = $cells[2]
        }
    }

    return $map
}
