<#
.SYNOPSIS
    Finds issue references that a closing keyword does NOT close, in a PR body or a commit message.
.DESCRIPTION
    GitHub closes an issue on merge only when a closing keyword immediately precedes THAT
    issue's own reference. In a list, only the first reference closes:

        Fixes #100, #101, #103     closes #100 only
        Fixes #100, fixes #101     closes both

    A pull request here once opened with `Fixes #100, #101, #103, #87, and #80`, and on merge
    closed #100 and nothing else. The mistake is silent, and it cannot be fixed afterwards:
    GitHub reads closing keywords AT MERGE TIME, so editing a merged PR's body closes nothing.
    That is why a finding is meant to stop a submission rather than warn about it: the PR
    looks right, the merge succeeds, and the issues simply stay open until someone notices
    the backlog. A warning that can be scrolled past is the wrong shape for a mistake whose
    whole problem is that nobody notices it.

    This script is the single implementation of the rule. .github/workflows/verify-closing-keywords.yml
    runs it on every pull request's body and commits, and local pre-submit tooling may call
    it too. It returns the corrected form for each finding.

    KEYWORDS: close, closes, closed, fix, fixes, fixed, resolve, resolves, resolved -- any
    case, optionally followed by a colon (Fixes: #1). REFERENCES: #N, owner/repo#N, and
    https://github.com/owner/repo/issues/N (or /pull/N).

    OUT OF SCOPE, each for a reason:
      * Titles, issue bodies and comments. A keyword there closes nothing, so the mistake
        cannot happen there. Only a PR body and the commits that land on the default branch
        are checked.
      * Code spans, ``` and ~~~ fences, and HTML comments (<!-- -->). GitHub neither links
        nor closes from them, so they are blanked before matching. This is the escape hatch:
        to quote the wrong form on purpose, put it in backticks. The PR template keeps its
        example inside an HTML comment for the same reason.
      * A chain continues only across list punctuation -- , ; / & + "and" "plus" and
        whitespace. `Fixes #100. Related: #101` is not a finding.
      * A conventional-commit subject such as `fix(admin): ... (#99, #100)` has no reference
        right after the keyword, so there is no closing anchor.
      * A keyword and its reference must share a line; `...is fixed` at the end of one line
        does not adopt `#1, #2` on the next.
.PARAMETER Text
    The text to check. Pipeline input is joined with newlines into ONE text, so
    `Get-Content body.md | ./tools/Test-PfbClosingKeywords.ps1` checks the file as a whole.
.OUTPUTS
    One object per finding: Line (1-based line of the keyword), Keyword (as written),
    Fragment (what was written, whitespace collapsed), Corrected (what to write instead),
    Missed (the references that would stay open). No output means no finding.
.EXAMPLE
    ./tools/Test-PfbClosingKeywords.ps1 -Text 'Fixes #1, #2'
#>
[CmdletBinding()]
param(
    [Parameter(ValueFromPipeline = $true)][AllowNull()][AllowEmptyString()][string]$Text
)

begin {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
    $parts = New-Object System.Collections.Generic.List[string]

    # JavaScript's regex classes, spelled out. .NET's \b, \d and \s are Unicode-aware and its
    # $ also matches before a final newline; any of those would make this disagree with the
    # local hook that falls back to the JavaScript original.
    #
    # Case is spelled out too, and no regex here uses IgnoreCase. JavaScript's /i (without /u)
    # folds these letters only within ASCII. .NET IgnoreCase does not, and not even the same
    # way on both editions: on pwsh 7 it counts the Kelvin sign (U+212A) as a K, so
    # [^A-Za-z0-9_] stops matching it and a keyword right after one is missed, while Windows
    # PowerShell 5.1 agrees with JavaScript. Explicit [Xx] classes give all three one answer.
    $word = '[A-Za-z0-9_]'
    $jsBoundary = "(?:(?<=$word)(?!$word)|(?<!$word)(?=$word))"
    $jsSpace = '[\t\n\v\f\r \u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000\ufeff]'
    # close[sd]? | fix(?:e[sd])? | resolve[sd]?, in any ASCII case.
    $keyword = '(?:[Cc][Ll][Oo][Ss][Ee][SsDd]?|[Ff][Ii][Xx](?:[Ee][SsDd])?|[Rr][Ee][Ss][Oo][Ll][Vv][Ee][SsDd]?)'
    $listWord = '(?:[Aa][Nn][Dd]|&|[Pp][Ll][Uu][Ss])'
    $cs = [System.Text.RegularExpressions.RegexOptions]'CultureInvariant'

    $script:ReKeywordTail = New-Object System.Text.RegularExpressions.Regex ("(?:^|[^A-Za-z0-9_])($keyword)[ \t]*:?[ \t]*\z", $cs)
    # The concatenation needs its OWN parentheses: in an argument list the comma binds tighter
    # than +, so without them New-Object receives ONE stringified array and ReRef never matches.
    $script:ReRef = New-Object System.Text.RegularExpressions.Regex (
        (('https?://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/(?:issues|pull)/([0-9]+)' + $jsBoundary) +
        ('|(?:' + $jsBoundary + '[A-Za-z0-9._-]+/[A-Za-z0-9._-]+)?#([0-9]+)' + $jsBoundary)), $cs)
    # ${listWord} is braced because PowerShell would read $listWord? as a variable named 'listWord?'.
    $script:ReSeparatorOnly = New-Object System.Text.RegularExpressions.Regex ("\A(?:$jsSpace|[,;/&+])*${listWord}?(?:$jsSpace|[,;/&+])*\z", $cs)
    $script:ReSpaceRun = New-Object System.Text.RegularExpressions.Regex ("$jsSpace+", $cs)
    $script:Blank = [System.Text.RegularExpressions.MatchEvaluator] { param($m) [regex]::Replace($m.Value, '[^\n]', ' ') }

    function ConvertTo-PfbInertBlankText {
        # Blank what GitHub does not parse for references. Fences first, or the inline-span
        # pass would chew through a fence's contents. Blanking (not deleting) keeps offsets.
        param([string]$Source)
        $t = [regex]::Replace($Source, '```[\s\S]*?```', $script:Blank)
        $t = [regex]::Replace($t, '~~~[\s\S]*?~~~', $script:Blank)
        $t = [regex]::Replace($t, '<!--[\s\S]*?-->', $script:Blank)
        return [regex]::Replace($t, '`+[^\n`]*`+', $script:Blank)
    }

    function Get-PfbClosingChain {
        param([string]$Source)
        $t = ConvertTo-PfbInertBlankText $Source
        $refs = @(foreach ($m in $script:ReRef.Matches($t)) { [pscustomobject]@{ Start = $m.Index; End = $m.Index + $m.Length; Text = $m.Value } })
        $chains = New-Object System.Collections.Generic.List[object]
        $cur = $null
        for ($i = 0; $i -lt $refs.Count; $i++) {
            $windowStart = [Math]::Max(0, $refs[$i].Start - 24)
            $kw = $script:ReKeywordTail.Match($t.Substring($windowStart, $refs[$i].Start - $windowStart))
            if ($kw.Success) {
                $kwText = $kw.Groups[1].Value
                $offset = 1
                if ($kw.Value.StartsWith($kwText, [System.StringComparison]::Ordinal)) { $offset = 0 }
                $cur = [pscustomobject]@{ Keyword = $kwText; KwStart = $windowStart + $kw.Index + $offset; Anchor = $refs[$i]; Bare = (New-Object System.Collections.Generic.List[object]) }
                $chains.Add($cur)
                continue
            }
            if ($null -ne $cur -and $i -gt 0 -and $script:ReSeparatorOnly.IsMatch($t.Substring($refs[$i - 1].End, $refs[$i].Start - $refs[$i - 1].End))) {
                $cur.Bare.Add($refs[$i])
                continue
            }
            $cur = $null
        }
        foreach ($c in $chains) {
            if ($c.Bare.Count -eq 0) { continue }
            $last = $c.Bare[$c.Bare.Count - 1]
            $fragment = $script:ReSpaceRun.Replace($t.Substring($c.KwStart, $last.End - $c.KwStart), ' ').Trim()
            $lower = $c.Keyword.ToLowerInvariant()
            $corrected = @("$($c.Keyword) $($c.Anchor.Text)") + @($c.Bare | ForEach-Object { "$lower $($_.Text)" })
            [pscustomobject]@{
                Line      = [regex]::Matches($t.Substring(0, $c.KwStart), "`n").Count + 1
                Keyword   = $c.Keyword
                Fragment  = $fragment
                Corrected = $corrected -join ', '
                Missed    = @($c.Bare | ForEach-Object { $_.Text })
            }
        }
    }
}

process {
    if ($null -ne $Text) { $parts.Add($Text) }
}

end {
    if ($parts.Count -eq 0) { return }
    Get-PfbClosingChain ($parts -join "`n")
}
