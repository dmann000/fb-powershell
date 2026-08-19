#Requires -Version 5.1
<#
.SYNOPSIS
    The single AST predicate over test-file module imports.
.DESCRIPTION
    Two consumers depend on this file and they must never disagree:
    tools/Update-PfbTestModuleImport.ps1 rewrites what it finds, and
    Tests/TestModuleImportGuard.Tests.ps1 asserts there is nothing left to find.
    A second, drifting copy of this logic would let the rewriter miss a site the
    guard still forbids, or vice versa.

    Everything here is AST-based on purpose. Two lines under Tests/ mention
    Import-Module and must NEVER be rewritten -- the separate-runspace
    $ps.AddCommand('Import-Module') in ArrayConnection.ShouldProcessTarget.Tests.ps1
    and `Mock ... Import-Module { }` in Get-PfbApiTokenViaSsh.Tests.ps1. Neither is
    a CommandAst named Import-Module, so an AST predicate cannot touch them. A
    negative-lookahead regex would be a permanent liability by comparison.

    5.1 CONSTRAINT: this is dot-sourced by a guard test that runs on Windows
    PowerShell 5.1 as well as pwsh 7. No ternaries, no ??, no pipeline chain operators.

    Deliberately does NOT call Set-StrictMode. This file is dot-sourced into a Pester
    BeforeAll scope, where a strict-mode setting would leak into unrelated test code
    in the same container and red it for reasons that have nothing to do with this library.
#>

$script:PfbManifestLeafName = 'PureStorageFlashBladePowerShell.psd1'
$script:PfbModuleName = 'PureStorageFlashBladePowerShell'

function Get-PfbTestImportAst {
    <#
        Parse one file and return every CommandAst in it. Throws on a parse error rather
        than returning a partial tree -- a file we cannot parse is a file we cannot make
        any claim about, and silently returning zero matches would read as "clean".
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    if ($null -ne $errors -and $errors.Count -gt 0) {
        throw ("Get-PfbTestImportAst: '{0}' failed to parse: {1}" -f $Path, $errors[0].Message)
    }
    return $ast
}

function Get-PfbCommandAst {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Ast)

    return @($Ast.FindAll({
        param($node)
        return ($node -is [System.Management.Automation.Language.CommandAst])
    }, $true))
}

function Get-PfbTestManifestImport {
    <#
        Returns one record per `Import-Module <manifest> -Force` in the file, classified
        into one of the five known call-site forms, or 'Unrecognised'.

        Unrecognised is never dropped: a silent skip reads as "covered everything", which
        is the specific mistake tools/Update-PfbContextHelp.ps1 documents at length.
        Offsets are byte-exact so a caller can splice without re-finding the text.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    $ast = Get-PfbTestImportAst -Path $Path
    $results = @()

    foreach ($command in (Get-PfbCommandAst -Ast $ast)) {
        $name = $command.GetCommandName()
        if ($name -ne 'Import-Module') { continue }

        $hasForce = $false
        $hasPassThru = $false
        $moduleArgument = $null

        # Element 0 is the command name itself. A bare (unnamed) argument is the module.
        for ($i = 1; $i -lt $command.CommandElements.Count; $i++) {
            $element = $command.CommandElements[$i]
            if ($element -is [System.Management.Automation.Language.CommandParameterAst]) {
                if ($element.ParameterName -eq 'Force') { $hasForce = $true }
                if ($element.ParameterName -eq 'PassThru') { $hasPassThru = $true }
                if ($element.ParameterName -eq 'Name' -and $null -ne $element.Argument) {
                    $moduleArgument = $element.Argument
                }
                continue
            }
            if ($null -eq $moduleArgument) { $moduleArgument = $element }
        }

        if (-not $hasForce) { continue }
        if ($null -eq $moduleArgument) { continue }

        $argumentText = $moduleArgument.Extent.Text
        $namesManifest = ($argumentText -match [regex]::Escape($script:PfbManifestLeafName)) -or
            ($argumentText -eq '$manifest') -or ($argumentText -eq '$script:manifest')
        if (-not $namesManifest) { continue }

        $form = 'Unrecognised'
        if ($hasPassThru) {
            $form = 'PassThru'
        }
        elseif ($argumentText -eq '$manifest') {
            $form = 'Manifest'
        }
        elseif ($argumentText -eq '$script:manifest') {
            $form = 'ScriptManifest'
        }
        elseif ($argumentText -match '^"\$PSScriptRoot/\.\./PureStorageFlashBladePowerShell\.psd1"$') {
            $form = 'PSScriptRoot'
        }
        elseif ($argumentText -match "^\(Join-Path \`$\w+ '$([regex]::Escape($script:PfbManifestLeafName))'\)$") {
            $form = 'JoinPath'
        }
        elseif (($argumentText -match 'Join-Path') -and
            ($argumentText -match [regex]::Escape($script:PfbManifestLeafName))) {
            # Sixth form, added by PR #125 (Tests/Test-PfbEmptyPipelineRead.Tests.ps1:4):
            #     Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) `
            #             'PureStorageFlashBladePowerShell.psd1') -Force
            # Deliberately AFTER the specific JoinPath arm, and keyed on structure rather than
            # on an exact spelling, because the extent carries an embedded backtick and newline
            # that no single-line anchored regex can match. Safe to rewrite sight-unseen because
            # the replacement never references the old argument, and no manifest -Force import in
            # this tree carries any parameter other than Force/PassThru -- so there is no import
            # whose extra parameters Import-PfbTestModule would fail to reproduce.
            $form = 'NestedJoinPath'
        }

        $results += [PSCustomObject]@{
            Form        = $form
            StartOffset = $command.Extent.StartOffset
            EndOffset   = $command.Extent.EndOffset
            Text        = $command.Extent.Text
            Line        = $command.Extent.StartLineNumber
        }
    }

    return $results
}

function Get-PfbExportedFunctionName {
    <#
        The exported-function list, read statically from the manifest. Verified to be an
        explicit literal array in PureStorageFlashBladePowerShell.psd1 -- not '*' and not
        a wildcard -- which is what lets the guard's obligation predicate track the module
        automatically instead of carrying a hand-maintained name table.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$ManifestPath)

    $data = Import-PowerShellDataFile -LiteralPath $ManifestPath
    return @($data.FunctionsToExport)
}

function Test-PfbTestModuleUsage {
    <#
        Does this test file oblige itself to load the module? True if it calls an EXPORTED
        function, or names the module in InModuleScope, or names it in Mock -ModuleName.

        Rules 2 and 3 are not redundant with rule 1: the files that test PRIVATE functions
        (Get-PfbCapabilityMap, Get-PfbVersionMap) never call an exported name, and reach
        module internals through InModuleScope instead.

        Matching is on CommandAst command names only. A cmdlet name inside a string -- a
        Should -Throw message, a comment, a -ParameterFilter -- is not a call.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$ExportedFunction
    )

    $exportedLookup = @{}
    foreach ($name in $ExportedFunction) { $exportedLookup[$name] = $true }

    $reasons = @()
    $callsHelper = $false

    foreach ($command in (Get-PfbCommandAst -Ast (Get-PfbTestImportAst -Path $Path))) {
        $name = $command.GetCommandName()
        if ([string]::IsNullOrEmpty($name)) { continue }

        if ($name -eq 'Import-PfbTestModule') {
            $callsHelper = $true
            continue
        }
        if ($exportedLookup.ContainsKey($name)) {
            $reasons += ("calls exported cmdlet {0} (line {1})" -f $name, $command.Extent.StartLineNumber)
            continue
        }
        if ($name -eq 'InModuleScope' -and $command.Extent.Text -match [regex]::Escape($script:PfbModuleName)) {
            $reasons += ("InModuleScope {0} (line {1})" -f $script:PfbModuleName, $command.Extent.StartLineNumber)
            continue
        }
        if ($name -eq 'Mock') {
            for ($i = 1; $i -lt $command.CommandElements.Count; $i++) {
                $element = $command.CommandElements[$i]
                if ($element -is [System.Management.Automation.Language.CommandParameterAst] -and
                    $element.ParameterName -eq 'ModuleName') {
                    $valueText = ''
                    if ($null -ne $element.Argument) {
                        $valueText = $element.Argument.Extent.Text
                    }
                    elseif (($i + 1) -lt $command.CommandElements.Count) {
                        $valueText = $command.CommandElements[$i + 1].Extent.Text
                    }
                    if ($valueText -match [regex]::Escape($script:PfbModuleName)) {
                        $reasons += ("Mock -ModuleName {0} (line {1})" -f $script:PfbModuleName, $command.Extent.StartLineNumber)
                    }
                }
            }
        }
    }

    return [PSCustomObject]@{
        Uses        = ($reasons.Count -gt 0)
        Reasons     = @($reasons)
        CallsHelper = $callsHelper
    }
}
