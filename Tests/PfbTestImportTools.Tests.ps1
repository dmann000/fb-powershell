#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $script:repoRoot 'tools/lib/PfbTestImportTools.ps1')
    $script:manifestPath = Join-Path $script:repoRoot 'PureStorageFlashBladePowerShell.psd1'
}

Describe 'Get-PfbTestManifestImport classifies every call-site form' {
    BeforeAll {
        $script:fixtureDir = Join-Path $TestDrive 'fixtures'
        $null = New-Item -ItemType Directory -Path $script:fixtureDir -Force
    }

    It 'classifies the <Expected> form' -ForEach @(
        @{ Expected = 'Manifest';       Body = '    Import-Module $manifest -Force' }
        @{ Expected = 'PSScriptRoot';   Body = '    Import-Module "$PSScriptRoot/../PureStorageFlashBladePowerShell.psd1" -Force' }
        @{ Expected = 'JoinPath';       Body = "    Import-Module (Join-Path `$moduleRoot 'PureStorageFlashBladePowerShell.psd1') -Force" }
        @{ Expected = 'ScriptManifest'; Body = '    Import-Module $script:manifest -Force' }
        @{ Expected = 'PassThru';       Body = "    `$script:module = Import-Module (Join-Path `$script:repoRoot 'PureStorageFlashBladePowerShell.psd1') -Force -PassThru" }
    ) {
        $path = Join-Path $script:fixtureDir "$Expected.Tests.ps1"
        Set-Content -LiteralPath $path -Value "BeforeAll {`n$Body`n}" -Encoding UTF8
        $found = @(Get-PfbTestManifestImport -Path $path)
        $found.Count | Should -Be 1
        $found[0].Form | Should -Be $Expected
    }

    It 'classifies a nested Join-Path spelling that spans two lines with a backtick continuation' {
        # Tests/Test-PfbEmptyPipelineRead.Tests.ps1:4, added by PR #125. The extent spans two
        # lines, so the classifier must not assume a single-line argument and the rewriter
        # must splice over both lines. A here-string keeps the backtick literal.
        $path = Join-Path $script:fixtureDir 'NestedJoinPathContinuation.Tests.ps1'
        $body = @'
BeforeAll {
    Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) `
            'PureStorageFlashBladePowerShell.psd1') -Force
}
'@
        Set-Content -LiteralPath $path -Value $body -Encoding UTF8
        $found = @(Get-PfbTestManifestImport -Path $path)
        $found.Count | Should -Be 1
        $found[0].Form | Should -Be 'NestedJoinPath'

        # The offset contract Task 3 splices on, pinned against the fixture's own text.
        # These are CHARACTER offsets into the decoded file with an exclusive EndOffset,
        # so ReadAllText + Substring must round-trip the returned Text exactly. Asserted
        # on the multi-line case specifically: a first-line-only extent (stopping at the
        # backtick) or an off-by-one would corrupt the file byte-wise when spliced.
        $raw = [System.IO.File]::ReadAllText($path)
        $slice = $raw.Substring($found[0].StartOffset, $found[0].EndOffset - $found[0].StartOffset)
        $slice | Should -BeExactly $found[0].Text

        # Begins with the command and ends with the trailing parameter: proves the extent
        # spans the whole two-line command rather than truncating at the continuation.
        $found[0].Text | Should -BeLike 'Import-Module*'
        $found[0].Text | Should -Match '-Force\s*$'
        $found[0].Text.Split("`n").Count | Should -BeGreaterThan 1
    }

    It 'does not match the separate-runspace AddCommand call' {
        $path = Join-Path $script:fixtureDir 'AddCommand.Tests.ps1'
        $body = "BeforeAll {`n" +
            "    `$null = `$ps.AddCommand('Import-Module').AddParameter('Name', `$Manifest).AddParameter('Force', `$true)`n}"
        Set-Content -LiteralPath $path -Value $body -Encoding UTF8
        @(Get-PfbTestManifestImport -Path $path).Count | Should -Be 0
    }

    It 'does not match Import-Module as an argument to Mock' {
        $path = Join-Path $script:fixtureDir 'Mock.Tests.ps1'
        $body = "BeforeAll {`n" +
            "    Mock -ModuleName PureStorageFlashBladePowerShell Import-Module { } -ParameterFilter { `$Name -eq 'Posh-SSH' }`n}"
        Set-Content -LiteralPath $path -Value $body -Encoding UTF8
        @(Get-PfbTestManifestImport -Path $path).Count | Should -Be 0
    }

    It 'buckets an unknown manifest -Force spelling as Unrecognised rather than dropping it' {
        $path = Join-Path $script:fixtureDir 'Odd.Tests.ps1'
        $body = "BeforeAll {`n    Import-Module `$someOtherVariable -Force`n" +
            "    Import-Module (Resolve-Path './PureStorageFlashBladePowerShell.psd1') -Force`n}"
        Set-Content -LiteralPath $path -Value $body -Encoding UTF8
        $found = @(Get-PfbTestManifestImport -Path $path)
        $found.Count | Should -Be 1
        $found[0].Form | Should -Be 'Unrecognised'
    }
}

Describe 'Get-PfbExportedFunctionName reads the manifest statically' {
    It 'returns an explicit list, not a wildcard' {
        $names = @(Get-PfbExportedFunctionName -ManifestPath $script:manifestPath)
        $names.Count | Should -BeGreaterThan 500
        $names | Should -Not -Contain '*'
        $names | Should -Contain 'Connect-PfbArray'
    }
}

Describe 'Test-PfbTestModuleUsage detects the module-use obligation structurally' {
    BeforeAll {
        $script:exported = @(Get-PfbExportedFunctionName -ManifestPath $script:manifestPath)
        $script:usageDir = Join-Path $TestDrive 'usage'
        $null = New-Item -ItemType Directory -Path $script:usageDir -Force
    }

    It 'flags <Case>' -ForEach @(
        @{ Case = 'a call to an exported cmdlet'; Body = '    $null = Get-PfbArray -Array $a'; Uses = $true }
        @{ Case = 'InModuleScope naming the module'; Body = '    InModuleScope PureStorageFlashBladePowerShell { $script:PfbModuleRoot }'; Uses = $true }
        @{ Case = 'Mock -ModuleName naming the module'; Body = '    Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }'; Uses = $true }
        @{ Case = 'a tooling-only file'; Body = "    `$null = Get-PfbApiDriftReport -Path 'x'"; Uses = $false }
        @{ Case = 'a cmdlet name that only appears inside a string'; Body = "    'Connect-PfbArray' | Should -Be 'Connect-PfbArray'"; Uses = $false }
    ) {
        $path = Join-Path $script:usageDir ((New-Guid).Guid + '.Tests.ps1')
        Set-Content -LiteralPath $path -Value "BeforeAll {`n$Body`n}" -Encoding UTF8
        (Test-PfbTestModuleUsage -Path $path -ExportedFunction $script:exported).Uses | Should -Be $Uses
    }

    It 'names the reason it fired, not just that it fired' {
        # Reasons is what a Task 4/5 guard failure quotes back to a maintainer, so pin
        # that it identifies the actual trigger -- the cmdlet and its line -- rather than
        # only agreeing with the Uses boolean.
        $path = Join-Path $script:usageDir 'reasons.Tests.ps1'
        Set-Content -LiteralPath $path -Value "BeforeAll {`n    `$null = Get-PfbArray -Array `$a`n}" -Encoding UTF8
        $result = Test-PfbTestModuleUsage -Path $path -ExportedFunction $script:exported
        $result.Uses | Should -BeTrue
        @($result.Reasons).Count | Should -Be 1
        $result.Reasons[0] | Should -BeExactly 'calls exported cmdlet Get-PfbArray (line 2)'
    }

    It 'reports CallsHelper when the file loads via Import-PfbTestModule' {
        $path = Join-Path $script:usageDir 'helper.Tests.ps1'
        $body = "BeforeAll {`n    . (Join-Path `$PSScriptRoot 'PfbTestModule.ps1')`n" +
            "    `$null = Import-PfbTestModule`n}"
        Set-Content -LiteralPath $path -Value $body -Encoding UTF8
        (Test-PfbTestModuleUsage -Path $path -ExportedFunction $script:exported).CallsHelper | Should -BeTrue
    }
}
