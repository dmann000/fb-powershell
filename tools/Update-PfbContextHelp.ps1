#Requires -Version 5.1
<#
.SYNOPSIS
    Generates the context-requirement .NOTES block in the comment-based help of every
    cmdlet whose endpoint has a non-default (non-array) Fusion context scope.
.DESCRIPTION
    The four client-side context gates validate against `contextScope` in
    Data/PfbCapabilityMap.json. This script generates the *help text* for the same
    requirement from that same field, so the documented behaviour cannot drift from the
    enforced behaviour.

    Scope ruling: generate for NON-DEFAULT scopes only -- endpoints whose contextScope is
    `fleet` or `unknown`. `array` is the overwhelming default and needs no note; adding one
    to all ~600 endpoints would be a several-hundred-file mechanical diff.

    The generated text lives between two delimiters:

        <!-- PfbContext: generated from Data/PfbCapabilityMap.json contextScope. Do not edit. -->
        ...
        <!-- /PfbContext -->

    so a re-run REPLACES the block rather than appending to it. Running this script twice
    produces byte-identical files (see Tests/Update-PfbContextHelp.Tests.ps1).

    Endpoint-to-cmdlet mapping is done by scanning each Public/**/*.ps1 for its
    `Invoke-PfbApiRequest -Method <verb> ... -Endpoint '<path>'` call. Any non-default-scope
    endpoint with no matching cmdlet file is REPORTED (warning + MissingCmdlet in the
    returned summary), never silently skipped -- a silent skip reads as "covered everything".

    A non-default-scope endpoint whose scope value this generator has no arm for is reported
    the same way, for the same reason (warning + UnrecognisedScope in the summary). Two
    independent rails already make a brand-new scope value hard to introduce by accident --
    Build-PfbCapabilityMap maps an unrecognised domain token to `unknown` rather than
    inventing a value, and Tests/Build-PfbCapabilityMap.Tests.ps1 asserts every endpoint's
    scope is one of fleet/array/unknown -- but "hard to reach" is not a reason to drop the
    endpoint quietly if it is ever reached.

    Known limitation, not exercised by any endpoint today: if an endpoint's scope later
    changes TO `array`, this generator stops emitting for that file. The strip phase removes
    the block, but the `.NOTES` header the generator originally created stays behind as an
    empty orphan. It is cosmetic; delete it by hand if it ever appears.
.PARAMETER EmitLineOnly
    Diagnostic/test mode: emit the block that WOULD be generated for a single
    -Scope / -EndpointKey pair and write no files. Returns $null for the default `array`
    scope, since nothing is generated for it.
.PARAMETER Scope
    With -EmitLineOnly, the contextScope value to render ('fleet', 'unknown', 'array').
    Deliberately not [Parameter(Mandatory)]: a mandatory parameter prompts and hangs under
    -NonInteractive. Missing values throw explicitly instead.
.PARAMETER EndpointKey
    With -EmitLineOnly, the endpoint key to render, e.g. 'POST /presets/workload'.
.PARAMETER CapabilityMapPath
    Path to the capability map. Defaults to Data/PfbCapabilityMap.json under the repo root.
.PARAMETER PublicRoot
    Directory holding the cmdlet files. Defaults to Public/ under the repo root.
.OUTPUTS
    In generate mode, a summary object with:
      Changed           - files this run changed (or, under -WhatIf, would change)
      Generated         - every file that carries a generated block after this run
      Unchanged         - count of target files already correct
      MissingCmdlet     - non-default-scope endpoints with no cmdlet file
      UnrecognisedScope - non-default-scope endpoints whose scope value has no render arm
.EXAMPLE
    ./tools/Update-PfbContextHelp.ps1 -WhatIf
    Report what would change without writing anything.
.EXAMPLE
    ./tools/Update-PfbContextHelp.ps1
    Regenerate the blocks in place.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$EmitLineOnly,

    [string]$Scope,

    [string]$EndpointKey,

    [string]$CapabilityMapPath,

    [string]$PublicRoot
)

$ErrorActionPreference = 'Stop'

$script:BlockOpen = '<!-- PfbContext: generated from Data/PfbCapabilityMap.json contextScope. Do not edit. -->'
$script:BlockClose = '<!-- /PfbContext -->'

function Get-PfbContextHelpBody {
    <#
        Returns the wrapped, indented block for one endpoint, or $null when the scope is
        the default ('array') and therefore needs no note. Unrecognised scopes also return
        $null -- the capability map is the source of truth and a new scope value must be
        handled deliberately, not guessed at in help text.

        $null here means only "nothing to render". Distinguishing the two reasons for it is
        the CALLER's job, and generate mode does: 'array' is expected and silent, while an
        unrecognised scope is warned about and recorded in UnrecognisedScope. -EmitLineOnly
        keeps returning a bare $null for both, which is what its 'emits nothing for an
        array-scoped endpoint' test pins.
    #>
    param(
        [string]$Scope,
        [string]$EndpointKey,
        [string]$Indent = '        '
    )

    $lines = switch ($Scope) {
        'fleet' {
            @(
                "Context requirement ($EndpointKey): this cmdlet targets a fleet-scoped resource"
                'and requires a bare fleet context. Set one with'
                'Set-PfbContext -Context <fleet> -Kind Fleet, or scope a single call with'
                'Invoke-PfbInContext. Get the fleet name from Get-PfbFleet.'
            )
        }
        'unknown' {
            @(
                "Context requirement ($EndpointKey): the context scope for this endpoint is not"
                'recorded in the capability map, so the module will not pre-validate a context'
                'for it. A fleet or array context may still be required by the array itself; if'
                'a call fails with a context error, set one with Set-PfbContext or scope the'
                'call with Invoke-PfbInContext.'
            )
        }
        default { $null }
    }

    if ($null -eq $lines) { return $null }

    $all = @($script:BlockOpen) + $lines + @($script:BlockClose)
    return (($all | ForEach-Object { $Indent + $_ }) -join "`r`n")
}

# --- diagnostic single-line mode -------------------------------------------------------
if ($EmitLineOnly) {
    if ([string]::IsNullOrWhiteSpace($Scope) -or [string]::IsNullOrWhiteSpace($EndpointKey)) {
        throw '-EmitLineOnly requires both -Scope and -EndpointKey.'
    }
    return (Get-PfbContextHelpBody -Scope $Scope -EndpointKey $EndpointKey)
}

# --- generate mode ---------------------------------------------------------------------
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $CapabilityMapPath) { $CapabilityMapPath = Join-Path $repoRoot 'Data/PfbCapabilityMap.json' }
if (-not $PublicRoot) { $PublicRoot = Join-Path $repoRoot 'Public' }

if (-not (Test-Path -LiteralPath $CapabilityMapPath)) {
    throw "Capability map not found at '$CapabilityMapPath'."
}
if (-not (Test-Path -LiteralPath $PublicRoot)) {
    throw "Public cmdlet root not found at '$PublicRoot'."
}

$map = Get-Content -LiteralPath $CapabilityMapPath -Raw | ConvertFrom-Json

# Non-default-scope endpoints, keyed exactly as the capability map keys them.
$nonDefault = @{}
foreach ($prop in $map.endpoints.PSObject.Properties) {
    $scopeValue = $prop.Value.contextScope.scope
    # $null (no scope recorded at all) is unset and stays out; an explicitly EMPTY scope is
    # a recorded value that happens to say nothing, so it comes in and is then reported as
    # unrecognised rather than being silently folded in with the 'array' default. Never a
    # truthiness test here -- that collapses those two cases into one.
    if ($null -ne $scopeValue -and $scopeValue -ne 'array') { $nonDefault[$prop.Name] = $scopeValue }
}

# Endpoint key -> cmdlet file, by scanning each cmdlet's Invoke-PfbApiRequest call.
$endpointToFile = @{}
foreach ($file in (Get-ChildItem -LiteralPath $PublicRoot -Recurse -Filter '*.ps1')) {
    $text = Get-Content -LiteralPath $file.FullName -Raw
    foreach ($call in [regex]::Matches($text, 'Invoke-PfbApiRequest[^\r\n]*')) {
        $method = [regex]::Match($call.Value, '-Method\s+([A-Za-z]+)').Groups[1].Value
        $endpoint = [regex]::Match($call.Value, "-Endpoint\s+'([^']+)'").Groups[1].Value
        if (-not $method -or -not $endpoint) { continue }
        $key = '{0} /{1}' -f $method.ToUpperInvariant(), $endpoint
        if (-not $nonDefault.ContainsKey($key)) { continue }
        if (-not $endpointToFile.ContainsKey($key)) { $endpointToFile[$key] = @() }
        if ($endpointToFile[$key] -notcontains $file.FullName) { $endpointToFile[$key] += $file.FullName }
    }
}

# Group the work by file: one file can legitimately own several non-default endpoints, in
# which case it gets one delimited block containing one paragraph per endpoint.
$fileToEndpoints = @{}
$missing = @()
foreach ($key in ($nonDefault.Keys | Sort-Object)) {
    if (-not $endpointToFile.ContainsKey($key)) {
        $missing += [PSCustomObject]@{ EndpointKey = $key; Scope = $nonDefault[$key] }
        Write-Warning "No cmdlet file calls '$key' (contextScope '$($nonDefault[$key])'); no help generated for it."
        continue
    }
    foreach ($f in $endpointToFile[$key]) {
        if (-not $fileToEndpoints.ContainsKey($f)) { $fileToEndpoints[$f] = @() }
        $fileToEndpoints[$f] += $key
    }
}

function Set-PfbContextHelpBlock {
    <#
        Returns the new content for one cmdlet file with its generated block inserted or
        replaced. Two-phase and therefore idempotent:
          1. strip any existing block (delimiters inclusive), leaving a pre-existing
             .NOTES header alone;
          2. insert the freshly rendered block immediately after the .NOTES header,
             creating that header just before the help terminator if the file has none.
    #>
    param(
        [string]$Content,
        [string]$Block
    )

    # Phase 1: strip the previous generated block, if any.
    $stripPattern = '(?ms)^[ \t]*' + [regex]::Escape($script:BlockOpen) + '.*?' +
        [regex]::Escape($script:BlockClose) + '[ \t]*\r?\n'
    $stripped = [regex]::Replace($Content, $stripPattern, '')

    # Phase 2: insert after an existing .NOTES header, else create one before the
    # comment-based help terminator.
    $notesMatch = [regex]::Match($stripped, '(?m)^([ \t]*)\.NOTES[ \t]*\r?\n')
    if ($notesMatch.Success) {
        $insertAt = $notesMatch.Index + $notesMatch.Length
        return $stripped.Substring(0, $insertAt) + $Block + "`r`n" + $stripped.Substring($insertAt)
    }

    $endMatch = [regex]::Match($stripped, '(?m)^([ \t]*)#>[ \t]*\r?\n')
    if (-not $endMatch.Success) {
        throw 'Could not locate the end of the comment-based help block (a line consisting of "#>").'
    }
    $indent = $endMatch.Groups[1].Value
    $header = $indent + '.NOTES' + "`r`n"
    return $stripped.Substring(0, $endMatch.Index) + $header + $Block + "`r`n" + $stripped.Substring($endMatch.Index)
}

$changed = @()
$generated = @()
$unchanged = 0
$unrecognised = @()

foreach ($file in ($fileToEndpoints.Keys | Sort-Object)) {
    $keys = $fileToEndpoints[$file] | Sort-Object -Unique

    $paragraphs = @()
    foreach ($key in $keys) {
        $body = Get-PfbContextHelpBody -Scope $nonDefault[$key] -EndpointKey $key
        if ($null -eq $body) {
            # A non-default scope with no render arm. Report it rather than dropping it:
            # this is the same "a silent skip reads as covered everything" failure the
            # MissingCmdlet path above exists to prevent, and the only difference is which
            # half of the pairing is missing -- there, the cmdlet; here, the render arm.
            $unrecognised += [PSCustomObject]@{ EndpointKey = $key; Scope = $nonDefault[$key] }
            Write-Warning ("contextScope '{0}' on '{1}' is not a value this generator renders; no help generated for it. Add a switch arm in Get-PfbContextHelpBody." -f $nonDefault[$key], $key)
            continue
        }
        # Strip each paragraph's own delimiters; one shared wrapper goes around them all.
        $inner = ($body -split "`r`n") | Where-Object {
            -not $_.Contains($script:BlockOpen) -and -not $_.Contains($script:BlockClose)
        }
        $paragraphs += ($inner -join "`r`n")
    }
    if (-not $paragraphs) { continue }

    $indent = '        '
    $block = (@($indent + $script:BlockOpen) + $paragraphs + @($indent + $script:BlockClose)) -join "`r`n"

    $original = Get-Content -LiteralPath $file -Raw
    $updated = Set-PfbContextHelpBlock -Content $original -Block $block

    $generated += $file
    if ($updated -eq $original) {
        $unchanged++
        continue
    }

    $changed += $file
    if ($PSCmdlet.ShouldProcess($file, 'Update generated context-requirement help block')) {
        # WriteAllText, not Set-Content: no Public/*.ps1 has a UTF-8 BOM, and Set-Content
        # -Encoding UTF8 adds one under Windows PowerShell 5.1. $updated already carries
        # the file's own trailing newline, so no extra newline is appended either.
        [System.IO.File]::WriteAllText($file, $updated, (New-Object System.Text.UTF8Encoding($false)))
    }
}

Write-Verbose ("Context help: {0} changed, {1} already current, {2} endpoint(s) with no cmdlet, {3} with an unrecognised scope." -f
    $changed.Count, $unchanged, $missing.Count, $unrecognised.Count)

[PSCustomObject]@{
    Changed           = $changed
    Generated         = $generated
    Unchanged         = $unchanged
    MissingCmdlet     = $missing
    UnrecognisedScope = $unrecognised
}
