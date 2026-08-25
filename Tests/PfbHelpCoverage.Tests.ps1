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

    # Which comment block `Get-Help` actually reads, for a function.
    #
    # MEASURED, not assumed. 34 probe shapes were written to disk, dot-sourced, and read back
    # through `Get-Help -Full` under BOTH Windows PowerShell 5.1 (5.1.26100.8875) and PowerShell
    # 7.6.5. Every shape gave the same answer on both editions, so there is one rule to encode
    # rather than one per edition.
    #
    # HONOURED positions:
    #   - immediately ABOVE the `function` keyword, separated by at most one blank line and by
    #     nothing else. Two blank lines breaks it; so does an intervening `#` line comment.
    #   - at the START of the body, BEFORE the param block. `[CmdletBinding()]` is part of the
    #     param block, so a block between the attribute and `param(` is NOT honoured, and neither
    #     is one immediately BELOW `param(` -- that one is the shape this lookup used to credit.
    #   - at the END of the body, after the last statement. Trailing blank lines are fine.
    # NOT honoured: anywhere in the middle of the body, and anywhere inside a `process { }` or
    # other sub-block. `Get-Help` renders its auto-generated syntax-only help instead.
    #
    # PRECEDENCE, when more than one block competes:
    #   - ABOVE beats every block inside the body, including one at the start of the body.
    #   - START of body beats END of body.
    #   - blocks on CONSECUTIVE lines form one run and are concatenated, so a later `.SYNOPSIS`
    #     overrides an earlier one: the LAST `.SYNOPSIS` in a run wins.
    #   - a blank line ends a run, and the FIRST run carrying any help keyword is the help. A run
    #     whose keywords do NOT include `.SYNOPSIS` still wins and suppresses every later block:
    #     `.DESCRIPTION` alone renders an EMPTY synopsis rather than falling through to a
    #     `.SYNOPSIS` further down. That is why the keyword pattern below is any `.KEYWORD` and
    #     not just `.SYNOPSIS` -- matching only `.SYNOPSIS` would credit a block `Get-Help` never
    #     reads.
    #
    # A `#` line comment inside a run cuts both ways, asymmetrically, and both directions were
    # measured: one BEFORE the block comment makes `Get-Help` render nothing, while one AFTER it
    # is honoured with the line's text appended to whatever section came last. Public/ contains
    # the second shape, so the two cannot be collapsed.
    #
    # Two known places where this is deliberately narrower than `Get-Help`, both erring toward a
    # red build rather than a false green:
    #   - line-comment-style help (`# .SYNOPSIS` on consecutive lines) is not recognised at all,
    #     above or inside. It is legal PowerShell and nothing in Public/ uses it.
    #   - a run whose only help keyword is one `Get-Help` does not recognise (`.FOO`) is treated as
    #     claiming the help, so nothing later is credited. `Get-Help` may well fall through to a
    #     later block; the cost of being wrong here is a red build on a shape nobody writes.
    function Get-PfbHelpToken {
        param(
            [System.Management.Automation.Language.FunctionDefinitionAst]$Function,
            [System.Management.Automation.Language.Token[]]$Tokens,
            [string]$KeywordPattern,
            [string]$SynopsisPattern
        )

        $commentKind = [System.Management.Automation.Language.TokenKind]::Comment
        $newLineKind = [System.Management.Automation.Language.TokenKind]::NewLine

        # ABOVE the function keyword. Reported, not credited -- see the record's
        # HelpAboveFunction field for why that is a finding rather than a pass.
        foreach ($token in $Tokens) {
            if ($token.Kind -ne $commentKind) { continue }
            if ($token.Text -notlike '<#*') { continue }
            if ($token.Text -notmatch $KeywordPattern) { continue }
            if ($token.Extent.EndOffset -gt $Function.Extent.StartOffset) { continue }

            $between = @($Tokens | Where-Object {
                    $_.Extent.StartOffset -ge $token.Extent.EndOffset -and
                    $_.Extent.EndOffset -le $Function.Extent.StartOffset
                })
            if (@($between | Where-Object { $_.Kind -ne $newLineKind }).Count -gt 0) { continue }
            # One newline is adjacency, two is a single blank line -- both honoured. Three is two
            # blank lines, which is not.
            if ($between.Count -gt 2) { continue }

            return [PSCustomObject]@{ Token = $null; AboveFunction = $true }
        }

        # Inside the body. Work from the TOKENS rather than the statement list: the param block,
        # its `[CmdletBinding()]` attribute and a named `begin`/`process`/`end` block are all
        # "code" for this purpose, and the token stream treats them uniformly. Body.Extent
        # includes the braces, so the strict comparisons drop them.
        $bodyStart = $Function.Body.Extent.StartOffset
        $bodyEnd = $Function.Body.Extent.EndOffset
        $inBody = @($Tokens | Where-Object {
                $_.Extent.StartOffset -gt $bodyStart -and $_.Extent.EndOffset -lt $bodyEnd
            })
        $code = @($inBody | Where-Object { $_.Kind -ne $commentKind -and $_.Kind -ne $newLineKind })

        # A body with no code at all: every comment in it is simultaneously at the start and the
        # end, and the leading region is searched first.
        $codeStart = $bodyEnd
        $codeEnd = $bodyStart
        if ($code.Count -gt 0) {
            $codeStart = $code[0].Extent.StartOffset
            $codeEnd = $code[$code.Count - 1].Extent.EndOffset
        }

        $comments = @($inBody | Where-Object { $_.Kind -eq $commentKind })
        $leading = @($comments | Where-Object { $_.Extent.EndOffset -le $codeStart })
        $trailing = @($comments | Where-Object { $_.Extent.StartOffset -ge $codeEnd })

        $found = Select-PfbHelpFromRegion -Comments $leading -Tokens $Tokens `
            -KeywordPattern $KeywordPattern -SynopsisPattern $SynopsisPattern
        if (-not $found.Stopped) {
            $found = Select-PfbHelpFromRegion -Comments $trailing -Tokens $Tokens `
                -KeywordPattern $KeywordPattern -SynopsisPattern $SynopsisPattern
        }

        return [PSCustomObject]@{ Token = $found.Token; AboveFunction = $false }
    }

    # Pick the block `Get-Help` would read out of ONE honoured region (start of body, or end of
    # body), per the precedence measured above.
    #
    # `Stopped` says the region held a help block, whether or not that block turned out to carry a
    # `.SYNOPSIS` this sweep can score. It is what keeps the end-of-body search from crediting a
    # block `Get-Help` never reaches, because a start-of-body block already claimed the help.
    function Select-PfbHelpFromRegion {
        param(
            [System.Management.Automation.Language.Token[]]$Comments,
            [System.Management.Automation.Language.Token[]]$Tokens,
            [string]$KeywordPattern,
            [string]$SynopsisPattern
        )

        $newLineKind = [System.Management.Automation.Language.TokenKind]::NewLine

        # Group into runs: consecutive lines are one run, a blank line starts a new one.
        $runs = [System.Collections.Generic.List[object]]::new()
        $current = $null
        $previous = $null
        foreach ($comment in $Comments) {
            $sameRun = $false
            if ($null -ne $previous) {
                $gap = @($Tokens | Where-Object {
                        $_.Extent.StartOffset -ge $previous.Extent.EndOffset -and
                        $_.Extent.EndOffset -le $comment.Extent.StartOffset
                    })
                $sameRun = (@($gap | Where-Object { $_.Kind -ne $newLineKind }).Count -eq 0) -and
                    (@($gap | Where-Object { $_.Kind -eq $newLineKind }).Count -le 1)
            }
            if (-not $sameRun) {
                $current = [System.Collections.Generic.List[object]]::new()
                $runs.Add($current)
            }
            $current.Add($comment)
            $previous = $comment
        }

        foreach ($run in $runs) {
            # A run of ordinary commentary is not help and does not suppress what follows it --
            # measured: a line comment, a blank line, then the real block, and Get-Help reads the
            # block. So the keyword test comes FIRST, before the composition test below.
            $keyworded = @($run | Where-Object { $_.Text -like '<#*' -and $_.Text -match $KeywordPattern })
            if ($keyworded.Count -eq 0) { continue }

            # A run carrying help keywords claims the help, so from here on every path stops.
            #
            # Position of a `#` line comment inside the run decides it, and the two directions are
            # not symmetric -- measured, on both editions. A line comment BEFORE the block makes
            # Get-Help render nothing at all. One AFTER the block is honoured, with the line's text
            # appended to whichever section came last. Public/Get-PfbOpenFile.ps1 is the second
            # shape (a drift-report note between the block and [CmdletBinding()]), so treating the
            # two alike would red-build a cmdlet whose help renders correctly.
            $firstKeyworded = $keyworded[0]
            $precedingLineComment = @($run | Where-Object {
                    $_.Text -notlike '<#*' -and
                    $_.Extent.StartOffset -lt $firstKeyworded.Extent.StartOffset
                })
            if ($precedingLineComment.Count -gt 0) {
                return [PSCustomObject]@{ Token = $null; Stopped = $true }
            }

            $synopsis = @($run | Where-Object { $_.Text -like '<#*' -and $_.Text -match $SynopsisPattern })
            if ($synopsis.Count -eq 0) {
                return [PSCustomObject]@{ Token = $null; Stopped = $true }
            }
            return [PSCustomObject]@{ Token = $synopsis[$synopsis.Count - 1]; Stopped = $true }
        }

        return [PSCustomObject]@{ Token = $null; Stopped = $false }
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
        # The block must sit at a position `Get-Help` HONOURS, and it must be inside the function
        # body. Get-PfbHelpToken above carries the measured placement and precedence rules; two
        # points about how this gate uses them:
        #
        # Being inside the function extent is not enough, which is what this lookup used to check.
        # A block below `param()`, or in the middle of a body after an early-return guard, is
        # inside the extent and outside any nested function, and `Get-Help` shows nothing for it --
        # so the old test reported "fully documented" for a cmdlet with no rendered help at all.
        # The 'help-below-param' and 'help-mid-body' fixtures pin that.
        #
        # A block immediately ABOVE the `function` keyword is honoured by `Get-Help` -- that much
        # the earlier comment here had backwards -- but it is still a finding, and the convention
        # is a block inside the body (all 544 in Public/ are). Two reasons to keep flagging it.
        # It renders IN PLACE OF a block inside the body, so a cmdlet with both shows the outer
        # one and the inner one is dead text no reader will ever see ('above-plus-inside' pins
        # that Get-Help prefers the outer). And crediting it would mean this sweep has to agree
        # with Get-Help about adjacency to the byte, where the failure direction is a file-header
        # block getting credited as a cmdlet's help ('distant-header'). Reported separately, via
        # HelpAboveFunction, so the failure message can name the actual remedy.
        # `\r` is in the trailing character class on purpose. In multiline mode `$` matches before
        # the `\n` but NOT before the `\r`, so a `[ \t]*$` tail silently matches nothing at all in
        # a CRLF file -- which every file in this repo is. The symptom is the whole population
        # reading as undocumented while the same pattern works on an LF fixture.
        $keywordPattern = '(?m)^[ \t]*\.[A-Za-z]+(?:[ \t]+\S+)?[ \t\r]*$'
        $synopsisPattern = '(?m)^[ \t]*\.SYNOPSIS[ \t\r]*$'

        $lookup = Get-PfbHelpToken -Function $Function -Tokens $Tokens `
            -KeywordPattern $keywordPattern -SynopsisPattern $synopsisPattern
        $help = $lookup.Token

        # Nested helpers, for DIAGNOSIS only. The position test above already rejects a nested
        # helper's block (it can be neither before the outer body's first code token nor after its
        # last), so this no longer gates the lookup -- it distinguishes "this cmdlet has no help"
        # from "this cmdlet's help is in the wrong place", which are different fixes.
        $nestedFunctions = @($Function.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
                }, $true) | Where-Object { -not [object]::ReferenceEquals($_, $Function) })

        $ownCandidates = @($Tokens | Where-Object {
                $_.Kind -eq [System.Management.Automation.Language.TokenKind]::Comment -and
                $_.Text -match $synopsisPattern -and
                $_.Extent.StartOffset -ge $Function.Extent.StartOffset -and
                $_.Extent.EndOffset -le $Function.Extent.EndOffset
            } | Where-Object {
                $candidate = $_
                -not @($nestedFunctions | Where-Object {
                        $candidate.Extent.StartOffset -ge $_.Extent.StartOffset -and
                        $candidate.Extent.EndOffset -le $_.Extent.EndOffset
                    }).Count
            })
        $misplaced = ($null -eq $help) -and (-not $lookup.AboveFunction) -and ($ownCandidates.Count -gt 0)

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
            HelpAboveFunction         = $lookup.AboveFunction
            HelpBlockMisplaced        = $misplaced
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
        #
        # PLACEMENT is part of this assertion, so the message has to name it: a cmdlet can hold a
        # perfectly good .SYNOPSIS and still fail here because it sits where `Get-Help` will not
        # read it. Each offender is annotated with which of the three it is, because the remedy
        # differs -- write the help, or move it.
        $missingBlock = @($script:cmdlets | Where-Object { -not $_.HasHelpBlock })
        $missingDetail = @($missingBlock | ForEach-Object {
                $reason = if ($_.HelpAboveFunction) {
                    'help block sits ABOVE the function keyword -- move it inside the body'
                }
                elseif ($_.HelpBlockMisplaced) {
                    'help block is at a position Get-Help does not honour (mid-body, or below param()) -- move it to the top of the body'
                }
                else {
                    'no help block at all'
                }
                "$($_.File): $($_.Function) -- $reason"
            }) -join "`n"
        $missingDetail | Should -BeNullOrEmpty -Because "every public cmdlet needs comment-based help that Get-Help will actually render: one block comment as the FIRST thing in the function body, above [CmdletBinding()] and param(). A .SYNOPSIS below param(), in the middle of the body, or above the function keyword does not satisfy this even though it is real help text -- move the existing block rather than writing a second one; offenders:`n$missingDetail"

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
            # The rest pin the help-block LOOKUP itself, which nothing else here exercises: every
            # fixture above puts the block at the top of the function body, so placement and
            # precedence had no coverage in either direction. ('second-synopsis' is the exception
            # -- it pins the first-.SYNOPSIS-wins rule inside a single block, not the lookup.)
            #
            # Each of these was measured against real `Get-Help` output on both editions before
            # being written down; the expectations below are the measurement, not a reading of the
            # docs. Where this sweep deliberately differs from `Get-Help` the -Because says so.
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
            'help-below-param' = @'
function Get-PfbFixture {
    [CmdletBinding()]
    param([Parameter()] [string]$Name)
    <#
    .SYNOPSIS
        Real help text, one line too low to be read.
    .PARAMETER Name
        The fixture name.
    #>

    Write-Output 'body'
}
'@
            'help-mid-body' = @'
function Get-PfbFixture {
    [CmdletBinding()]
    param([Parameter()] [string]$Name)

    if (-not $Name) { throw 'Name is required' }

    <#
    .SYNOPSIS
        Real help text, stranded in the middle of the body.
    .PARAMETER Name
        The fixture name.
    #>

    Write-Output 'body'
}
'@
            'help-body-end' = @'
function Get-PfbFixture {
    [CmdletBinding()]
    param([Parameter()] [string]$Name)

    Write-Output 'body'

    <#
    .SYNOPSIS
        Help at the end of the body, which Get-Help does read.
    .PARAMETER Name
        The fixture name.
    #>
}
'@
            'two-inside-start-and-end' = @'
function Get-PfbFixture {
    <#
    .SYNOPSIS
        The block at the start of the body.
    .PARAMETER Name
        The fixture name.
    #>
    [CmdletBinding()]
    param([Parameter()] [string]$Name)

    Write-Output 'body'

    <#
    .SYNOPSIS
        The block at the end of the body, which Get-Help ignores in favour of the first.
    .PARAMETER Other
        A parameter this cmdlet does not declare.
    #>
}
'@
            'two-blocks-one-run' = @'
function Get-PfbFixture {
    <#
    .SYNOPSIS
        First block of the run.
    .PARAMETER Other
        A parameter this cmdlet does not declare.
    #>
    <#
    .SYNOPSIS
        Second block of the run, whose .SYNOPSIS overrides the first.
    .PARAMETER Name
        The fixture name.
    #>
    [CmdletBinding()]
    param([Parameter()] [string]$Name)
}
'@
            'two-runs-blank-separated' = @'
function Get-PfbFixture {
    <#
    .SYNOPSIS
        First run, which Get-Help reads.
    .PARAMETER Name
        The fixture name.
    #>

    <#
    .SYNOPSIS
        Second run, which Get-Help never reaches.
    .PARAMETER Other
        A parameter this cmdlet does not declare.
    #>
    [CmdletBinding()]
    param([Parameter()] [string]$Name)
}
'@
            'linecomment-then-help' = @'
function Get-PfbFixture {
    # An ordinary line comment on the line directly above the help block.
    <#
    .SYNOPSIS
        Help in a run that also holds a line comment.
    .PARAMETER Name
        The fixture name.
    #>
    [CmdletBinding()]
    param([Parameter()] [string]$Name)
}
'@
            'help-then-linecomment' = @'
function Get-PfbFixture {
    <#
    .SYNOPSIS
        Help with a line comment directly BELOW it, as Public/Get-PfbOpenFile.ps1 has.
    .PARAMETER Name
        The fixture name.
    #>
    # A note to the reader, between the help block and [CmdletBinding()].
    [CmdletBinding()]
    param([Parameter()] [string]$Name)
}
'@
            'above-plus-inside' = @'
<#
.SYNOPSIS
    Adjacent help above the function, which Get-Help renders.
.PARAMETER Other
    A parameter this cmdlet does not declare.
#>
function Get-PfbFixture {
    <#
    .SYNOPSIS
        Help inside the body, which Get-Help never renders because of the block above.
    .PARAMETER Name
        The fixture name.
    #>
    [CmdletBinding()]
    param([Parameter()] [string]$Name)
}
'@
            'above-description-only' = @'
<#
.DESCRIPTION
    An adjacent block above the function carrying a help keyword but no .SYNOPSIS.
#>
function Get-PfbFixture {
    <#
    .SYNOPSIS
        Help inside the body, suppressed by the block above.
    .PARAMETER Name
        The fixture name.
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

        # Placement, part 1: blocks OUTSIDE the function body. The two cases are not the same and
        # the earlier version of this comment ran them together. Measured on both editions:
        # 'help-above' DOES render through Get-Help -- adjacent-above is a legal, honoured
        # placement -- while 'distant-header' renders nothing. This sweep declines to credit
        # either, deliberately and for the reasons in Get-PfbHelpRecord, so 'help-above' is the
        # one place where a red here is a convention finding rather than "Get-Help shows nothing".
        $records['help-above'].HasHelpBlock |
            Should -BeFalse -Because 'the convention throughout Public/ is a block inside the function body; an adjacent block above IS honoured by Get-Help, but it renders in place of any block inside the body, and crediting it would mean matching Get-Help on adjacency byte for byte with a distant file header as the failure mode'
        $records['help-above'].HelpAboveFunction |
            Should -BeTrue -Because 'the failure message must be able to say "move it inside" rather than "write some help"'
        $records['help-above'].MissingParameters | Should -Be @('Name')

        $records['distant-header'].HasHelpBlock |
            Should -BeFalse -Because 'a file-header block a dozen lines up documents the file, and Get-Help attaches none of it to the function'
        $records['distant-header'].HelpAboveFunction |
            Should -BeFalse -Because 'two blank lines or an intervening line comment breaks adjacency, so this is not the above-the-function shape at all'

        # An above-the-function block WINS over a block inside the body, so the inner one is text
        # no reader ever sees. Both fixtures pin that, and the second pins why the keyword pattern
        # is any .KEYWORD rather than .SYNOPSIS alone: measured, an adjacent block carrying only
        # .DESCRIPTION makes Get-Help render an EMPTY synopsis instead of falling through to the
        # .SYNOPSIS inside the body.
        $records['above-plus-inside'].HasHelpBlock |
            Should -BeFalse -Because 'Get-Help renders the block above the function, so the block inside the body is dead text'
        $records['above-plus-inside'].HelpAboveFunction | Should -BeTrue
        $records['above-plus-inside'].MissingParameters |
            Should -Be @('Name') -Because 'the inner block must not be credited for a parameter whose help never renders'

        $records['above-description-only'].HasHelpBlock |
            Should -BeFalse -Because 'a block with any help keyword claims the help even without a .SYNOPSIS, so the inner block is still suppressed'
        $records['above-description-only'].HelpAboveFunction | Should -BeTrue

        # Placement, part 2: positions INSIDE the body. These are the false greens the earlier
        # lookup produced -- both blocks are inside the function extent and outside any nested
        # function, which was the whole test, and Get-Help renders nothing for either.
        $records['help-below-param'].HasHelpBlock |
            Should -BeFalse -Because 'measured on both editions: a block below param() is not honoured, and Get-Help falls back to auto-generated syntax help'
        $records['help-below-param'].HelpBlockMisplaced |
            Should -BeTrue -Because 'the help text exists and needs moving, which is a different fix from writing help that does not exist'
        $records['help-below-param'].MissingParameters | Should -Be @('Name')

        $records['help-mid-body'].HasHelpBlock |
            Should -BeFalse -Because 'a block stranded mid-body after a guard is not honoured, so a lookup that only checks "inside the function" reports fully documented while Get-Help shows nothing'
        $records['help-mid-body'].HelpBlockMisplaced | Should -BeTrue
        $records['help-mid-body'].MissingParameters | Should -Be @('Name')

        $records['nested-only'].HelpBlockMisplaced |
            Should -BeFalse -Because 'a nested helper''s block is not the cmdlet''s own help placed badly, so the message must not tell the developer to move it'

        # End of body IS honoured -- measured -- so this must NOT be flagged. Without it the
        # position test could be "the block is the first thing in the body" and still pass
        # everything else here, which would red-build a legal placement.
        $records['help-body-end'].HasHelpBlock |
            Should -BeTrue -Because 'a block after the last statement is an honoured placement and Get-Help renders it'
        $records['help-body-end'].MissingParameters | Should -BeNullOrEmpty

        # Precedence among honoured blocks. Each fixture documents the DECLARED parameter from the
        # block Get-Help picks and a parameter that does not exist from the block it ignores, so
        # picking the wrong one shows up as a Missing/Orphaned pair rather than as a pass.
        $records['two-inside-start-and-end'].HasHelpBlock | Should -BeTrue
        $records['two-inside-start-and-end'].MissingParameters |
            Should -BeNullOrEmpty -Because 'start of body beats end of body, so the start block is the one scored'
        $records['two-inside-start-and-end'].OrphanedParameters |
            Should -BeNullOrEmpty -Because 'scoring the end block instead would orphan its .PARAMETER Other'

        $records['two-blocks-one-run'].HasHelpBlock | Should -BeTrue
        $records['two-blocks-one-run'].MissingParameters |
            Should -BeNullOrEmpty -Because 'blocks on consecutive lines are one run and a later .SYNOPSIS overrides an earlier one, so the SECOND is what Get-Help renders'
        $records['two-blocks-one-run'].OrphanedParameters | Should -BeNullOrEmpty

        $records['two-runs-blank-separated'].HasHelpBlock | Should -BeTrue
        $records['two-runs-blank-separated'].MissingParameters |
            Should -BeNullOrEmpty -Because 'a blank line ends the run, and the FIRST run carrying help keywords is the one Get-Help reads'
        $records['two-runs-blank-separated'].OrphanedParameters | Should -BeNullOrEmpty

        # A `#` line comment in the same run as the help block, in both orders. These are NOT
        # symmetric and the pair is what stops the rule being written as "reject any mixed run":
        # Public/Get-PfbOpenFile.ps1 is the second shape, so rejecting both would red-build a
        # cmdlet whose help renders perfectly well.
        $records['linecomment-then-help'].HasHelpBlock |
            Should -BeFalse -Because 'measured: a line comment ABOVE the block makes Get-Help render nothing for the function'
        $records['help-then-linecomment'].HasHelpBlock |
            Should -BeTrue -Because 'measured: a line comment BELOW the block is honoured, its text appended to the last section'
        $records['help-then-linecomment'].MissingParameters | Should -BeNullOrEmpty

        $records['nested-only'].HasHelpBlock |
            Should -BeFalse -Because 'the only help block belongs to a nested helper, so the cmdlet itself is undocumented'
        $records['nested-only'].MissingParameters |
            Should -Be @('Name') -Because "the nested helper's .PARAMETER entry must not be credited to the cmdlet"

        $records['second-synopsis'].SynopsisEmpty |
            Should -BeFalse -Because 'the first .SYNOPSIS is populated and wins; a later empty one must not flag the cmdlet'
    }
}
