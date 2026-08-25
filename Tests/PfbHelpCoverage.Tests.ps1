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
#
# That applies to the TEST, not to the rule the test encodes. Where Get-Help reads help from was
# measured by calling real Get-Help on real files -- see the placement note on Get-PfbRenderedHelp
# -- because every prose account of it written during this work, this file's own comments included,
# turned out to be wrong in some detail.

BeforeAll {
    $script:moduleRoot = Split-Path -Parent $PSScriptRoot
    $script:publicRoot = Join-Path $script:moduleRoot 'Public'

    # The comment-based-help directives Get-Help RECOGNISES, split by arity.
    #
    # Measured two independent ways, agreeing exactly. Behaviourally: each candidate was written as
    # the opening directive of a comment run, followed by a blank line and a real help block, and
    # read back through `Get-Help -Full` on both editions -- a directive Get-Help recognises claims
    # the help and the later block never renders, one it does not is ordinary commentary and the
    # later block renders normally. Then structurally: both editions' comment parser carries exactly
    # these fifteen names, and the same directive pattern used in Test-PfbHelpRun below, so the list
    # is complete for the two editions this repo runs on rather than merely unfalsified.
    #
    # ARITY is load-bearing, not decoration, and it cuts both ways. `.SYNOPSIS Some text` is NOT a
    # directive line -- the argument-less ones must stand alone -- so a block opening with it is
    # prose as far as Get-Help is concerned and renders nothing. A bare `.PARAMETER` is not a
    # directive line either, for the mirror reason.
    $script:helpDirectiveBare = @(
        'SYNOPSIS', 'DESCRIPTION', 'NOTES', 'LINK', 'ROLE',
        'EXAMPLE', 'OUTPUTS', 'INPUTS', 'COMPONENT', 'FUNCTIONALITY'
    )
    $script:helpDirectiveArgument = @(
        'PARAMETER', 'FORWARDHELPTARGETNAME', 'FORWARDHELPCATEGORY',
        'REMOTEHELPRUNSPACE', 'EXTERNALHELP'
    )

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

        # $Text is a RUN's help source, so every `<#`/`#>` delimiter and every line comment's
        # leading `#` has already been removed by Get-PfbCommentText. Nothing here has to strip
        # them, and nothing here may assume one comment token per help block: a run of adjacent
        # blocks is one help block to Get-Help, and its sections have to be read as one stream.
        $sections = [System.Collections.Generic.List[object]]::new()
        $current = $null
        foreach ($line in ($Text -split "\r?\n")) {
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

    # One comment token as help SOURCE text.
    function Get-PfbCommentText {
        param(
            [System.Management.Automation.Language.Token]$Comment
        )

        $text = $Comment.Text
        if ($text -like '<#*') {
            # Delimiters removed IN PLACE rather than by dropping the lines that carry them:
            # measured, `<# .SYNOPSIS` and `... PARAM-TEXT #>` both keep the content that shares a
            # delimiter's line, so dropping those lines would silently lose a section.
            $text = $text.Substring(2)
            if ($text.EndsWith('#>')) { $text = $text.Substring(0, $text.Length - 2) }
            return $text
        }

        # A `#` line comment contributes its text with the single leading `#` removed, and that
        # text is help source like any other. Measured both consequences: `# .PARAMETER Name` in a
        # run really does document Name, and `#region helpers` on the line above a help block
        # destroys the block by putting non-directive text first.
        return $text.Substring(1)
    }

    # Group a region's comment tokens into RUNS: consecutive lines are one run, a blank line starts
    # a new one. Verified on both editions that the tokeniser emits one NewLine token per line
    # break and never collapses them, so "at most one NewLine between two comments" is exactly "no
    # blank line between them".
    function Get-PfbCommentRun {
        param(
            [System.Management.Automation.Language.Token[]]$Comments,
            [System.Management.Automation.Language.Token[]]$Tokens
        )

        $newLineKind = [System.Management.Automation.Language.TokenKind]::NewLine

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

        # Comma on purpose. Returning the list bare lets the pipeline enumerate it, and a region
        # holding exactly one run would then come back as that run's tokens instead of as a list of
        # one run -- which reads as "several runs of one comment each" and quietly disables the
        # composition test this whole function exists to feed.
        return , $runs
    }

    # Concatenate one run into the help source Get-Help would see.
    function Get-PfbRunText {
        param(
            [object]$Run
        )

        return ((@($Run) | ForEach-Object { Get-PfbCommentText -Comment $_ }) -join "`n")
    }

    # Why a run is not comment-based help -- and the predicate built on it.
    #
    # A run stands or falls WHOLE. Get-Help walks its lines in order and abandons all of them the
    # moment one is wrong, so a block whose `.SYNOPSIS` and every `.PARAMETER` are perfect renders
    # NOTHING if a single line elsewhere in it is a directive Get-Help cannot accept. Two ways a
    # line can be wrong, both measured on both editions:
    #   - a line that is not a directive at all, sitting ABOVE the first directive. BELOW one it is
    #     simply that section's body, which is why a `#` note under the block is harmless and the
    #     same note above it is fatal.
    #   - a directive-SHAPED line -- a dot followed by word characters -- that is not a recognised
    #     directive, ANYWHERE in the run. `.WIBBLE`, `.SOME_THING`, a bare `.PARAMETER`,
    #     `.DESCRIPTION with text on the same line`, and (because the pattern is `\w`, not
    #     `[A-Za-z]`) a prose line such as `.5 is a fraction` each void the entire block.
    # A line that starts with a dot but is not word-shaped, such as
    # `.\tools\Update-PfbContextHelp.ps1 -WhatIf` in an .EXAMPLE body, is ordinary body text and
    # harmless. Measured, not assumed -- the two look alike and behave oppositely.
    #
    # This is what closes the shapes the position-only version of this lookup failed open on. An
    # ordinary `<#…#>` block, or an unknown-keyword one, on the line directly above a help block
    # takes the help block down with it; a stray `.WIBBLE` below one does the same. A blank line
    # before an offending BLOCK makes them two runs again and the help renders -- but a bad line
    # INSIDE the block cannot be rescued that way.
    #
    # Returns $null when the run IS help, an EMPTY string when it is plain commentary carrying no
    # directive at all (a comment, not a defect), and otherwise a reason naming the offending line.
    # That third case is the one a developer cannot see by reading the block, so the failure message
    # quotes it rather than saying "no help block".
    function Get-PfbHelpRunDefect {
        param(
            [string]$Text
        )

        $hasDirective = $Text -match '(?m)^\s*\.\w+'
        $seenDirective = $false

        foreach ($line in ($Text -split "\r?\n")) {
            if ($line -match '^\s*$') { continue }

            # Get-Help's own directive pattern, verbatim -- both editions' comment parser carries
            # this exact expression, argument group and all.
            if ($line -notmatch '^\s*\.(\w+)(\s+(\S.*))?\s*$') {
                if ($seenDirective) { continue }
                if ($hasDirective) {
                    return "a line that is not a help directive sits above the first one: '$($line.Trim())'"
                }
                return ''
            }

            $keyword = $Matches[1].ToUpperInvariant()
            $argument = $Matches[3]

            if ($script:helpDirectiveBare -contains $keyword) {
                if ([string]::IsNullOrWhiteSpace($argument)) { $seenDirective = $true; continue }
                return ".$keyword takes no argument, so '$($line.Trim())' is not a directive line"
            }
            if ($script:helpDirectiveArgument -contains $keyword) {
                if (-not [string]::IsNullOrWhiteSpace($argument)) { $seenDirective = $true; continue }
                return ".$keyword needs an argument, so '$($line.Trim())' is not a directive line"
            }
            return ".$keyword is not a directive Get-Help recognises, and one bad directive voids the whole block"
        }

        if ($seenDirective) { return $null }
        return ''
    }

    function Test-PfbHelpRun {
        param(
            [string]$Text
        )

        return ($null -eq (Get-PfbHelpRunDefect -Text $Text))
    }

    # The first run in ONE region that is help, as source text; $null when the region holds none.
    #
    # A run that is help claims it absolutely -- whether or not it carries a `.SYNOPSIS` this sweep
    # can score -- which is what stops the end-of-body search crediting a block Get-Help never
    # reaches. A run that is NOT help claims nothing and blocks nothing.
    function Select-PfbHelpFromRegion {
        param(
            [System.Management.Automation.Language.Token[]]$Comments,
            [System.Management.Automation.Language.Token[]]$Tokens
        )

        $defect = $null
        foreach ($run in (Get-PfbCommentRun -Comments $Comments -Tokens $Tokens)) {
            $text = Get-PfbRunText -Run $run
            $why = Get-PfbHelpRunDefect -Text $text
            if ($null -eq $why) { return [PSCustomObject]@{ Text = $text; Defect = $null } }
            # First malformed help block in the region wins the diagnosis. Plain commentary
            # reports an empty string and is not a defect.
            if ($why -and -not $defect) { $defect = $why }
        }

        return [PSCustomObject]@{ Text = $null; Defect = $defect }
    }

    # Which comment run `Get-Help` actually renders, for a function.
    #
    # MEASURED, not assumed, and not taken from any prose account -- this file's own comments
    # included, two of which were wrong. 125 probe shapes were written to disk, dot-sourced and read
    # back through `Get-Help -Full` under BOTH Windows PowerShell 5.1 (5.1.26100.8875) and
    # PowerShell 7.6.5, and then all 41 fixtures below were put through the same treatment and
    # compared against this detector. Every shape gave the same placement answer on both editions,
    # so there is one rule to encode rather than one per edition.
    #
    # The unit is the RUN, defined by Get-PfbCommentRun above, not the block. Modelling position
    # alone is precisely what made the previous version fail open: it asked where a `<#…#>` block
    # sat and never asked what shared its run.
    #
    # REGIONS, searched in this order and moving on whenever a region holds no help run:
    #   1. ABOVE the `function` keyword -- the LAST run before it, and only when nothing but at
    #      most one blank line separates the two. Two blank lines breaks it, and so does another
    #      comment run in between, which is why a file header with unrelated commentary beneath it
    #      attaches to nothing. An intervening `#` line comment does NOT break it: the comment
    #      simply joins the run, and its text is appended to the last section.
    #   2. START of the body -- the runs before the first code token. `[CmdletBinding()]` is code,
    #      so a run between the attribute and `param(` is already past this region, as is one below
    #      `param()`. There is no proximity rule inside the body; blank lines either side are fine.
    #   3. END of the body -- the runs after the last code token.
    # Nothing else is honoured. Mid-body, or inside a `process { }` or other sub-block, renders the
    # auto-generated syntax help.
    #
    # PRECEDENCE follows from the region order: above beats the body, and start of body beats end of
    # body. A run that is help but carries no `.SYNOPSIS` still claims it -- `.DESCRIPTION` alone
    # renders an EMPTY synopsis rather than falling through to a `.SYNOPSIS` further down.
    #
    # One deliberate narrowing, erring toward a red build rather than a false green: an ABOVE run
    # that Get-Help does render is reported rather than credited. See Get-PfbHelpRecord for why.
    function Get-PfbRenderedHelp {
        param(
            [System.Management.Automation.Language.FunctionDefinitionAst]$Function,
            [System.Management.Automation.Language.Token[]]$Tokens
        )

        $commentKind = [System.Management.Automation.Language.TokenKind]::Comment
        $newLineKind = [System.Management.Automation.Language.TokenKind]::NewLine

        # Region 1 -- ABOVE the function keyword.
        $above = @($Tokens | Where-Object {
                $_.Kind -eq $commentKind -and
                $_.Extent.EndOffset -le $Function.Extent.StartOffset
            })
        $aboveRuns = Get-PfbCommentRun -Comments $above -Tokens $Tokens
        if ($aboveRuns.Count -gt 0) {
            $lastRun = $aboveRuns[$aboveRuns.Count - 1]
            $lastComment = $lastRun[$lastRun.Count - 1]
            $between = @($Tokens | Where-Object {
                    $_.Extent.StartOffset -ge $lastComment.Extent.EndOffset -and
                    $_.Extent.EndOffset -le $Function.Extent.StartOffset
                })
            # One newline is adjacency, two is a single blank line -- both honoured. Three is two
            # blank lines, which is not.
            $adjacent = (@($between | Where-Object { $_.Kind -ne $newLineKind }).Count -eq 0) -and
                ($between.Count -le 2)

            if ($adjacent -and (Test-PfbHelpRun -Text (Get-PfbRunText -Run $lastRun))) {
                return [PSCustomObject]@{ Text = $null; AboveFunction = $true; Defect = $null }
            }
            # Not adjacent, or adjacent but not help: measured, Get-Help then reads the body
            # exactly as though nothing sat above the function at all. Falling through rather than
            # stopping here is what keeps a `#region` marker or a file header from being read as a
            # cmdlet having no help.
        }

        # Regions 2 and 3 -- inside the body. Work from the TOKENS rather than the statement list:
        # the param block, its `[CmdletBinding()]` attribute and a named `begin`/`process`/`end`
        # block are all "code" for this purpose, and the token stream treats them uniformly.
        # Body.Extent includes the braces, so the strict comparisons drop them.
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

        $found = Select-PfbHelpFromRegion -Comments $leading -Tokens $Tokens
        if ($null -eq $found.Text) {
            $end = Select-PfbHelpFromRegion -Comments $trailing -Tokens $Tokens
            if ($null -ne $end.Text -or $null -eq $found.Defect) { $found = $end }
        }

        return [PSCustomObject]@{ Text = $found.Text; AboveFunction = $false; Defect = $found.Defect }
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

        # Locate the help from the TOKEN stream, not by regexing the file: a comment token is the
        # only thing that is definitely a comment, and the AST has no node for one.
        #
        # Get-PfbRenderedHelp above carries the measured placement, composition and precedence
        # rules, and returns the help SOURCE -- the whole claiming run concatenated -- rather than
        # one token. That matters here: a run of adjacent blocks is a single help block to
        # Get-Help, so every `.PARAMETER` in it counts no matter which block carried it. Scoring
        # one token instead hid the other blocks' entries from the orphan and duplicate
        # assertions ('two-blocks-one-run' pins it). Three points about how this gate uses the rest:
        #
        # Being inside the function extent is not enough, which is what this lookup used to check.
        # A block below `param()`, or in the middle of a body after an early-return guard, is
        # inside the extent and outside any nested function, and `Get-Help` shows nothing for it --
        # so the old test reported "fully documented" for a cmdlet with no rendered help at all.
        # The 'help-below-param' and 'help-mid-body' fixtures pin that.
        #
        # Neither is POSITION enough on its own, which is what the version before this one checked.
        # A block on the line directly below ordinary commentary is at an honoured position and
        # renders nothing, because the run it belongs to does not open with a directive
        # ('ordinary-then-help-one-run', 'unknown-keyword-then-help-one-run', 'prose-before-keyword').
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
        $lookup = Get-PfbRenderedHelp -Function $Function -Tokens $Tokens
        $helpText = $lookup.Text

        # Used for DIAGNOSIS only, below. Case-insensitive because Get-Help's directives are, and
        # `\r` is in the trailing character class on purpose: in multiline mode `$` matches before
        # the `\n` but NOT before the `\r`, so a `[ \t]*$` tail silently matches nothing at all in
        # a CRLF file -- which every file in this repo is. The symptom is the whole population
        # reading as undocumented while the same pattern works on an LF fixture.
        $synopsisPattern = '(?im)^[ \t]*\.SYNOPSIS[ \t\r]*$'

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
        $synopsisEmpty = $false
        $seenSynopsis = $false
        $documented = @()
        $emptyParameterSections = @()

        if ($null -ne $helpText) {
            $sections = @(Get-PfbHelpSection -Text $helpText)

            # The LAST .SYNOPSIS wins, and this is the reverse of what this file used to assert.
            # Measured on both editions, within one block and across blocks of one run alike: a
            # later .SYNOPSIS overrides an earlier one even when it is EMPTY, and Get-Help then
            # renders a blank synopsis rather than the earlier text. Taking the first was the false
            # green -- it reported a populated synopsis for a cmdlet whose rendered synopsis is
            # blank, which is exactly what this assertion exists to catch.
            $synopsisSections = @($sections | Where-Object { $_.Keyword -eq 'SYNOPSIS' })
            if ($synopsisSections.Count -gt 0) {
                $seenSynopsis = $true
                $lastSynopsis = $synopsisSections[$synopsisSections.Count - 1]
                $synopsisEmpty = [string]::IsNullOrWhiteSpace((($lastSynopsis.BodyLines -join "`n").Trim()))
            }

            foreach ($section in $sections) {
                if ($section.Keyword -ne 'PARAMETER') { continue }

                $sectionBody = ($section.BodyLines -join "`n").Trim()

                # A NAMELESS `.PARAMETER` cannot reach here and is deliberately not counted. It
                # used to have a field and an assertion of its own, on the belief that Get-Help
                # renders the rest of the block and silently drops the entry. Measured on both
                # editions, it does not: a bare `.PARAMETER` is a malformed directive and voids
                # the whole block, so the cmdlet has no rendered help at all. That is caught
                # earlier and harder, by HasHelpBlock, and named exactly by HelpRunDefect -- so
                # the counter could never have been non-zero once the run test was correct, and a
                # field that can only ever read 0 is an assertion that cannot fail.
                if ([string]::IsNullOrEmpty($section.Argument)) { continue }

                $documented += $section.Argument
                if ([string]::IsNullOrWhiteSpace($sectionBody)) {
                    $emptyParameterSections += $section.Argument
                }
            }
        }

        $misplaced = (-not $seenSynopsis) -and (-not $lookup.AboveFunction) -and ($ownCandidates.Count -gt 0)

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
            HasHelpBlock              = $seenSynopsis
            HelpAboveFunction         = $lookup.AboveFunction
            HelpBlockMisplaced        = $misplaced
            HelpRunDefect             = $lookup.Defect
            SynopsisEmpty             = $synopsisEmpty
            DeclaredParameters        = $declared
            DocumentedParameters      = $documented
            MissingParameters         = $missing
            OrphanedParameters        = $orphaned
            DuplicatedParameters      = $duplicated
            EmptyParameterSections    = $emptyParameterSections
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
        # perfectly good .SYNOPSIS and still fail here because Get-Help will not read it there.
        # Each offender is annotated with which of the three it is, because the remedy differs --
        # write the help, or move it.
        #
        # The above-the-function wording is deliberate and was wrong until 2026-08-25. It used to
        # tell the developer that Get-Help does not render help above the function. It DOES --
        # measured on both editions. The finding is a convention one: an outer block renders IN
        # PLACE OF a block inside the body, so a cmdlet carrying both has inner help no reader ever
        # sees, and crediting the outer block would force this sweep to agree with Get-Help about
        # adjacency to the byte, whose failure direction is a file header scored as a cmdlet's help.
        # A message that misstates the reason sends the reader looking for a rendering bug that is
        # not there.
        $missingBlock = @($script:cmdlets | Where-Object { -not $_.HasHelpBlock })
        $missingDetail = @($missingBlock | ForEach-Object {
                $reason = if ($_.HelpAboveFunction) {
                    'help block sits ABOVE the function keyword. Get-Help DOES render it there, so this is a convention finding, not a broken-help one -- but it renders INSTEAD OF any block inside the body, and the convention throughout Public/ is a block inside the body; move it inside'
                }
                elseif ($_.HelpRunDefect) {
                    # The one case a developer cannot diagnose by reading the block, because the
                    # block looks correct: one bad line voids all of it. Quote the line.
                    "the help block is malformed and Get-Help renders NONE of it -- $($_.HelpRunDefect)"
                }
                elseif ($_.HelpBlockMisplaced) {
                    'the cmdlet has a .SYNOPSIS that Get-Help does not render -- either it sits where Get-Help never looks (below param(), mid-body, or inside a process block), or it shares a comment run with a line that is not a help directive, which voids the whole run; move it to the top of the body and leave a blank line between it and any comment above it'
                }
                else {
                    'no help block at all'
                }
                "$($_.File): $($_.Function) -- $reason"
            }) -join "`n"
        $missingDetail | Should -BeNullOrEmpty -Because "every public cmdlet needs comment-based help that Get-Help will actually render: one block comment as the FIRST thing in the function body, above [CmdletBinding()] and param(), and not sharing a comment run with ordinary commentary. Real help text is not enough on its own -- a .SYNOPSIS below param(), in the middle of the body, or on the line directly below an unrelated comment renders nothing at all. Move the existing block rather than writing a second one; offenders:`n$missingDetail"

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

        # There WAS a third assertion here, for a `.PARAMETER` with no name. It is gone, and this
        # note is the record of why rather than a silent deletion. It rested on the belief that
        # Get-Help renders the rest of such a block and quietly drops the nameless entry, which
        # would make it invisible to both assertions above. Measured on both editions, that is not
        # what happens: a bare `.PARAMETER` is a malformed directive, and one malformed directive
        # voids the entire block, so the cmdlet renders no help at all. The first assertion in this
        # file therefore catches it, earlier and harder, and names the offending line via
        # HelpRunDefect. The counter it read could no longer be non-zero, and an assertion over a
        # field that is structurally always 0 is one that cannot fail -- which is the failure mode
        # the anti-vacuous floor at the top of this file exists to prevent.
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
            # RUN COMPOSITION. The last group, and the one the position-only version of this lookup
            # had no model for at all: which comment run a block belongs to decides whether it is
            # help, independently of where the run sits. Each of these was measured against real
            # `Get-Help -Full` output on both editions, and each is paired with the same shape one
            # blank line apart -- the pair is the point, because the two differ by a single
            # character of whitespace and Get-Help answers them oppositely.
            'above-linecomment-then-inside' = @'
<#
.SYNOPSIS
    Adjacent help above the function, with a note between it and the keyword.
.PARAMETER Other
    A parameter this cmdlet does not declare.
#>
# A note between the help block and the function keyword.
function Get-PfbFixture {
    <#
    .SYNOPSIS
        Help inside the body, which Get-Help never renders because of the run above.
    .PARAMETER Name
        The fixture name.
    #>
    [CmdletBinding()]
    param([Parameter()] [string]$Name)
}
'@
            'ordinary-then-help-one-run' = @'
function Get-PfbFixture {
    <#
        An ordinary comment block on the line directly above the help block.
    #>
    <#
    .SYNOPSIS
        Help in a run that does not open with a directive, so Get-Help reads none of it.
    .PARAMETER Name
        The fixture name.
    #>
    [CmdletBinding()]
    param([Parameter()] [string]$Name)
}
'@
            'ordinary-blank-then-help' = @'
function Get-PfbFixture {
    <#
        An ordinary comment block, one blank line above the help block.
    #>

    <#
    .SYNOPSIS
        Help in a run of its own, which Get-Help renders normally.
    .PARAMETER Name
        The fixture name.
    #>
    [CmdletBinding()]
    param([Parameter()] [string]$Name)
}
'@
            'unknown-keyword-then-help-one-run' = @'
function Get-PfbFixture {
    <#
    .WIBBLE
        A keyword Get-Help does not recognise, on the line above the help block.
    #>
    <#
    .SYNOPSIS
        Help in the same run, which Get-Help therefore never reads.
    .PARAMETER Name
        The fixture name.
    #>
    [CmdletBinding()]
    param([Parameter()] [string]$Name)
}
'@
            'unknown-keyword-blank-then-help' = @'
function Get-PfbFixture {
    <#
    .WIBBLE
        A keyword Get-Help does not recognise, one blank line above the help block.
    #>

    <#
    .SYNOPSIS
        Help in a run of its own, which Get-Help renders.
    .PARAMETER Name
        The fixture name.
    #>
    [CmdletBinding()]
    param([Parameter()] [string]$Name)
}
'@
            'prose-before-keyword' = @'
function Get-PfbFixture {
    <#
        Prose above the first directive, inside the block rather than above it.
    .SYNOPSIS
        Help Get-Help refuses to read, for the same reason as the two shapes above.
    .PARAMETER Name
        The fixture name.
    #>
    [CmdletBinding()]
    param([Parameter()] [string]$Name)
}
'@
            'synopsis-with-inline-argument' = @'
function Get-PfbFixture {
    <#
    .SYNOPSIS Help text on the directive line, which makes it not a directive line.
    .PARAMETER Other
        A parameter this cmdlet does not declare.
    #>

    <#
    .SYNOPSIS
        The block Get-Help actually renders.
    .PARAMETER Name
        The fixture name.
    #>
    [CmdletBinding()]
    param([Parameter()] [string]$Name)
}
'@
            'linecomment-help-claims-run' = @'
function Get-PfbFixture {
    # .SYNOPSIS
    #     Line-comment-style help, which Get-Help does render.
    # .PARAMETER Other
    #     A parameter this cmdlet does not declare.

    <#
    .SYNOPSIS
        A block Get-Help never reaches, because the run above already claimed the help.
    .PARAMETER Name
        The fixture name.
    #>
    [CmdletBinding()]
    param([Parameter()] [string]$Name)
}
'@
            'linecomment-continues-run' = @'
function Get-PfbFixture {
    <#
    .SYNOPSIS
        Help whose run continues into the line comments below it.
    #>
    # .PARAMETER Name
    #     The fixture name, documented by a line comment in the same run.
    [CmdletBinding()]
    param([Parameter()] [string]$Name)
}
'@
            'invalid-above-falls-through' = @'
<#
    An ordinary block sharing a run with the help block above the function.
#>
<#
.SYNOPSIS
    Help that looks adjacent but whose run does not open with a directive.
.PARAMETER Other
    A parameter this cmdlet does not declare.
#>
function Get-PfbFixture {
    <#
    .SYNOPSIS
        The block Get-Help renders, because nothing above the function is help.
    .PARAMETER Name
        The fixture name.
    #>
    [CmdletBinding()]
    param([Parameter()] [string]$Name)
}
'@
            # Content sharing a line with a delimiter, at both ends. Measured: Get-Help keeps it,
            # so the delimiters have to be stripped IN PLACE. Dropping the `<#` line instead loses
            # the .SYNOPSIS and voids the block; dropping the `#>` line silently empties the last
            # section. Neither is visible to any other fixture here, because every other fixture
            # puts its delimiters on lines of their own.
            'delimiter-line-content' = @'
function Get-PfbFixture {
    <# .SYNOPSIS
        A synopsis whose directive shares the opening delimiter's line.
    .PARAMETER Name
        The fixture name, ending on the closing delimiter's line. #>
    [CmdletBinding()]
    param([Parameter()] [string]$Name)
}
'@
            # A malformed directive LATER in an otherwise-perfect block. The run test has to walk
            # every line, not just the first: these two blocks open correctly, document their
            # parameter correctly, and render nothing at all.
            'unknown-keyword-later-in-block' = @'
function Get-PfbFixture {
    <#
    .SYNOPSIS
        A synopsis Get-Help never renders, because of the line four below it.
    .PARAMETER Name
        The fixture name.
    .WIBBLE
        A keyword Get-Help does not recognise, after otherwise-correct help.
    #>
    [CmdletBinding()]
    param([Parameter()] [string]$Name)
}
'@
            'dotword-prose-voids-block' = @'
function Get-PfbFixture {
    <#
    .SYNOPSIS
        A synopsis Get-Help never renders, because of the .EXAMPLE body below.
    .PARAMETER Name
        The fixture name.
    .EXAMPLE
        .NET Core is mentioned at the start of this line
    #>
    [CmdletBinding()]
    param([Parameter()] [string]$Name)
}
'@
            # The one shape that separates `\w` from `[A-Za-z]`, and the reason it needs its own
            # fixture: `.NET` above is pure ASCII, so it matches both patterns identically and
            # pins only the ARGUMENT group. A digit- or underscore-led dot line is directive-shaped
            # to `\w` alone. Measured on both editions -- Get-Help renders auto-generated syntax
            # help and no parameter text for this fixture, so narrowing the pattern would credit a
            # cmdlet whose help does not render at all.
            'digit-dotword-voids-block' = @'
function Get-PfbFixture {
    <#
    .SYNOPSIS
        A synopsis Get-Help never renders, because of the .EXAMPLE body below.
    .PARAMETER Name
        The fixture name.
    .EXAMPLE
        .5 is a fraction and not a path, so this line is a malformed directive
    #>
    [CmdletBinding()]
    param([Parameter()] [string]$Name)
}
'@
            # The adjacency BOUNDARY above the function, both sides of it. 'distant-header' never
            # reaches this: its last run before the keyword is the line comment, so the block above
            # it never gets an adjacency test at all, and the bound went unpinned until a mutation
            # of it survived.
            'above-blank-line-still-adjacent' = @'
<#
.SYNOPSIS
    A block one blank line above the function, which Get-Help still attaches to it.
.PARAMETER Name
    The fixture name.
#>

function Get-PfbFixture {
    [CmdletBinding()]
    param([Parameter()] [string]$Name)
}
'@
            'distant-block-falls-through' = @'
<#
.SYNOPSIS
    A block two blank lines above the function, which Get-Help does not attach to it.
.PARAMETER Other
    A parameter this cmdlet does not declare.
#>


function Get-PfbFixture {
    <#
    .SYNOPSIS
        The block Get-Help renders, because two blank lines break adjacency above.
    .PARAMETER Name
        The fixture name.
    #>
    [CmdletBinding()]
    param([Parameter()] [string]$Name)
}
'@
            # Which of SEVERAL runs above the function is the one that counts. Every other
            # above-function fixture has exactly one run up there, so taking the first instead of
            # the last is indistinguishable in all of them -- and in 'distant-header' the first
            # falls through anyway, on adjacency. Here the file header is first and the real help
            # is last, and the two verdicts differ: measured on both editions, Get-Help renders the
            # LAST run, so reading the first would leave the block above unexamined and credit a
            # body block Get-Help never reads.
            'last-run-above-function-wins' = @'
<#
.SYNOPSIS
    File header for a script, not help for the function below it.
#>

<#
.SYNOPSIS
    The block directly above the function, which Get-Help renders.
.PARAMETER Name
    The fixture name.
#>
function Get-PfbFixture {
    <#
    .SYNOPSIS
        A body block Get-Help never reads, because the block above it wins.
    .PARAMETER Name
        The fixture name.
    #>
    [CmdletBinding()]
    param([Parameter()] [string]$Name)
}
'@
            'ordinary-start-help-at-end' = @'
function Get-PfbFixture {
    <#
        An ordinary block at the start of the body, which is not help.
    #>
    [CmdletBinding()]
    param([Parameter()] [string]$Name)

    Write-Output 'body'

    <#
    .SYNOPSIS
        Help at the end of the body, which Get-Help falls through to.
    .PARAMETER Name
        The fixture name.
    #>
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
        $records['clean'].HelpRunDefect | Should -BeNullOrEmpty

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

        # A bare `.PARAMETER` does NOT merely fail to document its parameter. Measured on both
        # editions: it is a malformed directive, and one malformed directive voids the whole block,
        # so Get-Help renders auto-generated syntax help and the .SYNOPSIS above it never appears
        # either. This fixture asserted a nameless-section COUNT until 2026-08-25, on the opposite
        # belief -- crediting the block was a false green over a cmdlet with no rendered help.
        $records['nameless'].HasHelpBlock |
            Should -BeFalse -Because 'measured: a bare .PARAMETER voids the entire block, .SYNOPSIS included'
        $records['nameless'].MissingParameters |
            Should -Be @('Name') -Because 'nothing in a voided block is credited'
        $records['nameless'].HelpRunDefect |
            Should -BeLike '*PARAMETER needs an argument*' -Because 'the failure message has to name the line that voided the block, or the developer is left reading a block that looks perfectly correct'

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
        $records['two-blocks-one-run'].OrphanedParameters |
            Should -Be @('Other') -Because 'a run is ONE help block to Get-Help: the first block''s .PARAMETER Other renders too, so it is a genuine orphan. This expectation was empty until 2026-08-25, when the run was measured rather than described -- scoring only the block that carried the winning .SYNOPSIS hid every other block''s entries from this assertion'

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

        # The LAST .SYNOPSIS wins, not the first. This assertion read -BeFalse until 2026-08-25 on
        # the strength of a source comment; measured on both editions, within one block and across
        # blocks of one run alike, a later .SYNOPSIS overrides an earlier one EVEN WHEN EMPTY and
        # Get-Help renders a blank synopsis. Believing the first won was a false green: it reported
        # a populated synopsis for a cmdlet whose rendered synopsis is empty, which is verbatim the
        # defect the empty-synopsis assertion exists to catch.
        $records['second-synopsis'].SynopsisEmpty |
            Should -BeTrue -Because 'measured: a trailing empty .SYNOPSIS overrides the populated one above it and Get-Help renders a blank synopsis'
        $records['second-synopsis'].HasHelpBlock |
            Should -BeTrue -Because 'the run is help and does carry a .SYNOPSIS; the finding is that it renders empty, which is the other assertion'

        # RUN COMPOSITION. Three shapes the position-only lookup scored as documented while
        # Get-Help rendered auto-generated syntax help, each paired with the same shape one blank
        # line apart to keep the rule from collapsing into "reject any mixed run".

        # HIGH 1. Measured: an intervening `#` line comment does NOT break adjacency above the
        # function -- the comment joins the run and its text is appended to the last section, and
        # the outer block renders IN PLACE OF the inner one. The old lookup rejected any non-newline
        # token between block and keyword, so it ignored the outer block and credited the inner one:
        # rendered help and scored help came from different blocks.
        $records['above-linecomment-then-inside'].HelpAboveFunction |
            Should -BeTrue -Because 'measured on both editions: a line comment between the block and the function keyword is honoured, so this is the above-the-function shape'
        $records['above-linecomment-then-inside'].HasHelpBlock |
            Should -BeFalse -Because 'Get-Help renders the run above the function, so the block inside the body is dead text'
        $records['above-linecomment-then-inside'].MissingParameters |
            Should -Be @('Name') -Because 'the inner block must not be credited for a parameter whose help never renders'

        # HIGH 2. An ordinary block on the line above the help block puts non-directive text first
        # in the run, and Get-Help reads none of it.
        $records['ordinary-then-help-one-run'].HasHelpBlock |
            Should -BeFalse -Because 'measured: a run whose first non-blank line is not a directive is ordinary commentary, help block and all, and Get-Help falls back to auto-generated syntax help'
        $records['ordinary-then-help-one-run'].MissingParameters |
            Should -Be @('Name') -Because 'nothing in a voided run is credited, including its .PARAMETER entries'
        $records['ordinary-blank-then-help'].HasHelpBlock |
            Should -BeTrue -Because 'measured: one blank line makes them two runs, the second opens with a directive, and Get-Help renders it -- the pair is what stops the rule becoming "reject any mixed run"'
        $records['ordinary-blank-then-help'].MissingParameters | Should -BeNullOrEmpty

        # HIGH 3. Same shape with an unrecognised keyword. Both directions matter: same-run voids
        # the help block, blank-separated does NOT suppress it. The blank-separated expectation is
        # the reverse of what this file used to encode -- it treated any `.KEYWORD` run as claiming
        # the help, which red-built a shape Get-Help renders perfectly well.
        $records['unknown-keyword-then-help-one-run'].HasHelpBlock |
            Should -BeFalse -Because 'measured: .WIBBLE is not a directive Get-Help recognises, so it is prose, and prose first in a run voids the whole run'
        $records['unknown-keyword-then-help-one-run'].MissingParameters | Should -Be @('Name')
        $records['unknown-keyword-blank-then-help'].HasHelpBlock |
            Should -BeTrue -Because 'measured: an unrecognised keyword claims nothing, so a blank-separated help block below it renders normally'
        $records['unknown-keyword-blank-then-help'].MissingParameters | Should -BeNullOrEmpty

        # The same defect inside a SINGLE block, which is why the test is "first non-blank line of
        # the run" and not "the run's first comment is a block comment".
        $records['prose-before-keyword'].HasHelpBlock |
            Should -BeFalse -Because 'measured: prose above the first directive voids the block, exactly as an ordinary block on the line above would'
        $records['prose-before-keyword'].MissingParameters | Should -Be @('Name')

        # ARITY. `.SYNOPSIS` takes no argument, so `.SYNOPSIS <text>` is not a directive line at all
        # and the block opening with it is prose -- which means the block BELOW it is the help.
        # Getting arity wrong in this direction is a false green: it would treat the first run as
        # claiming and score nothing.
        $records['synopsis-with-inline-argument'].HasHelpBlock |
            Should -BeTrue -Because 'measured: an argument-less directive carrying an argument is not a directive line, so that run is prose and Get-Help falls through to the next one'
        $records['synopsis-with-inline-argument'].MissingParameters | Should -BeNullOrEmpty
        $records['synopsis-with-inline-argument'].OrphanedParameters |
            Should -BeNullOrEmpty -Because 'the voided run''s .PARAMETER Other never renders, so crediting it would invent an orphan'

        # LINE-COMMENT help is real help, both as the thing that renders and as the thing that
        # suppresses. The old lookup only ever looked at `<#…#>` tokens, so it skipped this run
        # entirely and credited the block below -- a block Get-Help never reaches.
        $records['linecomment-help-claims-run'].HasHelpBlock |
            Should -BeTrue -Because 'measured: `# .SYNOPSIS` on consecutive lines is comment-based help and Get-Help renders it'
        $records['linecomment-help-claims-run'].MissingParameters |
            Should -Be @('Name') -Because 'the line-comment run claims the help, so the block below it never renders and Name really is undocumented'
        $records['linecomment-help-claims-run'].OrphanedParameters |
            Should -Be @('Other') -Because 'the .PARAMETER entry that DOES render names a parameter this cmdlet does not declare'
        $records['linecomment-continues-run'].MissingParameters |
            Should -BeNullOrEmpty -Because 'measured: a line comment in the same run contributes help source, so `# .PARAMETER Name` documents Name'

        # FALL-THROUGH. A region that holds no help run suppresses nothing -- Get-Help carries on
        # to the next region. Both directions of that were measured: above to body, and start of
        # body to end of body.
        $records['invalid-above-falls-through'].HelpAboveFunction |
            Should -BeFalse -Because 'the run above the function is not help, so there is nothing above the function to report'
        $records['invalid-above-falls-through'].HasHelpBlock |
            Should -BeTrue -Because 'measured: Get-Help reads the body exactly as though nothing sat above the function'
        $records['invalid-above-falls-through'].MissingParameters | Should -BeNullOrEmpty
        $records['invalid-above-falls-through'].OrphanedParameters | Should -BeNullOrEmpty

        $records['ordinary-start-help-at-end'].HasHelpBlock |
            Should -BeTrue -Because 'measured: an ordinary run at the start of the body does not claim the help, so the end-of-body block is what renders'
        $records['ordinary-start-help-at-end'].MissingParameters | Should -BeNullOrEmpty

        # Delimiters are stripped IN PLACE, not by dropping the lines that carry them. Measured on
        # both editions: content on the `<#` line and on the `#>` line both survive into the help.
        $records['delimiter-line-content'].HasHelpBlock |
            Should -BeTrue -Because 'the .SYNOPSIS shares the opening delimiter''s line and Get-Help still reads it, so dropping that line would void a block that renders'
        $records['delimiter-line-content'].MissingParameters | Should -BeNullOrEmpty
        $records['delimiter-line-content'].EmptyParameterSections |
            Should -BeNullOrEmpty -Because 'the last .PARAMETER body ends on the closing delimiter''s line, so dropping that line would silently empty a section that has text'

        # A malformed directive LATER in the block, which voids all of it. This is the reason the
        # run test walks every line rather than just the first: both of these open with a correct
        # .SYNOPSIS and a correct .PARAMETER, and Get-Help renders auto-generated syntax help for
        # both. 'dotword-prose-voids-block' is the sharp one -- `.NET Core ...` is prose to a
        # reader and a malformed directive to Get-Help.
        # (`.\tools\...` in the 'dotted-prose' fixture is the harmless twin: a backslash is not a
        # word character, so that line is body text and its block renders. The pair is the point.)
        #
        # What separates `.NET` from prose is the DOT plus word characters, which `\w` and
        # `[A-Za-z]` agree on -- `NET` is pure ASCII, so this pair does not pin the character class
        # and reading it as though it did is how the class went unpinned. What it does pin is the
        # argument group: narrowing `(\S.*)` to `(\S+)` is killed here and nowhere else.
        # 'digit-dotword-voids-block' is the fixture that pins `\w` itself.
        $records['unknown-keyword-later-in-block'].HasHelpBlock |
            Should -BeFalse -Because 'measured: one unrecognised directive anywhere in the run voids the whole block, .SYNOPSIS included'
        $records['unknown-keyword-later-in-block'].MissingParameters | Should -Be @('Name')
        $records['unknown-keyword-later-in-block'].HelpRunDefect |
            Should -BeLike '*WIBBLE is not a directive*'

        $records['dotword-prose-voids-block'].HasHelpBlock |
            Should -BeFalse -Because 'measured: `.NET Core ...` matches Get-Help''s directive pattern, so it is a malformed directive and not example prose'
        $records['dotword-prose-voids-block'].MissingParameters | Should -Be @('Name')
        $records['dotted-prose'].HasHelpBlock |
            Should -BeTrue -Because 'the twin case: `.\tools\...` is NOT directive-shaped, because a backslash is not a word character, so that block renders'

        $records['digit-dotword-voids-block'].HasHelpBlock |
            Should -BeFalse -Because 'measured on both editions: `.5 is a fraction ...` is directive-shaped to `\w` and Get-Help renders no help for this cmdlet, so narrowing the class to `[A-Za-z]` would credit a block that does not render'
        $records['digit-dotword-voids-block'].MissingParameters | Should -Be @('Name')
        $records['digit-dotword-voids-block'].HelpRunDefect |
            Should -BeLike '*5 is not a directive*'

        # The adjacency BOUNDARY above the function. One blank line is still adjacency and two is
        # not, and both sides need a fixture: 'distant-header' looks like it covers this and does
        # not, because its last run before the keyword is the line comment rather than the block.
        # Widening the bound survived mutation testing until these two landed.
        $records['above-blank-line-still-adjacent'].HelpAboveFunction |
            Should -BeTrue -Because 'measured: one blank line between the block and the function keyword is still adjacency'
        $records['above-blank-line-still-adjacent'].HasHelpBlock | Should -BeFalse
        $records['above-blank-line-still-adjacent'].MissingParameters | Should -Be @('Name')

        $records['distant-block-falls-through'].HelpAboveFunction |
            Should -BeFalse -Because 'measured: two blank lines break adjacency, so the block above documents the file rather than the function -- the failure direction that keeps a file header from being scored as a cmdlet''s help'
        $records['distant-block-falls-through'].HasHelpBlock |
            Should -BeTrue -Because 'nothing above the function is help, so Get-Help reads the body'
        $records['distant-block-falls-through'].MissingParameters | Should -BeNullOrEmpty
        $records['distant-block-falls-through'].OrphanedParameters | Should -BeNullOrEmpty

        # WHICH run above the function is examined, when there is more than one. Both fixtures
        # above hold a single run up there, so they cannot tell the last from the first; this one
        # puts a file header first and the real help last. Measured on both editions: Get-Help
        # renders the LAST run's synopsis and its parameter text, so examining the first would
        # find a non-adjacent header, fall through, and credit the body block instead.
        $records['last-run-above-function-wins'].HelpAboveFunction |
            Should -BeTrue -Because 'measured: the run nearest the function keyword is the one Get-Help renders, header or not'
        $records['last-run-above-function-wins'].HasHelpBlock |
            Should -BeFalse -Because 'the help that renders sits above the function, so the body block is not what a reader sees and must not be scored as though it were'
        $records['last-run-above-function-wins'].MissingParameters | Should -Be @('Name')
    }
}
