#Requires -Version 5.1
<#
.SYNOPSIS
    Inserts the empty-pipeline guard statement into every collect-then-request cmdlet under
    Public/, and reports the population it derived rather than one it was handed.
.DESCRIPTION
    A cmdlet that COLLECTS pipeline input in `process` and issues ONE request in a NAMED
    `end` block turns an empty pipeline into an unfiltered request: nothing was collected,
    so no selector reaches the query, so the request asks for everything. Private/
    Test-PfbEmptyPipelineRead.ps1 decides that at runtime; this script writes the single
    call site into each qualifying cmdlet:

        if (Test-PfbEmptyPipelineRead -Caller $PSCmdlet -QueryParams $queryParams) { return }

    Everything here is decided from the ABSTRACT SYNTAX TREE, never from a regex over the
    text. Two reasons, both measured:

      * The parser SYNTHESISES an `end` block for any function that declared no named
        blocks at all, and marks it `Unnamed`. `$null -ne $Body.EndBlock` is therefore true
        for nearly every function in the module and selects hundreds of files that are not
        collect-then-request at all. The qualifying predicate is process block present AND
        end block present AND NOT Unnamed.

      * This module writes attribute arguments bare -- `ValueFromPipeline`, not
        `ValueFromPipeline = $true` -- so a text search for the assignment form silently
        UNDER-counts the population instead of failing.

    Insertion point: walk up from the `Invoke-PfbApiRequest` CommandAst to the direct child
    statement of the end block, and insert above THAT. The request is often nested inside a
    `try` or an assignment; inserting at the command's own line would place the guard inside
    the try body (where it still returns, but reads as if the catch were the protected path)
    or, worse, inside a multi-line command expression.

    Routing of the shapes this script will not write, in this exact order:

      1. Already carries a Test-PfbEmptyPipelineRead call in the same end block -> reported
         AlreadyPresent. This runs FIRST so that the hand-edited outliers below become
         AlreadyPresent once a human has placed their guard, instead of being reported as
         skipped forever and never reaching a drift fixed point.
      2. On the explicit human-review list (-HumanReviewFile) -> SkippedNeedsHuman. These
         are files whose shape is ordinary but where the generator's usual position would
         produce an INERT guard. Get-PfbRemoteArray writes `current_fleet_only` on both
         branches of an if/else, so its query hashtable is never empty by the time the
         request is issued; its guard belongs above that write and only a human can say so.
      3. More than one request in the end block, or SupportsShouldProcess ->
         SkippedNeedsHuman. Two requests need one dominating guard rather than two, and a
         ShouldProcess cmdlet must return BEFORE it prompts, not after.

    A file on the human-review list that matches nothing under the real Public/ root is a
    hard error: a renamed or deleted cmdlet must not quietly leave the list protecting
    nothing. That check is scoped to the real tree so synthetic fixture roots in the tests
    are not required to contain every listed name.
.PARAMETER PublicRoot
    Directory holding the cmdlet files. Defaults to Public/ under the repo root. Supplying
    it explicitly also disables the human-review list integrity check, since a fixture root
    legitimately contains only the shapes under test.
.PARAMETER HumanReviewFile
    Leaf file names the generator must refuse to edit even when their shape is ordinary.
.OUTPUTS
    A summary object with:
      Inserted          - files this run changed (or, under -WhatIf, would change)
      AlreadyPresent    - qualifying files that already carry the guard
      SkippedNeedsHuman - qualifying files a human must edit by hand
.EXAMPLE
    ./tools/Update-PfbEmptyPipelineGuards.ps1 -WhatIf
    Report what would change, and act as the drift check: a non-zero Inserted count on a
    clean tree means a new cmdlet shipped without its guard.
.EXAMPLE
    ./tools/Update-PfbEmptyPipelineGuards.ps1 -Confirm:$false
    Insert the guards in place.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$PublicRoot,

    [string[]]$HumanReviewFile = @('Get-PfbRemoteArray.ps1')
)

$ErrorActionPreference = 'Stop'

$script:GuardStatement = 'if (Test-PfbEmptyPipelineRead -Caller $PSCmdlet -QueryParams $queryParams) { return }'
$script:RequestCommand = 'Invoke-PfbApiRequest'
$script:PredicateCommand = 'Test-PfbEmptyPipelineRead'

$repoRoot = Split-Path -Parent $PSScriptRoot
$isRealTree = -not $PSBoundParameters.ContainsKey('PublicRoot')
if (-not $PublicRoot) { $PublicRoot = Join-Path $repoRoot 'Public' }
if (-not (Test-Path -LiteralPath $PublicRoot)) {
    throw "Public cmdlet root not found at '$PublicRoot'."
}

function Get-PfbCommandCall {
    <#
        Every CommandAst under $Scope invoking $Name. GetCommandName() returns $null for a
        dynamically invoked command, which is why it is compared rather than coerced.
    #>
    param(
        [System.Management.Automation.Language.Ast]$Scope,
        [string]$Name
    )
    return @($Scope.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.CommandAst] -and
                $node.GetCommandName() -eq $Name
            }, $true))
}

function Get-PfbTopLevelStatement {
    <#
        Walks up from $Node to the statement that is a DIRECT child of $EndBlock. That
        statement, not the command's own line, is the insertion anchor: it is what a `try`
        or an assignment wrapping the request resolves to.
    #>
    param(
        [System.Management.Automation.Language.Ast]$Node,
        [System.Management.Automation.Language.Ast]$EndBlock
    )
    $current = $Node
    while ($null -ne $current.Parent -and $current.Parent -ne $EndBlock) {
        $current = $current.Parent
    }
    if ($current.Parent -ne $EndBlock) {
        throw 'Could not walk from the request call up to a direct child of the end block.'
    }
    return $current
}

$files = @(Get-ChildItem -LiteralPath $PublicRoot -Recurse -Filter '*.ps1' -File | Sort-Object FullName)

if ($isRealTree) {
    $leafNames = @($files | ForEach-Object { $_.Name })
    foreach ($listed in $HumanReviewFile) {
        if ($leafNames -notcontains $listed) {
            throw ("Human-review list entry '$listed' matches no file under '$PublicRoot'. " +
                'Remove the entry or correct it -- a stale entry protects nothing while ' +
                'still reading as though it did.')
        }
    }
}

$inserted = @()
$alreadyPresent = @()
$skippedNeedsHuman = @()

foreach ($file in $files) {
    # Parse the SAME string that is later spliced and written back. Extent offsets index
    # into the parsed text, so reading once and parsing that text keeps the offsets and the
    # splice provably in step.
    $original = [System.IO.File]::ReadAllText($file.FullName)

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput(
        $original, $file.FullName, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) { throw "Parse errors in '$($file.FullName)'." }

    $functions = $ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
        }, $true)

    # Offsets collected per file, then applied in DESCENDING order so an earlier insertion
    # cannot shift a later one. One qualifying function per file is the norm here, but the
    # generator must not silently corrupt a file that ever holds two.
    $insertOffsets = @()
    $fileState = $null   # 'AlreadyPresent' or 'SkippedNeedsHuman', first one wins

    foreach ($function in $functions) {
        $endBlock = $function.Body.EndBlock
        $qualifies = ($null -ne $function.Body.ProcessBlock) -and
            ($null -ne $endBlock) -and
            (-not $endBlock.Unnamed)
        if (-not $qualifies) { continue }

        $calls = Get-PfbCommandCall -Scope $endBlock -Name $script:RequestCommand
        if ($calls.Count -eq 0) { continue }

        # 1. Already guarded.
        if ((Get-PfbCommandCall -Scope $endBlock -Name $script:PredicateCommand).Count -gt 0) {
            if (-not $fileState) { $fileState = 'AlreadyPresent' }
            continue
        }

        # 2. Explicit human-review list.
        if ($HumanReviewFile -contains $file.Name) {
            $fileState = 'SkippedNeedsHuman'
            continue
        }

        # 3. Structural outliers.
        $hasShouldProcess = $function.Extent.Text -match 'SupportsShouldProcess'
        if ($calls.Count -ne 1 -or $hasShouldProcess) {
            $fileState = 'SkippedNeedsHuman'
            continue
        }

        $statement = Get-PfbTopLevelStatement -Node $calls[0] -EndBlock $endBlock
        $insertOffsets += $statement.Extent.StartOffset
    }

    # A file needing a human edit is never partly written, even if another function in it
    # would have qualified.
    if ($fileState -eq 'SkippedNeedsHuman') {
        $skippedNeedsHuman += $file.FullName
        continue
    }
    if ($insertOffsets.Count -eq 0) {
        if ($fileState -eq 'AlreadyPresent') { $alreadyPresent += $file.FullName }
        continue
    }

    # Adopt the target file's own newline style. The repo commits LF blobs, so a checkout
    # is CRLF on Windows and LF elsewhere; emitting a fixed style would rewrite every line
    # of every file instead of adding one.
    $newline = if ($original.Contains("`r`n")) { "`r`n" } else { "`n" }

    $updated = $original
    foreach ($offset in ($insertOffsets | Sort-Object -Descending)) {
        # The statement's leading whitespace, taken from the text between the preceding
        # newline and the statement. Tabs survive because they are copied, not assumed.
        $lineStart = $updated.LastIndexOf("`n", $offset - 1) + 1
        $indent = $updated.Substring($lineStart, $offset - $lineStart)
        if ($indent -match '\S') {
            throw ("The request statement in '$($file.FullName)' does not start its own " +
                'line; refusing to splice a guard into shared line content.')
        }
        $updated = $updated.Substring(0, $lineStart) +
            $indent + $script:GuardStatement + $newline +
            $updated.Substring($lineStart)
    }

    $inserted += $file.FullName
    if ($PSCmdlet.ShouldProcess($file.FullName, 'Insert empty-pipeline guard')) {
        # WriteAllText with an explicit BOM-less UTF8 encoding: no Public/*.ps1 carries a
        # BOM, and Set-Content -Encoding UTF8 adds one under Windows PowerShell 5.1.
        [System.IO.File]::WriteAllText(
            $file.FullName,
            $updated,
            (New-Object System.Text.UTF8Encoding($false)))
    }
}

Write-Verbose ("Empty-pipeline guards: {0} inserted, {1} already present, {2} awaiting a human edit." -f
    $inserted.Count, $alreadyPresent.Count, $skippedNeedsHuman.Count)

[PSCustomObject]@{
    Inserted          = @($inserted)
    AlreadyPresent    = @($alreadyPresent)
    SkippedNeedsHuman = @($skippedNeedsHuman)
}
