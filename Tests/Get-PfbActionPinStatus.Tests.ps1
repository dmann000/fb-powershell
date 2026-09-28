#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    tools/Get-PfbActionPinStatus.ps1 with the GitHub API mocked.
.DESCRIPTION
    EDITION-GATED: the script is `#Requires -Version 7.0` (it uses tools/lib/PfbGitHubRead.ps1),
    so every Describe carries -Skip:($PSVersionTable.PSVersion.Major -lt 7) and the 5.1 skip
    count is pinned in Tests/coverage-baseline.psd1.
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:scriptPath = Join-Path (Join-Path $script:repoRoot 'tools') 'Get-PfbActionPinStatus.ps1'
    $script:utf8 = New-Object System.Text.UTF8Encoding $false
    $script:shaA = '1111111111111111111111111111111111111111'
    $script:shaB = '2222222222222222222222222222222222222222'

    function New-TestRepo {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Test helper writing a fixture repo under $TestDrive; nothing to confirm.')]
        param()
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $wf = Join-Path (Join-Path $root '.github') 'workflows'
        $null = New-Item -ItemType Directory -Path $wf -Force
        $yml = @(
            'jobs:'
            '  a:'
            '    steps:'
            "      - uses: actions/checkout@$($script:shaA) # v7.0.1"
            "      - uses: actions/cache/restore@$($script:shaB) # v6.0.0"
            "      - uses: actions/cache/save@$($script:shaB) # v6.0.0"
            '      - uses: ./.github/actions/local'
        ) -join "`n"
        [System.IO.File]::WriteAllText((Join-Path $wf 'a.yml'), $yml + "`n", $script:utf8)
        return $root
    }
}

Describe 'Get-PfbActionPinStatus' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
    BeforeEach {
        Mock Invoke-RestMethod {
            if ($Uri -like '*/repos/actions/checkout/releases/latest') { return [pscustomobject]@{ tag_name = 'v7.0.1' } }
            if ($Uri -like '*/repos/actions/cache/releases/latest') { return [pscustomobject]@{ tag_name = 'v6.1.0' } }
            throw "unexpected $Uri"
        }
    }

    It 'reports one row per repository and pinned version, and says which are behind' {
        $rows = @(& $script:scriptPath -RepoRoot (New-TestRepo) -Token 'x' 6>$null)
        @($rows | ForEach-Object { '{0}|{1}|{2}|{3}' -f $_.Action, $_.Pinned, $_.Latest, $_.Behind }) -join ';' |
            Should -BeExactly 'actions/cache|v6.0.0|v6.1.0|yes;actions/checkout|v7.0.1|v7.0.1|no'
    }
    It 'asks the API once per repository, not once per reference' {
        $null = & $script:scriptPath -RepoRoot (New-TestRepo) -Token 'x' 6>$null
        Should -Invoke Invoke-RestMethod -Times 2 -Exactly
    }
    It 'ignores local references' {
        $rows = @(& $script:scriptPath -RepoRoot (New-TestRepo) -Token 'x' 6>$null)
        @($rows | Where-Object { $_.Action -like './*' }).Count | Should -Be 0
    }
    It 'appends a Markdown table to -SummaryPath' {
        $summary = Join-Path $TestDrive 'summary.md'
        $null = & $script:scriptPath -RepoRoot (New-TestRepo) -Token 'x' -SummaryPath $summary 6>$null
        $text = [System.IO.File]::ReadAllText($summary)
        $text | Should -Match '(?m)^\| Action \| Pinned \| Latest \| Behind \|\s*$'
        $text | Should -Match '(?m)^\| actions/cache \| v6\.0\.0 \| v6\.1\.0 \| yes \|\s*$'
    }
    It 'sends the token when given one' {
        $null = & $script:scriptPath -RepoRoot (New-TestRepo) -Token 'tok' 6>$null
        Should -Invoke Invoke-RestMethod -ParameterFilter { $Headers['Authorization'] -ceq 'Bearer tok' } -Times 2 -Exactly
    }
    It 'fails when the API fails, rather than reporting a clean table' {
        Mock Invoke-RestMethod { throw 'No such host is known.' }
        { & $script:scriptPath -RepoRoot (New-TestRepo) -Token 'x' 6>$null } | Should -Throw -ExpectedMessage '*failed*No such host is known.*'
    }
}
