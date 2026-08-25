#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

# Comment-based-help coverage sweep. Same rationale and same shape as
# Tests/PfbEmptyPipelineGuardCoverage.Tests.ps1 and Tests/PfbShouldProcessCoverage.Tests.ps1:
# Public/ is a 544-cmdlet generated-and-hand-edited population, and undocumented surface is exactly
# the kind of decay nothing else notices -- every other test in Tests/ is scoped to one cmdlet's
# behaviour and none of them looks at help at all.
#
# Two directions of drift matter, and only one of them is visible to a coverage count:
#   - a parameter with no .PARAMETER entry (the count sees it);
#   - a .PARAMETER entry naming a parameter that no longer exists (the count does NOT -- rename a
#     parameter without renaming its help and the total stays put while the help is now wrong).
# Both are asserted below, by NAME MATCHING rather than by comparing counts.
#
# Deliberately NOT Get-Help. Get-Help requires importing the module, which drags module state into
# a file that is otherwise pure parsing; it also resolves help from external MAML and from the
# .NOTES blocks tools/Update-PfbContextHelp.ps1 injects, which is a different question from
# "is the source comment correct". Token-stream parsing answers the source question directly.

BeforeAll {
    $script:moduleRoot = Split-Path -Parent $PSScriptRoot
    $script:publicRoot = Join-Path $script:moduleRoot 'Public'

    # Split a comment-based help block into its sections.
    #
    # Returns one record per help keyword, in source order, carrying the keyword, its argument
    # (the parameter name, for .PARAMETER) and the body text beneath it.
    #
    # The keyword line must be the WHOLE trimmed line -- `^\.([A-Za-z]+)(\s+(\S+))?$`. Anchoring
    # both ends is what keeps an .EXAMPLE body from being misread as a section: an example line such
    # as `.\tools\Update-PfbContextHelp.ps1 -WhatIf` starts with a dot but does not match, and
    # neither does prose that happens to begin a sentence with one.
    function Get-PfbHelpSection {
        param(
            [string]$Text
        )

        # Strip the block delimiters so `<#` and `#>` cannot land inside a body and make an
        # otherwise-empty section look populated.
        $body = $Text -replace '^\s*<#', '' -replace '#>\s*$', ''

        $sections = [System.Collections.Generic.List[object]]::new()
        $current = $null
        foreach ($line in ($body -split "\r?\n")) {
            if ($line.Trim() -match '^\.([A-Za-z]+)(?:\s+(\S+))?$') {
                $current = [PSCustomObject]@{
                    Keyword   = $Matches[1].ToUpperInvariant()
                    Argument  = $Matches[2]
                    BodyLines = [System.Collections.Generic.List[string]]::new()
                }
                $sections.Add($current)
                continue
            }
            if ($null -ne $current) { $current.BodyLines.Add($line) }
        }
        return $sections
    }

    # Reduce one cmdlet to the facts the assertions below need.
    function Get-PfbHelpRecord {
        param(
            [System.Management.Automation.Language.FunctionDefinitionAst]$Function,
            [System.Management.Automation.Language.Token[]]$Tokens,
            [string]$File
        )

        $declared = @()
        $paramBlock = $Function.Body.ParamBlock
        if ($null -ne $paramBlock) {
            $declared = @($paramBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
        }

        # Locate the help block from the TOKEN stream, not by regexing the file: a comment token is
        # the only thing that is definitely a comment, and the AST has no node for one.
        #
        # A `.SYNOPSIS` keyword line is the marker (anchored, per Get-PfbHelpSection's reasoning),
        # so a .DESCRIPTION or .EXAMPLE that merely mentions the word cannot be mistaken for the
        # block.
        #
        # The block must sit INSIDE the function body, and must not belong to a nested helper.
        # This is narrower than "a .SYNOPSIS somewhere near the function", deliberately: an earlier
        # draft accepted the nearest block ABOVE the function as a fallback, and that admitted two
        # shapes that report as fully documented while `Get-Help` shows nothing --
        #   - a file-header block a dozen lines above the function, holding unrelated prose;
        #   - a block belonging to a nested helper, when the cmdlet itself has none.
        # Both were probed against Get-Help; neither attaches. The `above` placement IS legal
        # PowerShell, but only when adjacent, and a gate that cannot tell adjacent from distant is
        # a gate that false-greens. All 544 blocks in Public/ are inside their function, so
        # requiring that is strictly stronger here rather than a restriction anyone has to work
        # around. The 'help-above-function' and 'nested-helper-only' fixtures below pin both.
        $candidates = @($Tokens | Where-Object {
                $_.Kind -eq [System.Management.Automation.Language.TokenKind]::Comment -and
                $_.Text -match '(?m)^\s*\.SYNOPSIS\s*$'
            })

        $nestedFunctions = @($Function.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
                }, $true) | Where-Object { -not [object]::ReferenceEquals($_, $Function) })

        $help = $null
        foreach ($candidate in $candidates) {
            if ($candidate.Extent.StartOffset -lt $Function.Extent.StartOffset) { continue }
            if ($candidate.Extent.EndOffset -gt $Function.Extent.EndOffset) { continue }

            $inNested = $false
            foreach ($nested in $nestedFunctions) {
                if ($candidate.Extent.StartOffset -ge $nested.Extent.StartOffset -and
                    $candidate.Extent.EndOffset -le $nested.Extent.EndOffset) {
                    $inNested = $true
                    break
                }
            }
            if ($inNested) { continue }

            # Tokens arrive in source order, so the first surviving candidate is the cmdlet's own.
            $help = $candidate
            break
        }

        $synopsisEmpty = $false
        $seenSynopsis = $false
        $documented = @()
        $emptyParameterSections = @()
        $namelessParameterSections = 0

        if ($null -ne $help) {
            $sections = Get-PfbHelpSection -Text $help.Text

            foreach ($section in $sections) {
                $sectionBody = ($section.BodyLines -join "`n").Trim()

                if ($section.Keyword -eq 'SYNOPSIS') {
                    # First .SYNOPSIS wins -- enforced, not merely described. The previous guard
                    # was `-not $synopsisEmpty`, which only prevented un-setting a flag that is
                    # never un-set: given a populated first .SYNOPSIS and an empty second, the loop
                    # reached the second and flagged the cmdlet. Wrong direction is a false
                    # positive rather than a false green, but the comment claimed a behaviour the
                    # code did not have, which is the defect class 3c98a7f already paid for.
                    if (-not $seenSynopsis) {
                        $seenSynopsis = $true
                        $synopsisEmpty = [string]::IsNullOrWhiteSpace($sectionBody)
                    }
                    continue
                }

                if ($section.Keyword -ne 'PARAMETER') { continue }

                if ([string]::IsNullOrEmpty($section.Argument)) {
                    # `.PARAMETER` with no name documents nothing and names nothing, so neither the
                    # coverage nor the orphan assertion would see it. Counted separately.
                    $namelessParameterSections++
                    continue
                }

                $documented += $section.Argument
                if ([string]::IsNullOrWhiteSpace($sectionBody)) {
                    $emptyParameterSections += $section.Argument
                }
            }
        }

        # Case-insensitive both ways: PowerShell parameter names are case-insensitive, so a
        # `.PARAMETER filter` documenting `[string]$Filter` is correct help and must not read as a
        # miss in one direction and an orphan in the other.
        $missing = @($declared | Where-Object {
                $name = $_
                -not (@($documented | Where-Object { $_ -eq $name }).Count)
            })
        $orphaned = @($documented | Where-Object {
                $name = $_
                -not (@($declared | Where-Object { $_ -eq $name }).Count)
            })
        $duplicated = @($documented | Group-Object | Where-Object { $_.Count -gt 1 } |
            ForEach-Object { $_.Name })

        [PSCustomObject]@{
            File                      = $File
            Function                  = $Function.Name
            Line                      = $Function.Extent.StartLineNumber
            HasHelpBlock              = ($null -ne $help)
            SynopsisEmpty             = $synopsisEmpty
            DeclaredParameters        = $declared
            DocumentedParameters      = $documented
            MissingParameters         = $missing
            OrphanedParameters        = $orphaned
            DuplicatedParameters      = $duplicated
            EmptyParameterSections    = $emptyParameterSections
            NamelessParameterSections = $namelessParameterSections
        }
    }

    # One record per cmdlet. FindAll(..., $false) takes only DEPTH-0 function definitions so a
    # nested helper is never mistaken for a cmdlet, and the first of those is the cmdlet -- matching
    # the file-per-cmdlet layout Public/ uses throughout.
    $script:cmdlets = @(
        foreach ($file in (Get-ChildItem -Path $script:publicRoot -Filter '*.ps1' -Recurse -File)) {
            $relative = $file.FullName.Substring($script:moduleRoot.Length).TrimStart('\', '/').Replace('\', '/')

            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $file.FullName, [ref]$tokens, [ref]$errors)
            if ($errors.Count -gt 0) {
                throw "Parse errors in ${relative}: $(($errors | ForEach-Object { $_.Message }) -join '; ')"
            }

            $functions = @($ast.FindAll({
                        param($node)
                        $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
                    }, $false))
            if ($functions.Count -eq 0) { continue }

            Get-PfbHelpRecord -Function $functions[0] -Tokens $tokens -File $relative
        }
    )

    $script:withParameters = @($script:cmdlets | Where-Object { $_.DeclaredParameters.Count -gt 0 })
    $script:totalDeclared = (@($script:cmdlets | ForEach-Object { $_.DeclaredParameters.Count }) |
        Measure-Object -Sum).Sum
    $script:totalDocumented = (@($script:cmdlets | ForEach-Object { $_.DocumentedParameters.Count }) |
        Measure-Object -Sum).Sum
}

Describe 'Comment-based help coverage' {

    It 'scans a population large enough for the other assertions to mean something' {
        # THE ANTI-VACUOUS FLOOR. Every assertion below is "the set of offenders is empty". If the
        # Public/ glob returned nothing, or the depth-0 function walk regressed, all of them would
        # pass having examined zero cmdlets and the gate would report green while checking nothing.
        #
        # Floors, not pins. The population grows -- pinning 544 turns every legitimate new cmdlet
        # into an unrelated red build, which is how a gate ends up disabled. Measured on main
        # 2026-08-24: 544 cmdlets, 542 with parameters, 2860 declared parameters, 2845 documented
        # (2860 after the six help fixes that land with this file).
        #
        # The derived floors carry as much weight as the total. A total-only floor survives intact
        # while a regression in the token-stream help lookup drives every DocumentedParameters to
        # empty -- which would empty the orphan assertion (nothing documented, nothing to orphan)
        # while making the coverage assertion red for the right reason. Flooring the documented
        # total makes that failure explicit instead of half-visible.
        $script:cmdlets.Count | Should -BeGreaterOrEqual 500
        $script:withParameters.Count |
            Should -BeGreaterOrEqual 500 -Because 'the parameter assertions are scoped to cmdlets that declare parameters'
        $script:totalDeclared |
            Should -BeGreaterOrEqual 2500 -Because 'a regression in the ParamBlock walk empties the coverage assertion without emptying the cmdlet count'
        $script:totalDocumented |
            Should -BeGreaterOrEqual 2500 -Because 'a regression in the help-block lookup empties the orphan assertion without emptying the cmdlet count'
    }

    It 'gives every cmdlet a .SYNOPSIS with text in it' {
        # Presence and content in one assertion, because they fail together in practice: a block
        # that lost its text is the same defect as a block that was never written, and splitting
        # them would let a bare `.SYNOPSIS` line satisfy a presence check while documenting nothing.
        $missingBlock = @($script:cmdlets | Where-Object { -not $_.HasHelpBlock })
        $missingDetail = @($missingBlock | ForEach-Object { "$($_.File): $($_.Function)" }) -join "`n"
        $missingDetail | Should -BeNullOrEmpty -Because "every public cmdlet needs comment-based help with a .SYNOPSIS; offenders:`n$missingDetail"

        $emptySynopsis = @($script:cmdlets | Where-Object { $_.SynopsisEmpty })
        $emptyDetail = @($emptySynopsis | ForEach-Object { "$($_.File): $($_.Function)" }) -join "`n"
        $emptyDetail | Should -BeNullOrEmpty -Because "a .SYNOPSIS with no text satisfies a presence check while documenting nothing; offenders:`n$emptyDetail"
    }

    It 'documents every declared parameter, matching by name' {
        # By NAME, never by count. A count comparison passes when a file has the right number of
        # .PARAMETER entries naming the wrong parameters -- which is exactly what a rename produces.
        $offenders = @($script:withParameters | Where-Object { $_.MissingParameters.Count -gt 0 })
        $detail = @($offenders | ForEach-Object {
                "$($_.File): $($_.Function) -- undocumented: $($_.MissingParameters -join ', ')"
            }) -join "`n"
        $detail | Should -BeNullOrEmpty -Because "every declared parameter needs a .PARAMETER entry; offenders:`n$detail"
    }

    It 'names no parameter that does not exist' {
        # The drift direction a coverage count cannot see. Rename or remove a parameter without
        # touching its help and the documented total is unchanged, so coverage still reads 100%
        # while Get-Help now describes a parameter the cmdlet does not have.
        $orphans = @($script:cmdlets | Where-Object { $_.OrphanedParameters.Count -gt 0 })
        $orphanDetail = @($orphans | ForEach-Object {
                "$($_.File): $($_.Function) -- documents nonexistent: $($_.OrphanedParameters -join ', ')"
            }) -join "`n"
        $orphanDetail | Should -BeNullOrEmpty -Because "a .PARAMETER entry naming a parameter that does not exist is help describing a cmdlet that no longer exists; offenders:`n$orphanDetail"

        # Two adjacent malformations, both invisible to the assertions above. A duplicate entry
        # means one of the two is stale (or a copy-paste that should have been renamed); a bare
        # `.PARAMETER` with no name documents nothing and orphans nothing. Both measured 0 on main.
        $duplicates = @($script:cmdlets | Where-Object { $_.DuplicatedParameters.Count -gt 0 })
        $duplicateDetail = @($duplicates | ForEach-Object {
                "$($_.File): $($_.Function) -- duplicated: $($_.DuplicatedParameters -join ', ')"
            }) -join "`n"
        $duplicateDetail | Should -BeNullOrEmpty -Because "a duplicated .PARAMETER entry means one of the two is stale; offenders:`n$duplicateDetail"

        $nameless = @($script:cmdlets | Where-Object { $_.NamelessParameterSections -gt 0 })
        $namelessDetail = @($nameless | ForEach-Object {
                "$($_.File): $($_.Function) -- $($_.NamelessParameterSections) nameless .PARAMETER"
            }) -join "`n"
        $namelessDetail | Should -BeNullOrEmpty -Because "a .PARAMETER with no name documents nothing and is invisible to both coverage and orphan checks; offenders:`n$namelessDetail"
    }

    It 'gives every .PARAMETER entry a body' {
        # A bare `.PARAMETER Name` followed immediately by the next keyword satisfies the
        # name-matching assertion above while telling the reader nothing. Split out from that
        # assertion because the remedy is different: the entry exists and needs prose, rather than
        # being absent and needing to be added.
        $offenders = @($script:cmdlets | Where-Object { $_.EmptyParameterSections.Count -gt 0 })
        $detail = @($offenders | ForEach-Object {
                "$($_.File): $($_.Function) -- empty: $($_.EmptyParameterSections -join ', ')"
            }) -join "`n"
        $detail | Should -BeNullOrEmpty -Because "a .PARAMETER entry with no text documents nothing; offenders:`n$detail"
    }

    It 'recognises every shape it is meant to flag, and none it is not' {
        # The mutation proof. Every assertion above is "offenders is empty", and on main every one
        # of those sets IS empty -- so a parser bug that returned no sections at all, or that
        # matched nothing, would leave them empty for the wrong reason and the whole file would be
        # green while inert. These fixtures give each predicate a known answer in each direction.
        #
        # The last two are the false-positive guard: an .EXAMPLE body containing a dot-leading line
        # and a .DESCRIPTION containing the word SYNOPSIS must not be misread as section keywords.
        $fixtures = [ordered]@{
            'clean'            = @'
function Get-PfbFixture {
    <#
    .SYNOPSIS
        Retrieves a fixture.
    .PARAMETER Name
        The fixture name.
    .PARAMETER Array
        The connection.
    #>
    [CmdletBinding()]
    param([Parameter()] [string]$Name, [Parameter()] [PSCustomObject]$Array)
}
'@
            'no-help'          = @'
function Get-PfbFixture {
    [CmdletBinding()]
    param([Parameter()] [string]$Name)
}
'@
            'empty-synopsis'   = @'
function Get-PfbFixture {
    <#
    .SYNOPSIS
    .PARAMETER Name
        The fixture name.
    #>
    [CmdletBinding()]
    param([Parameter()] [string]$Name)
}
'@
            'undocumented'     = @'
function Get-PfbFixture {
    <#
    .SYNOPSIS
        Retrieves a fixture.
    .PARAMETER Name
        The fixture name.
    #>
    [CmdletBinding()]
    param([Parameter()] [string]$Name, [Parameter()] [PSCustomObject]$Array)
}
'@
            'orphaned'         = @'
function Get-PfbFixture {
    <#
    .SYNOPSIS
        Retrieves a fixture.
    .PARAMETER Name
        The fixture name.
    .PARAMETER Removed
        A parameter that was deleted from param() without deleting its help.
    #>
    [CmdletBinding()]
    param([Parameter()] [string]$Name)
}
'@
            'renamed'          = @'
function Get-PfbFixture {
    <#
    .SYNOPSIS
        Retrieves a fixture.
    .PARAMETER OldName
        Renamed in param() but not here -- the documented COUNT is still 1 of 1.
    #>
    [CmdletBinding()]
    param([Parameter()] [string]$NewName)
}
'@
            'empty-parameter'  = @'
function Get-PfbFixture {
    <#
    .SYNOPSIS
        Retrieves a fixture.
    .PARAMETER Name
    .EXAMPLE
        Get-PfbFixture
    #>
    [CmdletBinding()]
    param([Parameter()] [string]$Name)
}
'@
            'duplicate'        = @'
function Get-PfbFixture {
    <#
    .SYNOPSIS
        Retrieves a fixture.
    .PARAMETER Name
        First entry.
    .PARAMETER Name
        Second, stale entry.
    #>
    [CmdletBinding()]
    param([Parameter()] [string]$Name)
}
'@
            'nameless'         = @'
function Get-PfbFixture {
    <#
    .SYNOPSIS
        Retrieves a fixture.
    .PARAMETER
        No name on the keyword line.
    #>
    [CmdletBinding()]
    param([Parameter()] [string]$Name)
}
'@
            'dotted-prose'     = @'
function Get-PfbFixture {
    <#
    .SYNOPSIS
        Retrieves a fixture. The word SYNOPSIS appears here and must not start a section.
    .DESCRIPTION
        Regenerate with the tool below.
    .PARAMETER Name
        The fixture name.
    .EXAMPLE
        .\tools\Update-PfbContextHelp.ps1 -WhatIf

        A dot-leading line inside an example body.
    #>
    [CmdletBinding()]
    param([Parameter()] [string]$Name)
}
'@
            'case-mismatch'    = @'
function Get-PfbFixture {
    <#
    .SYNOPSIS
        Retrieves a fixture.
    .PARAMETER name
        Lower-case name for an upper-case parameter -- correct help, not a defect.
    #>
    [CmdletBinding()]
    param([Parameter()] [string]$Name)
}
'@
            # The three below pin the help-block LOOKUP itself, which nothing else here exercises:
            # every fixture above puts the block inside the function, so the placement rule was the
            # one predicate with no coverage in either direction.
            'help-above'       = @'
<#
.SYNOPSIS
    Adjacent help above the function.
.PARAMETER Name
    The fixture name.
#>
function Get-PfbFixture {
    [CmdletBinding()]
    param([Parameter()] [string]$Name)
}
'@
            'distant-header'   = @'
<#
.SYNOPSIS
    File header for a script, not help for the function far below it.
.DESCRIPTION
    Unrelated prose that documents the file rather than the cmdlet.
#>

# Some other commentary sits between the header and the function.

function Get-PfbFixture {
    [CmdletBinding()]
    param([Parameter()] [string]$Name)
}
'@
            'nested-only'      = @'
function Get-PfbFixture {
    [CmdletBinding()]
    param([Parameter()] [string]$Name)

    function Get-PfbInnerHelper {
        <#
        .SYNOPSIS
            Belongs to the nested helper, not to the cmdlet.
        .PARAMETER Name
            The helper's own parameter.
        #>
        param([string]$Name)
    }
}
'@
            'second-synopsis'  = @'
function Get-PfbFixture {
    <#
    .SYNOPSIS
        A populated first synopsis.
    .PARAMETER Name
        The fixture name.
    .SYNOPSIS
    #>
    [CmdletBinding()]
    param([Parameter()] [string]$Name)
}
'@
        }

        $records = [ordered]@{}
        foreach ($label in $fixtures.Keys) {
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseInput(
                $fixtures[$label], [ref]$tokens, [ref]$errors)
            if ($errors.Count -gt 0) {
                throw "Parse errors in ${label}: $(($errors | ForEach-Object { $_.Message }) -join '; ')"
            }
            $fn = $ast.Find({
                    param($node)
                    $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
                }, $true)
            $records[$label] = Get-PfbHelpRecord -Function $fn -Tokens $tokens -File $label
        }

        # A clean cmdlet must produce NO findings at all. Without this every other expectation
        # below could be satisfied by a parser that flags everything.
        $records['clean'].HasHelpBlock | Should -BeTrue
        $records['clean'].SynopsisEmpty | Should -BeFalse
        $records['clean'].DocumentedParameters.Count | Should -Be 2
        $records['clean'].MissingParameters | Should -BeNullOrEmpty
        $records['clean'].OrphanedParameters | Should -BeNullOrEmpty
        $records['clean'].DuplicatedParameters | Should -BeNullOrEmpty
        $records['clean'].EmptyParameterSections | Should -BeNullOrEmpty
        $records['clean'].NamelessParameterSections | Should -Be 0

        $records['no-help'].HasHelpBlock | Should -BeFalse
        $records['empty-synopsis'].HasHelpBlock | Should -BeTrue
        $records['empty-synopsis'].SynopsisEmpty | Should -BeTrue

        $records['undocumented'].MissingParameters | Should -Be @('Array')

        $records['orphaned'].OrphanedParameters | Should -Be @('Removed')
        $records['orphaned'].MissingParameters | Should -BeNullOrEmpty

        # The rename case is the whole reason assertion 3 exists: counts match exactly (1 declared,
        # 1 documented) and only name matching sees the drift.
        $records['renamed'].DeclaredParameters.Count | Should -Be $records['renamed'].DocumentedParameters.Count
        $records['renamed'].MissingParameters | Should -Be @('NewName')
        $records['renamed'].OrphanedParameters | Should -Be @('OldName')

        $records['empty-parameter'].EmptyParameterSections | Should -Be @('Name')
        $records['empty-parameter'].MissingParameters |
            Should -BeNullOrEmpty -Because 'the entry exists, so it is an empty-body finding and not a coverage finding'

        $records['duplicate'].DuplicatedParameters | Should -Be @('Name')
        $records['nameless'].NamelessParameterSections | Should -Be 1
        $records['nameless'].MissingParameters |
            Should -Be @('Name') -Because 'a nameless entry documents nothing, so the parameter is still undocumented'

        # False-positive guards.
        $records['dotted-prose'].MissingParameters | Should -BeNullOrEmpty
        $records['dotted-prose'].OrphanedParameters | Should -BeNullOrEmpty
        $records['dotted-prose'].EmptyParameterSections | Should -BeNullOrEmpty
        $records['dotted-prose'].SynopsisEmpty | Should -BeFalse

        $records['case-mismatch'].MissingParameters |
            Should -BeNullOrEmpty -Because 'PowerShell parameter names are case-insensitive, so .PARAMETER name documents $Name'
        $records['case-mismatch'].OrphanedParameters | Should -BeNullOrEmpty

        # Placement. All three of these read as fully documented to a lookup that accepts the
        # nearest .SYNOPSIS above the function, and Get-Help attaches nothing to any of them.
        $records['help-above'].HasHelpBlock |
            Should -BeFalse -Because 'the convention throughout Public/ is a block inside the function body, and a lookup that also accepts an adjacent block above cannot distinguish it from a distant file header'
        $records['help-above'].MissingParameters | Should -Be @('Name')

        $records['distant-header'].HasHelpBlock |
            Should -BeFalse -Because 'a file-header block a dozen lines up documents the file, and Get-Help attaches none of it to the function'

        $records['nested-only'].HasHelpBlock |
            Should -BeFalse -Because 'the only help block belongs to a nested helper, so the cmdlet itself is undocumented'
        $records['nested-only'].MissingParameters |
            Should -Be @('Name') -Because "the nested helper's .PARAMETER entry must not be credited to the cmdlet"

        $records['second-synopsis'].SynopsisEmpty |
            Should -BeFalse -Because 'the first .SYNOPSIS is populated and wins; a later empty one must not flag the cmdlet'
    }
}
