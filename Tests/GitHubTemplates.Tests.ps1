#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Structural checks on the issue forms and the PR template. GitHub validates issue forms
    only when someone opens the "new issue" page on the default branch, so a typo would ship
    silently; these checks are the only thing that sees one first.
.DESCRIPTION
    UNGATED on edition: text only, 5.1-safe. Listed in RequiredDescribes for both editions.
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:templates = Join-Path (Join-Path $script:repoRoot '.github') 'ISSUE_TEMPLATE'
    function Read-TestTemplate { param([string]$Name) [System.IO.File]::ReadAllText((Join-Path $script:templates $Name)) }
}

Describe 'GitHub issue forms and PR template' {
    It '<Name> has the top-level keys an issue form needs, and applies no labels' -ForEach @(
        @{ Name = 'bug.yml' }, @{ Name = 'feature.yml' }
    ) {
        $t = Read-TestTemplate $Name
        foreach ($key in 'name', 'description', 'body') { $t | Should -Match "(?m)^${key}:" }
        # The drift reconciler treats its source label as machine ownership; a form must never apply it
        # or any other label, so a hand-opened issue can never look machine-owned.
        $t | Should -Not -Match '(?m)^labels:'
    }
    It '<Name> uses only known body element types, and every input has a unique id and a label' -ForEach @(
        @{ Name = 'bug.yml' }, @{ Name = 'feature.yml' }
    ) {
        $t = Read-TestTemplate $Name
        $types = @([regex]::Matches($t, '(?m)^  - type: (\S+)') | ForEach-Object { $_.Groups[1].Value })
        $types.Count | Should -BeGreaterThan 0
        @($types | Where-Object { $_ -notin 'markdown', 'input', 'textarea', 'dropdown', 'checkboxes' }).Count | Should -Be 0
        $ids = @([regex]::Matches($t, '(?m)^    id: (\S+)') | ForEach-Object { $_.Groups[1].Value })
        $ids.Count | Should -Be @($types | Where-Object { $_ -ne 'markdown' }).Count
        @($ids | Sort-Object -Unique).Count | Should -Be $ids.Count
        [regex]::Matches($t, '(?m)^      label: ').Count | Should -Be $ids.Count
    }
    It 'bug.yml asks for the versions, the repro, and the expected and actual behaviour' {
        $t = Read-TestTemplate 'bug.yml'
        foreach ($id in 'module-version', 'powershell-edition', 'powershell-version', 'rest-version', 'repro', 'expected', 'actual') {
            $t | Should -Match "(?m)^    id: $id\s*$"
        }
    }
    It 'config.yml keeps blank issues enabled' {
        (Read-TestTemplate 'config.yml') | Should -Match '(?m)^blank_issues_enabled: true\s*$'
    }
    It 'the PR template closes and links nothing: every #N sits inside an HTML comment' {
        $t = [System.IO.File]::ReadAllText((Join-Path (Join-Path $script:repoRoot '.github') 'PULL_REQUEST_TEMPLATE.md'))
        $visible = [regex]::Replace($t, '<!--[\s\S]*?-->', '')
        $visible | Should -Not -Match '#\d'
        $t | Should -Match '(?s)<!--.*[Ff]ixes #1, fixes #2.*-->'
    }
}
