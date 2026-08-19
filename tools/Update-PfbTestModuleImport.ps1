#Requires -Version 7.0
<#
.SYNOPSIS
    Rewrites every `Import-Module <manifest> -Force` in Tests/*.Tests.ps1 to load through
    Tests/PfbTestModule.ps1 instead.
.DESCRIPTION
    Run once to produce the 162-file diff, then kept tracked. It is NOT a build step and
    must not be wired into CI. It stays because (a) a 162-file diff must be reproducible
    and reviewable as generated output, and (b) it is the tool for the next bulk change of
    this shape. Its -WhatIf fixed-point test is what keeps it honest against a drifting
    tree (Tests/Update-PfbTestModuleImport.Tests.ps1).

    Only the import STATEMENT is replaced, in place, at its own indentation. Surrounding
    $moduleRoot / $manifest assignments are left alone: several files go on to use them
    (Tests/RemovedCmdlets.Tests.ps1 asserts against $manifest;
    Tests/ArrayConnection.ShouldProcessTarget.Tests.ps1 passes it to Get-PfbTargetRecorder).
    Deleting them would be a much larger, riskier diff for no gain.

    Line endings are read, detected and preserved per file. Both LF and CRLF live in this
    tree because .gitattributes does not normalise .ps1, and splicing the wrong newline in
    makes every file differ, which reddens an idempotency test on one platform only.
.OUTPUTS
    Changed      - files this run changed, or would change under -WhatIf
    Unchanged    - count of files that already load through the helper
    Unrecognised - manifest -Force imports whose spelling has no rewrite arm. NEVER
                   silently skipped: a silent skip reads as "covered everything".
.EXAMPLE
    ./tools/Update-PfbTestModuleImport.ps1 -WhatIf
.EXAMPLE
    ./tools/Update-PfbTestModuleImport.ps1
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$TestRoot
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $repoRoot 'tools/lib/PfbTestImportTools.ps1')

if ([string]::IsNullOrWhiteSpace($TestRoot)) { $TestRoot = Join-Path $repoRoot 'Tests' }

$dotSourceLine = ". (Join-Path `$PSScriptRoot 'PfbTestModule.ps1')"
$changed = @()
$unrecognised = @()
$unchanged = 0

foreach ($file in (Get-ChildItem -Path $TestRoot -Filter '*.Tests.ps1' -File | Sort-Object Name)) {
    $content = [System.IO.File]::ReadAllText($file.FullName)
    $imports = @(Get-PfbTestManifestImport -Path $file.FullName)

    if ($imports.Count -eq 0) {
        $unchanged++
        continue
    }

    $unknown = @($imports | Where-Object { $_.Form -eq 'Unrecognised' })
    foreach ($item in $unknown) {
        Write-Warning ("Update-PfbTestModuleImport: unrecognised manifest -Force import at {0}:{1} -- '{2}'. Not rewritten." -f
            $file.Name, $item.Line, $item.Text)
        $unrecognised += [PSCustomObject]@{ File = $file.Name; Line = $item.Line; Text = $item.Text }
    }

    $rewritable = @($imports | Where-Object { $_.Form -ne 'Unrecognised' })
    if ($rewritable.Count -eq 0) { continue }

    # Detect from the file, not from [Environment]::NewLine: the platform does not decide
    # this, the checked-out file does.
    $nl = "`n"
    if ($content -match "`r`n") { $nl = "`r`n" }

    # Splice back-to-front so earlier offsets stay valid.
    $updated = $content
    foreach ($item in ($rewritable | Sort-Object StartOffset -Descending)) {
        $lineStart = $updated.LastIndexOf($nl, $item.StartOffset)
        if ($lineStart -lt 0) { $indentStart = 0 } else { $indentStart = $lineStart + $nl.Length }
        $indent = ''
        for ($i = $indentStart; $i -lt $item.StartOffset; $i++) {
            $ch = $updated[$i]
            if ($ch -ne ' ' -and $ch -ne "`t") { break }
            $indent += $ch
        }

        if ($item.Form -eq 'PassThru') {
            $replacement = $dotSourceLine + $nl + $indent + '$script:module = Import-PfbTestModule'
        }
        else {
            $replacement = $dotSourceLine + $nl + $indent + '$null = Import-PfbTestModule'
        }

        if ($item.Form -eq 'PassThru') {
            $head = $updated.Substring(0, $indentStart) + $indent
        }
        else {
            $head = $updated.Substring(0, $item.StartOffset)
        }
        $tail = $updated.Substring($item.EndOffset)
        $updated = $head + $replacement + $tail
    }

    if ($updated -eq $content) {
        $unchanged++
        continue
    }

    $changed += $file.FullName
    if ($PSCmdlet.ShouldProcess($file.FullName, 'Rewrite manifest import to use Import-PfbTestModule')) {
        # WriteAllText with a BOM-less UTF8 encoding, not Set-Content: no test file has a
        # BOM, and Set-Content would append its own trailing newline.
        [System.IO.File]::WriteAllText($file.FullName, $updated, (New-Object System.Text.UTF8Encoding($false)))
    }
}

Write-Verbose ("Test-module imports: {0} changed, {1} already current, {2} unrecognised." -f
    $changed.Count, $unchanged, $unrecognised.Count)

[PSCustomObject]@{
    Changed      = $changed
    Unchanged    = $unchanged
    Unrecognised = $unrecognised
}
