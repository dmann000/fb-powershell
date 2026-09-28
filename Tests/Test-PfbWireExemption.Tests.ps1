#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    tools/Test-PfbWireExemption.ps1 against scratch git repositories, one mutation each.
.DESCRIPTION
    A green verdict on a real branch proves nothing on its own: a classifier that always said
    "exempt" would produce it too. Each case builds a throwaway repo, makes ONE specific
    change on a feature branch, and asserts the verdict -- including the cases a regex-based
    check gets wrong (#Requires, a comment on a code line, '<#' or '#' inside a here-string).

    Setup that must NOT be part of the diff is committed on main BEFORE the feature branch is
    cut (the -Base scriptblock). The original harness committed it on the feature branch,
    which made its here-string case NOT EXEMPT for the wrong reason.

    EDITION-GATED: -Skip:($PSVersionTable.PSVersion.Major -lt 7) on every Describe; the 5.1
    skip count is pinned in Tests/coverage-baseline.psd1.
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:checker = Join-Path (Join-Path $script:repoRoot 'tools') 'Test-PfbWireExemption.ps1'
    $script:utf8 = New-Object System.Text.UTF8Encoding $false
    $script:cmdlet = 'Public/Things/Get-PfbThing.ps1'
    $script:cmdletSource = (@'
<#
.SYNOPSIS
    Fake cmdlet.
.DESCRIPTION
    Original description.
#>
function Get-PfbThing {
    [CmdletBinding()]
    param([string]$Name)

    $uri = "/api/2.0/things"
    $body = @{ name = $Name }
    Invoke-PfbApiRequest -Uri $uri -Body $body   # trailing comment here
}
'@) -replace "`r`n", "`n"

    function Invoke-TestGit {
        param([string]$Repo, [string[]]$Arguments)
        $out = & git -C $Repo @Arguments 2>&1
        if ($LASTEXITCODE -ne 0) { throw "git $($Arguments -join ' ') failed: $out" }
        $out
    }
    function Write-TestFile {
        param([string]$Repo, [string]$RelativePath, [string]$Content)
        $full = Join-Path $Repo $RelativePath
        $dir = Split-Path -Parent $full
        if (-not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
        [System.IO.File]::WriteAllText($full, $Content, $script:utf8)
    }
    # Throws on a miss. A Replace() that silently finds nothing would turn an "exempt" case
    # into a pass on an unchanged file.
    function Edit-TestFile {
        param([string]$Repo, [string]$RelativePath, [string]$Old, [string]$New)
        $full = Join-Path $Repo $RelativePath
        $text = [System.IO.File]::ReadAllText($full)
        if (-not $text.Contains($Old)) { throw "Edit-TestFile: '$Old' not found in $RelativePath" }
        [System.IO.File]::WriteAllText($full, $text.Replace($Old, $New), $script:utf8)
    }
    function New-TestRepo {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Test helper building a scratch git repo under $TestDrive; nothing to confirm.')]
        param([scriptblock]$Base)
        $repo = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $repo
        Invoke-TestGit $repo @('init', '-q', '-b', 'main') | Out-Null
        foreach ($pair in @(
                @('user.email', 't@example.invalid'), @('user.name', 'test'),
                @('core.autocrlf', 'false'), @('commit.gpgsign', 'false'),
                @('core.hooksPath', (Join-Path $repo '.no-hooks')))) {
            Invoke-TestGit $repo @('config', $pair[0], $pair[1]) | Out-Null
        }
        Write-TestFile $repo $script:cmdlet $script:cmdletSource
        Write-TestFile $repo 'Tests/Some.Tests.ps1' "Describe 'x' { It 'y' { 1 | Should -Be 1 } }`n"
        Write-TestFile $repo 'PureStorageFlashBladePowerShell.psd1' "@{ ModuleVersion = '1.0.0' }`n"
        Write-TestFile $repo 'PureStorageFlashBladePowerShell.psm1' "# module loader`n. (Join-Path `$PSScriptRoot 'x.ps1')`n"
        if ($Base) { & $Base $repo }
        Invoke-TestGit $repo @('add', '-A') | Out-Null
        Invoke-TestGit $repo @('commit', '-q', '-m', 'base') | Out-Null
        Invoke-TestGit $repo @('checkout', '-q', '-b', 'feature') | Out-Null
        return $repo
    }
    function Invoke-TestCase {
        param([scriptblock]$Mutate, [scriptblock]$Base, [hashtable]$Extra = @{})
        $repo = New-TestRepo -Base $Base
        & $Mutate $repo
        Invoke-TestGit $repo @('add', '-A') | Out-Null
        Invoke-TestGit $repo @('commit', '-q', '-m', 'change') | Out-Null
        $params = @{ RepoPath = $repo; BaseRef = 'main' }
        foreach ($k in $Extra.Keys) { $params[$k] = $Extra[$k] }
        $out = @(& $script:checker @params 6>$null)
        [pscustomobject]@{ Output = $out; ExitCode = $LASTEXITCODE; Repo = $repo }
    }
}

# -ForEach data is evaluated at DISCOVERY, before any BeforeAll runs, so scriptblocks the
# data table references by variable must be defined here. The blocks' BODIES run later,
# inside an It, where the BeforeAll helpers and $script:cmdlet exist. They are $script:
# variables, as elsewhere in this repo's BeforeDiscovery blocks: a plain local that is only
# read from another block is "assigned but never used" to PSUseDeclaredVarsMoreThanAssignments,
# which the analyze job gates at zero.
BeforeDiscovery {
    $script:hereStringLt = { param($r) Edit-TestFile $r $script:cmdlet "Invoke-PfbApiRequest -Uri `$uri -Body `$body   # trailing comment here`n}" ("Invoke-PfbApiRequest -Uri `$uri -Body `$body   # trailing comment here`n}`nfunction Get-PfbDoc {`n    `$t = @`"`n<# this is data, not a comment #>`n`"@`n    `$t`n}") }
    $script:hereStringHash = { param($r) Edit-TestFile $r $script:cmdlet "Invoke-PfbApiRequest -Uri `$uri -Body `$body   # trailing comment here`n}" ("Invoke-PfbApiRequest -Uri `$uri -Body `$body   # trailing comment here`n}`nfunction Get-PfbNote {`n    `$t = @`"`n# not a comment, just data`n`"@`n    `$t`n}") }
}

Describe 'Test-PfbWireExemption exit codes (ported from the original negative-control harness, plus additions)' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
    It '<Name> -> exit <Code>' -ForEach @(
        # --- the 13 original cases --------------------------------------------------------
        @{ Name = 'comment-only edit in a help block'; Code = 0; Base = $null; Mutate = { param($r) Edit-TestFile $r $script:cmdlet 'Original description.' 'Rewritten description.' } }
        @{ Name = 'whole help block added above the function'; Code = 0; Base = $null; Mutate = { param($r) Edit-TestFile $r $script:cmdlet 'function Get-PfbThing {' "<#`n.NOTES`n    Added block.`n#>`nfunction Get-PfbThing {" } }
        @{ Name = 'Tests/ only (nothing in scope)'; Code = 0; Base = $null; Mutate = { param($r) Write-TestFile $r 'Tests/Some.Tests.ps1' "Describe 'x' { It 'y' { 1 | Should -Be 1 } }`n# more`n" } }
        @{ Name = 'a help line deleted (deletion-only, inert)'; Code = 0; Base = $null; Mutate = { param($r) Edit-TestFile $r $script:cmdlet ".DESCRIPTION`n    Original description.`n" '' } }
        @{ Name = 'executable line changed (uri)'; Code = 1; Base = $null; Mutate = { param($r) Edit-TestFile $r $script:cmdlet '/api/2.0/things' '/api/2.1/things' } }
        @{ Name = 'executable line removed (deletion-only, base-side check)'; Code = 1; Base = $null; Mutate = { param($r) Edit-TestFile $r $script:cmdlet "    `$body = @{ name = `$Name }`n" '' } }
        @{ Name = 'comment edited on a line that also holds code'; Code = 1; Base = $null; Mutate = { param($r) Edit-TestFile $r $script:cmdlet '# trailing comment here' '# reworded comment' } }
        @{ Name = '#Requires added (a Comment token that changes load behaviour)'; Code = 1; Base = $null; Mutate = { param($r) Edit-TestFile $r $script:cmdlet '<#' "#Requires -Version 7.0`n<#" } }
        @{ Name = 'new cmdlet file added to Public/'; Code = 1; Base = $null; Mutate = { param($r) Write-TestFile $r 'Public/Things/Get-PfbOther.ps1' "function Get-PfbOther { 'x' }`n" } }
        @{ Name = 'cmdlet file deleted from Public/'; Code = 1; Base = $null; Mutate = { param($r) Remove-Item (Join-Path $r $script:cmdlet) } }
        @{ Name = 'manifest changed'; Code = 1; Base = $null; Mutate = { param($r) Edit-TestFile $r 'PureStorageFlashBladePowerShell.psd1' '1.0.0' '1.0.1' } }
        @{ Name = 'one executable line alongside a comment-only edit'; Code = 1; Base = $null; Mutate = { param($r) Edit-TestFile $r $script:cmdlet 'Original description.' 'Reworded.'; Edit-TestFile $r $script:cmdlet '/api/2.0/' '/api/2.9/' } }
        @{ Name = "'<#' inside an edited here-string (setup on main)"; Code = 1; Base = $script:hereStringLt; Mutate = { param($r) Edit-TestFile $r $script:cmdlet 'this is data' 'this is payload' } }
        # --- additions: rename, #Requires edited, '#' in a here-string, root module ----------
        @{ Name = "'#' inside an edited here-string (setup on main)"; Code = 1; Base = $script:hereStringHash; Mutate = { param($r) Edit-TestFile $r $script:cmdlet 'just data' 'just payload' } }
        @{ Name = '#Requires edited (setup on main)'; Code = 1; Base = { param($r) Edit-TestFile $r $script:cmdlet '<#' "#Requires -Version 5.1`n<#" }; Mutate = { param($r) Edit-TestFile $r $script:cmdlet '#Requires -Version 5.1' '#Requires -Version 7.0' } }
        @{ Name = 'cmdlet file renamed in Public/'; Code = 1; Base = $null; Mutate = { param($r) Invoke-TestGit $r @('mv', $script:cmdlet, 'Public/Things/Get-PfbThing2.ps1') | Out-Null } }
        @{ Name = 'comment-only edit in the root module (in scope, inert)'; Code = 0; Base = $null; Mutate = { param($r) Edit-TestFile $r 'PureStorageFlashBladePowerShell.psm1' '# module loader' '# module loader, reworded' } }
    ) {
        $case = Invoke-TestCase -Mutate $Mutate -Base $Base
        $case.ExitCode | Should -Be $Code -Because ($case.Output | Out-String)
    }

    It 'an unreachable base ref cannot be decided -> exit 2' {
        $case = Invoke-TestCase -Mutate { param($r) Edit-TestFile $r $script:cmdlet '/api/2.0/' '/api/2.1/' } -Extra @{ BaseRef = 'no-such-ref' }
        $case.ExitCode | Should -Be 2
    }
}

Describe 'Test-PfbWireExemption verdict object' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
    It 'emits exactly one object, whose Decision agrees with the exit code (<Decision>)' -ForEach @(
        @{ Decision = 'Exempt'; Code = 0; Mutate = { param($r) Edit-TestFile $r $script:cmdlet 'Original description.' 'Rewritten.' }; Extra = @{} }
        @{ Decision = 'NotExempt'; Code = 1; Mutate = { param($r) Edit-TestFile $r $script:cmdlet '/api/2.0/' '/api/2.1/' }; Extra = @{} }
        @{ Decision = 'Undecided'; Code = 2; Mutate = { param($r) Edit-TestFile $r $script:cmdlet '/api/2.0/' '/api/2.1/' }; Extra = @{ BaseRef = 'no-such-ref' } }
    ) {
        $case = Invoke-TestCase -Mutate $Mutate -Extra $Extra
        $case.Output.Count | Should -Be 1 -Because 'human-readable text goes to Write-Host, never the success stream'
        $case.Output[0].Decision | Should -BeExactly $Decision
        $case.ExitCode | Should -Be $Code
    }
    It 'carries a paste-ready Basis only when exempt' {
        (Invoke-TestCase -Mutate { param($r) Edit-TestFile $r $script:cmdlet 'Original description.' 'Rewritten.' }).Output[0].Basis | Should -Match '\S'
        (Invoke-TestCase -Mutate { param($r) Edit-TestFile $r $script:cmdlet '/api/2.0/' '/api/2.1/' }).Output[0].Basis | Should -BeNullOrEmpty
    }
    It 'names the file, its verdict and the first executable line changed' {
        $v = (Invoke-TestCase -Mutate { param($r) Edit-TestFile $r $script:cmdlet '/api/2.0/' '/api/2.1/' }).Output[0]
        @($v.Files).Count | Should -Be 1
        $v.Files[0].Path | Should -BeExactly $script:cmdlet
        $v.Files[0].Verdict | Should -BeExactly 'Executable'
        $v.Files[0].FirstExecutableLine | Should -Be 11
    }
    It 'an unreachable -HeadRef cannot be decided -> Undecided, exit 2' {
        $case = Invoke-TestCase -Mutate { param($r) Edit-TestFile $r $script:cmdlet '/api/2.0/' '/api/2.1/' } -Extra @{ HeadRef = 'no-such-ref' }
        $case.Output[0].Decision | Should -BeExactly 'Undecided'
        $case.ExitCode | Should -Be 2
    }
    It 'classifies -HeadRef, not whatever is checked out (control pair)' {
        $case = Invoke-TestCase -Mutate { param($r) Edit-TestFile $r $script:cmdlet '/api/2.0/' '/api/2.1/' }
        Invoke-TestGit $case.Repo @('checkout', '-q', 'main') | Out-Null
        $atHead = @(& $script:checker -RepoPath $case.Repo -BaseRef main 6>$null)
        $atHead[0].Decision | Should -BeExactly 'Exempt' -Because 'HEAD is main, so the diff is empty'
        $atFeature = @(& $script:checker -RepoPath $case.Repo -BaseRef main -HeadRef feature 6>$null)
        $atFeature[0].Decision | Should -BeExactly 'NotExempt'
    }
}

Describe 'Test-PfbWireExemption is publishable as written' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
    BeforeAll { $script:src = [System.IO.File]::ReadAllText($script:checker) }
    It 'names no private rule and no local tooling' {
        $script:src | Should -Not -Match '(?i)private (development )?rule'
        $script:src | Should -Not -Match '(?i)does not belong|not belong in'
    }
    # Any drive root, not just 'X:\<letter>': an elided 'C:\...\worktrees' must fail too.
    It 'carries no absolute Windows path' {
        $script:src | Should -Not -Match '(?<![A-Za-z])[A-Za-z]:\\'
    }
    It 'documents how a gate must recompute the verdict rather than trust a CI result' {
        $script:src | Should -Match ([regex]::Escape('git show origin/main:tools/Test-PfbWireExemption.ps1'))
        $script:src | Should -Match '(?i)never read'
    }
    It 'documents -HeadRef and the verdict object' {
        $script:src | Should -Match '\.PARAMETER HeadRef'
        $script:src | Should -Match '(?s)\.OUTPUTS.*Decision.*Files.*Basis'
    }
    # '#Requires' directly above '<#' makes Get-Help lose the synopsis, so the blank line
    # between them is load-bearing.
    It 'keeps its comment help discoverable by Get-Help' {
        (Get-Help $script:checker).Synopsis | Should -Match '\S'
        (Get-Help $script:checker).Synopsis | Should -Not -Match ([regex]::Escape('Test-PfbWireExemption.ps1'))
    }
}
