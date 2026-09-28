#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Every remote `uses:` under .github/ is pinned to a commit SHA with a release comment,
    and every workflow added for this check keeps the workflow hygiene rules.
.DESCRIPTION
    A tag such as actions/checkout@v7 is a moving pointer: whoever controls the tag controls
    what runs here. A 40-hex commit SHA is not. The `# vX.Y.Z` comment records which release
    the SHA came from, which is what tools/Get-PfbActionPinStatus.ps1 compares against the
    latest release each week.

    UNGATED on edition: text and regex only, 5.1-safe, no spec cache, no network. Listed in
    RequiredDescribes in both blocks of Tests/coverage-baseline.psd1.
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path (Join-Path (Join-Path $script:repoRoot 'tools') 'lib') 'PfbActionPinTools.ps1')
    $script:sha = '0123456789abcdef0123456789abcdef01234567'

    function Get-TestReference {
        param([string]$Line)
        @(Get-PfbActionReference -Text ($Line + "`n") -File 'fixture.yml')[0]
    }
}

Describe 'Action pin matcher (control pairs)' {
    It 'rejects a tag ref' {
        Test-PfbActionPinned (Get-TestReference '      - uses: actions/checkout@v7') | Should -BeFalse
    }
    It 'accepts a 40-hex SHA with a release comment' {
        Test-PfbActionPinned (Get-TestReference "      - uses: actions/checkout@$($script:sha) # v7.0.1") | Should -BeTrue
    }
    It 'rejects a SHA with no release comment' {
        Test-PfbActionPinned (Get-TestReference "      - uses: actions/checkout@$($script:sha)") | Should -BeFalse
    }
    It 'rejects a 39-hex SHA' {
        Test-PfbActionPinned (Get-TestReference "      - uses: actions/checkout@$($script:sha.Substring(1)) # v7.0.1") | Should -BeFalse
    }
    It 'rejects upper-case hex' {
        Test-PfbActionPinned (Get-TestReference "      - uses: actions/checkout@$($script:sha.ToUpperInvariant()) # v7.0.1") | Should -BeFalse
    }
    It 'rejects a comment that is not a version' {
        Test-PfbActionPinned (Get-TestReference "      - uses: actions/checkout@$($script:sha) # latest") | Should -BeFalse
    }
    It 'reads a quoted value' {
        $ref = Get-TestReference "      - uses: 'actions/checkout@$($script:sha)' # v7.0.1"
        $ref.Uses | Should -BeExactly "actions/checkout@$($script:sha)"
        Test-PfbActionPinned $ref | Should -BeTrue
    }
    It 'splits owner/repo from an action sub-path' {
        $ref = Get-TestReference "      uses: actions/cache/restore@$($script:sha) # v6.1.0"
        $ref.Kind | Should -BeExactly 'remote'
        $ref.Repository | Should -BeExactly 'actions/cache'
        $ref.SubPath | Should -BeExactly 'restore'
        $ref.Sha | Should -BeExactly $script:sha
        $ref.Version | Should -BeExactly 'v6.1.0'
    }
    It 'treats a ./ reference as local, including a job-level reusable workflow' {
        (Get-TestReference '        uses: ./.github/actions/install-test-modules').Kind | Should -BeExactly 'local'
        (Get-TestReference '    uses: ./.github/workflows/cross-platform-tests.yml').Kind | Should -BeExactly 'local'
    }
    It 'classifies docker:// separately so the pin rule can name it' {
        (Get-TestReference '      - uses: docker://alpine:3').Kind | Should -BeExactly 'docker'
    }
    It 'reports the 1-based line of each reference' {
        $refs = @(Get-PfbActionReference -Text "a: 1`nsteps:`n  - uses: actions/checkout@v7`n")
        $refs[0].Line | Should -Be 3
    }
    It 'compares release versions numerically' {
        Test-PfbPinBehind -Pinned 'v7.0.1' -Latest 'v7.0.1' | Should -BeFalse
        Test-PfbPinBehind -Pinned 'v7.0.1' -Latest 'v7.0.10' | Should -BeTrue
        Test-PfbPinBehind -Pinned 'v7.0.1' -Latest 'v8.0.0' | Should -BeTrue
        Test-PfbPinBehind -Pinned 'v7.2.0' -Latest 'v7.10.0' | Should -BeTrue
    }
}

Describe 'Workflow action pins (every remote uses: under .github is SHA-pinned)' {
    BeforeAll {
        $script:files = @(Get-PfbWorkflowFile -RepoRoot $script:repoRoot)
        $script:refs = @(foreach ($f in $script:files) {
                Get-PfbActionReference -Text ([System.IO.File]::ReadAllText($f.FullName)) -File $f.Name
            })
    }
    It 'finds remote references at all (a zero here would make every other test vacuous)' {
        @($script:refs | Where-Object Kind -eq 'remote').Count | Should -BeGreaterThan 0
    }
    It 'parses every uses: line (the extractor misses none)' {
        $lines = 0
        foreach ($f in $script:files) {
            $lines += [regex]::Matches([System.IO.File]::ReadAllText($f.FullName), '(?m)^[ \t]*(?:-[ \t]+)?uses:').Count
        }
        $script:refs.Count | Should -Be $lines
    }
    It 'pins every remote reference to a SHA with a # vX.Y.Z comment' {
        $unpinned = @($script:refs | Where-Object { $_.Kind -ne 'local' -and -not (Test-PfbActionPinned $_) } |
                ForEach-Object { '{0}:{1} {2}{3}' -f $_.File, $_.Line, $_.Uses, $_.Rest })
        $unpinned -join "`n" | Should -BeNullOrEmpty
    }
    It 'pins each action repository to ONE SHA and ONE version everywhere' {
        $split = @($script:refs | Where-Object Kind -eq 'remote' | Group-Object Repository | Where-Object {
                @($_.Group | ForEach-Object { '{0}|{1}' -f $_.Sha, $_.Version } | Sort-Object -Unique).Count -gt 1
            } | ForEach-Object { $_.Name })
        $split -join ', ' | Should -BeNullOrEmpty
    }
}

Describe 'verify-workflows.yml (actionlint)' {
    BeforeAll {
        $script:wf = [System.IO.File]::ReadAllText((Join-Path $script:repoRoot '.github/workflows/verify-workflows.yml'))
        $script:runBlocks = @([regex]::Matches($script:wf, '(?m)^([ \t]+)(?:- )?run: \|[ \t]*\r?\n((?:(?:\1[ \t]+\S[^\r\n]*|[ \t]*)(?:\r?\n|$))+)') | ForEach-Object { $_.Groups[2].Value })
    }
    It 'runs on pull requests that touch .github/, and on dispatch' {
        $script:wf | Should -Match "(?m)^  pull_request:\s*\r?\n    paths:\s*\r?\n      - '\.github/\*\*'"
        $script:wf | Should -Match '(?m)^  workflow_dispatch:'
    }
    It 'asks for contents: read and nothing else' {
        $permissions = [regex]::Match($script:wf, '(?ms)^permissions:[ \t]*\r?\n(.*?)(?=^\S)').Groups[1].Value
        @([regex]::Matches($permissions, '(?m)^  ([a-z-]+: \S+)') | ForEach-Object { $_.Groups[1].Value }) -join ',' | Should -BeExactly 'contents: read'
        $script:wf | Should -Not -Match 'secrets\.'
    }
    It 'verifies the downloaded binary against a pinned sha256 before running it' {
        $script:wf | Should -Match '(?m)^\s+ACTIONLINT_SHA256: ''[0-9a-f]{64}''\s*$'
        $script:wf | Should -Match '(?m)^\s+ACTIONLINT_VERSION: ''\d+\.\d+\.\d+''\s*$'
        $script:wf | Should -Match 'Get-FileHash -Algorithm SHA256'
        $script:wf.IndexOf('Get-FileHash') | Should -BeLessThan $script:wf.IndexOf('-config-file .github/actionlint.yaml')
    }
    It 'uses no third-party action' {
        @([regex]::Matches($script:wf, '(?m)^\s+(?:- )?uses: (\S+)') | ForEach-Object { $_.Groups[1].Value } |
                Where-Object { $_ -notmatch '^actions/checkout@' }).Count | Should -Be 0
    }
    It 'interpolates nothing into a run block' {
        $script:runBlocks.Count | Should -BeGreaterThan 0
        @($script:runBlocks | Where-Object { $_.Contains('${{') }).Count | Should -Be 0
        @([regex]::Matches($script:wf, '(?m)^[ \t]+(?:- )?run: (?!\|)(.*)$') | Where-Object { $_.Groups[1].Value.Contains('${{') }).Count | Should -Be 0
    }
}

Describe 'report-action-pins.yml (weekly, report-only)' {
    BeforeAll {
        $script:rp = [System.IO.File]::ReadAllText((Join-Path $script:repoRoot '.github/workflows/report-action-pins.yml'))
    }
    It 'runs weekly and on dispatch, and on nothing else' {
        $on = [regex]::Match($script:rp, '(?ms)^on:\r?\n(.*?)(?=^\S)').Groups[1].Value
        @([regex]::Matches($on, '(?m)^  ([a-z_]+):') | ForEach-Object { $_.Groups[1].Value }) -join ',' | Should -BeExactly 'schedule,workflow_dispatch'
    }
    It 'reads contents only and writes nothing' {
        $permissions = [regex]::Match($script:rp, '(?ms)^permissions:[ \t]*\r?\n(.*?)(?=^\S)').Groups[1].Value
        @([regex]::Matches($permissions, '(?m)^  ([a-z-]+: \S+)') | ForEach-Object { $_.Groups[1].Value }) -join ',' | Should -BeExactly 'contents: read'
        @([regex]::Matches($script:rp, '(?m)^\s+[a-z-]+: write\s*$')).Count | Should -Be 0
        @([regex]::Matches($script:rp, 'secrets\.([A-Za-z_]+)') | ForEach-Object { $_.Groups[1].Value } | Where-Object { $_ -cne 'GITHUB_TOKEN' }).Count | Should -Be 0
    }
    It 'interpolates nothing into a run block' {
        $blocks = @([regex]::Matches($script:rp, '(?m)^([ \t]+)(?:- )?run: \|[ \t]*\r?\n((?:(?:\1[ \t]+\S[^\r\n]*|[ \t]*)(?:\r?\n|$))+)') | ForEach-Object { $_.Groups[2].Value })
        $blocks.Count | Should -Be 1
        @($blocks | Where-Object { $_.Contains('${{') }).Count | Should -Be 0
    }
    It 'runs the report script with the job summary as its output' {
        $script:rp | Should -Match ([regex]::Escape('./tools/Get-PfbActionPinStatus.ps1 -SummaryPath $env:GITHUB_STEP_SUMMARY'))
    }
}
