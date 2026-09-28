#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    tools/Test-PfbClosingKeywords.ps1: every reference a closing keyword does NOT close is found,
    and nothing GitHub would not close from is flagged.
.DESCRIPTION
    UNGATED on edition: the script is 5.1-safe and runs on both legs. Listed in
    RequiredDescribes for both editions.
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:check = Join-Path (Join-Path $script:repoRoot 'tools') 'Test-PfbClosingKeywords.ps1'
    # The unary comma is load-bearing: without it a single finding is unrolled on return,
    # and on Windows PowerShell 5.1 a lone pscustomobject has no .Count (it reads $null).
    function Get-TestFinding { param([AllowNull()][string]$Text) return , @(& $script:check -Text $Text) }
}

Describe 'Test-PfbClosingKeywords: the PR #108 incident' {
    It 'flags the incident text and hands back the corrected form' {
        $f = Get-TestFinding 'Fixes #100, #101, #103, #87, and #80.'
        $f.Count | Should -Be 1
        $f[0].Line | Should -Be 1
        $f[0].Keyword | Should -BeExactly 'Fixes'
        $f[0].Fragment | Should -BeExactly 'Fixes #100, #101, #103, #87, and #80'
        $f[0].Corrected | Should -BeExactly 'Fixes #100, fixes #101, fixes #103, fixes #87, fixes #80'
        @($f[0].Missed) -join ',' | Should -BeExactly '#101,#103,#87,#80'
    }
    It 'passes the corrected form' {
        (Get-TestFinding 'Fixes #100, fixes #101, fixes #103, fixes #87, fixes #80.').Count | Should -Be 0
    }
    It 'reports the right line in a CRLF body (GitHub stores web-edited bodies with CRLF)' {
        $f = Get-TestFinding "## Summary`r`n`r`nFixes #100, #101, #103, #87, and #80.`r`n"
        $f.Count | Should -Be 1
        $f[0].Line | Should -Be 3
    }
}

Describe 'Test-PfbClosingKeywords: what is flagged' {
    It 'flags <Text>' -ForEach @(
        @{ Text = 'Fixes #100, #101'; Corrected = 'Fixes #100, fixes #101' }
        @{ Text = 'fixes #87, #88'; Corrected = 'fixes #87, fixes #88' }
        @{ Text = 'Closes #1 and dmann000/fb-powershell#2'; Corrected = 'Closes #1, closes dmann000/fb-powershell#2' }
        @{ Text = 'Resolves #5, #6'; Corrected = 'Resolves #5, resolves #6' }
        @{ Text = 'Fixes: #1, #2'; Corrected = 'Fixes #1, fixes #2' }
        @{ Text = 'Fixes https://github.com/dmann000/fb-powershell/issues/1, #2'; Corrected = 'Fixes https://github.com/dmann000/fb-powershell/issues/1, fixes #2' }
        @{ Text = 'Fixes #1; #2 / #3 & #4 + #5 plus #6'; Corrected = 'Fixes #1, fixes #2, fixes #3, fixes #4, fixes #5, fixes #6' }
        @{ Text = "Fixes #1,$([char]0x00A0)#2"; Corrected = 'Fixes #1, fixes #2' }
    ) {
        $f = Get-TestFinding $Text
        $f.Count | Should -Be 1
        $f[0].Corrected | Should -BeExactly $Corrected
    }
    It 'knows all nine keywords in any case: <Kw>' -ForEach @(
        'close', 'closes', 'closed', 'fix', 'fixes', 'fixed', 'resolve', 'resolves', 'resolved',
        'CLOSES', 'Fixed', 'ReSoLvEd' | ForEach-Object { @{ Kw = $_ } }
    ) {
        (Get-TestFinding "$Kw #1, #2").Count | Should -Be 1
    }
    It 'reports two chains in one text, each on its own line' {
        $f = Get-TestFinding "Fixes #1, #2`nand later`nCloses #3, #4"
        @($f | ForEach-Object Line) -join ',' | Should -BeExactly '1,3'
    }
    It 'joins pipeline input into ONE text, so a fence split across lines is still a fence' {
        @('```', 'Fixes #1, #2', '```' | & $script:check).Count | Should -Be 0
        @('intro', 'Fixes #1, #2' | & $script:check)[0].Line | Should -Be 2
    }
}

Describe 'Test-PfbClosingKeywords: what is not flagged' {
    It 'passes <Why>' -ForEach @(
        @{ Why = 'a single reference'; Text = 'Fixes #63' }
        @{ Why = 'prose between references'; Text = 'Fixes #100. Related: #101, #102' }
        @{ Why = 'a conventional-commit subject'; Text = 'fix(admin): stop the dead query keys (#99, #100)' }
        @{ Why = 'a code span'; Text = 'The old body read `Fixes #100, #101` and closed only #100.' }
        @{ Why = 'a ``` fence'; Text = "Fixes #63.`n`n``````n Fixes #1, #2`n``````n" }
        @{ Why = 'a ~~~ fence'; Text = "~~~`nFixes #1, #2`n~~~" }
        @{ Why = 'an HTML comment (the PR template''s own example)'; Text = "<!--`nFixes #1, #2`n-->" }
        @{ Why = 'a keyword AFTER the list'; Text = 'See #1, #2 -- this fixes them' }
        @{ Why = 'a keyword at the end of one line and references on the next'; Text = "this is fixed`n#1, #2" }
        @{ Why = 'a keyword that is only the tail of a longer word'; Text = 'hotfixes #1, #2' }
        @{ Why = 'an empty text'; Text = '' }
    ) {
        (Get-TestFinding $Text).Count | Should -Be 0
    }
    It 'accepts $null without throwing' {
        { Get-TestFinding $null } | Should -Not -Throw
        (Get-TestFinding $null).Count | Should -Be 0
    }
    It 'handles a 65,536-character body quickly (no catastrophic backtracking)' {
        $body = ('x ' * 32760) + 'Fixes #1, #2'
        $body.Length | Should -BeGreaterOrEqual 65000
        $elapsed = Measure-Command { $script:big = Get-TestFinding $body }
        $script:big.Count | Should -Be 1
        $elapsed.TotalSeconds | Should -BeLessThan 5
    }
}

Describe 'Test-PfbClosingKeywords: letters are ASCII, as in the JavaScript original' {
    # The local hook is JavaScript, whose /i flag (without /u) folds only within ASCII for these
    # letters. .NET IgnoreCase does not: on pwsh 7 it treats the Kelvin sign (U+212A) as a K, so
    # [^A-Za-z0-9_] stops matching it and the keyword after it is missed -- while Windows
    # PowerShell 5.1 agrees with JavaScript. The script spells case out in explicit classes so
    # both editions and the hook give one answer.
    It 'still sees a keyword right after a Kelvin sign' {
        (Get-TestFinding "$([char]0x212A)fixes #1, #2").Count | Should -Be 1
    }
    It 'does not read a long s (U+017F) as an s' {
        (Get-TestFinding "clo$([char]0x017F)es #1, #2").Count | Should -Be 0
        (Get-TestFinding "Fixes #1 plu$([char]0x017F) #2").Count | Should -Be 0
    }
}

Describe 'verify-closing-keywords.yml' {
    BeforeAll {
        $script:ck = [System.IO.File]::ReadAllText((Join-Path $script:repoRoot '.github/workflows/verify-closing-keywords.yml'))
        $script:ckRun = @([regex]::Matches($script:ck, '(?m)^([ \t]+)(?:- )?run: \|[ \t]*\r?\n((?:(?:\1[ \t]+\S[^\r\n]*|[ \t]*)(?:\r?\n|$))+)') | ForEach-Object { $_.Groups[2].Value })
    }
    It 'runs on opened, edited, synchronize and reopened, on ubuntu (a body can exceed the Windows env-var cap)' {
        $script:ck | Should -Match '(?m)^    types: \[opened, edited, synchronize, reopened\]\s*$'
        $script:ck | Should -Match '(?m)^    runs-on: ubuntu-latest\s*$'
    }
    It 'reads contents only, with no secret' {
        $permissions = [regex]::Match($script:ck, '(?ms)^permissions:[ \t]*\r?\n(.*?)(?=^\S)').Groups[1].Value
        @([regex]::Matches($permissions, '(?m)^  ([a-z-]+: \S+)') | ForEach-Object { $_.Groups[1].Value }) -join ',' | Should -BeExactly 'contents: read'
        $script:ck | Should -Not -Match 'secrets\.'
    }
    It 'passes the body as an env VALUE and interpolates nothing into a run block' {
        $script:ck | Should -Match ([regex]::Escape('PR_BODY: ${{ github.event.pull_request.body }}'))
        $script:ck | Should -Match ([regex]::Escape('-Text $env:PR_BODY'))
        $script:ckRun.Count | Should -BeGreaterThan 0
        @($script:ckRun | Where-Object { $_.Contains('${{') }).Count | Should -Be 0
    }
    It 'reads commits from a full-depth checkout, without merges, excluding what is already on the base branch' {
        $script:ck | Should -Match '(?m)^\s+fetch-depth: 0\s*$'
        $script:ck | Should -Match ([regex]::Escape('git merge-base $env:BASE_SHA $env:HEAD_SHA'))
        $script:ck | Should -Match 'git rev-list --no-merges \$env:HEAD_SHA --not'
        $script:ck | Should -Match ([regex]::Escape('"origin/$($env:BASE_REF)"'))
    }
    It 'annotates each finding with the bare ::error:: form and fails the job' {
        $script:ck | Should -Match '::error::'
        $script:ck | Should -Not -Match '::error file='
        $script:ck | Should -Match '(?m)^\s+if \(\$failures -gt 0\) \{ exit 1 \}'
    }
}
