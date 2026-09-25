#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    The pure half of the drift -> GitHub issue reconciler (tools/lib/PfbDriftIssueTools.ps1).
.DESCRIPTION
    Every rule the reconciler applies -- fingerprints, grouping, the machine block, settled
    keys and the reconcile table -- runs here against small synthetic fixtures. Never the
    committed 600 KB report: a fixture states the case it tests, while the real report
    changes underneath the assertion every week.

    NOT EDITION-GATED. The library is 5.1-compatible on purpose, so this file runs on both
    legs and skips nothing -- which is why it has no entry in Tests/coverage-baseline.psd1.

    The golden fingerprints are PINS, not examples. Fingerprints are stamped into issues on
    github.com and GitHub is the reconciler's only state; if one of these moves, every
    stamped issue is re-keyed at once. A red there means the change is wrong, not the pin.
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path (Join-Path (Join-Path $script:repoRoot 'tools') 'lib') 'PfbDriftIssueTools.ps1')
}

Describe 'Get-PfbDriftFingerprint' {
    It 'produces the pinned fingerprint for <Category> | <Endpoint> | <Field>' -ForEach @(
        @{ Category = 'uncoveredEndpoint'; Endpoint = 'GET /widgets'; Field = ''; Expected = '69f4e2d74329848a' }
        @{ Category = 'parameterGap'; Endpoint = 'GET /widgets'; Field = 'query:allow_errors'; Expected = '49a2461c5d8543b8' }
        @{ Category = 'parameterGap'; Endpoint = 'PATCH /widgets'; Field = 'body:name'; Expected = '08ab39051f709bbb' }
        @{ Category = 'responseFieldRemoval'; Endpoint = 'GET /widgets'; Field = 'items:colour'; Expected = '3770c21d34523950' }
        @{ Category = 'responseFieldRename'; Endpoint = 'GET /widgets'; Field = 'items:server->attached_servers'; Expected = '10bcbd2ccc9856de' }
        @{ Category = 'validateSetDrift'; Endpoint = ''; Field = 'Get-PfbWidget:Mode=missing:fast'; Expected = '9ad232e58ec74f5c' }
        @{ Category = 'newValidateSetCandidate'; Endpoint = ''; Field = 'Get-PfbWidget:Kind'; Expected = '0b189d51ea5cf5f5' }
        @{ Category = 'unhandledEnvelopeField'; Endpoint = ''; Field = 'errors'; Expected = '0411599c36ccff9a' }
        @{ Category = 'deadKey'; Endpoint = 'GET /widgets'; Field = 'flavour'; Expected = '1aa1141c6aacfeef' }
        @{ Category = 'noSurvivingSelector'; Endpoint = 'GET /widgets/parts'; Field = ''; Expected = '32f2b3c0c0fc8e51' }
    ) {
        Get-PfbDriftFingerprint -Category $Category -Endpoint $Endpoint -Field $Field | Should -BeExactly $Expected
    }

    It 'is 16 lowercase hex characters and stable across calls' {
        $first = Get-PfbDriftFingerprint -Category 'deadKey' -Endpoint 'GET /alerts' -Field 'flagged'
        $first | Should -MatchExactly '^[0-9a-f]{16}$'
        Get-PfbDriftFingerprint -Category 'deadKey' -Endpoint 'GET /alerts' -Field 'flagged' | Should -BeExactly $first
    }

    It 'changes when any one component changes' {
        $base = Get-PfbDriftFingerprint -Category 'parameterGap' -Endpoint 'GET /widgets' -Field 'query:ids'
        Get-PfbDriftFingerprint -Category 'deadKey' -Endpoint 'GET /widgets' -Field 'query:ids' | Should -Not -Be $base
        Get-PfbDriftFingerprint -Category 'parameterGap' -Endpoint 'POST /widgets' -Field 'query:ids' | Should -Not -Be $base
        Get-PfbDriftFingerprint -Category 'parameterGap' -Endpoint 'GET /widgets' -Field 'body:ids' | Should -Not -Be $base
    }

    It 'rejects a category that is not exactly one of the frozen tokens' {
        { Get-PfbDriftFingerprint -Category 'DeadKey' -Endpoint 'GET /x' -Field 'k' } | Should -Throw -ExpectedMessage '*not a drift category token*'
        { Get-PfbDriftFingerprint -Category 'systemicGap' -Endpoint 'GET /x' -Field 'k' } | Should -Throw -ExpectedMessage '*not a drift category token*'
    }

    It 'rejects the separator inside a component' {
        { Get-PfbDriftFingerprint -Category 'deadKey' -Endpoint 'GET /x|y' -Field 'k' } | Should -Throw -ExpectedMessage '*separator*'
        { Get-PfbDriftFingerprint -Category 'deadKey' -Endpoint 'GET /x' -Field 'a|b' } | Should -Throw -ExpectedMessage '*separator*'
    }
}

Describe 'ConvertTo-PfbDriftEndpoint' {
    It 'normalises method <Method> and path <Path>' -ForEach @(
        @{ Method = 'get'; Path = 'alerts'; Expected = 'GET /alerts' }
        @{ Method = 'GET'; Path = '/arrays/performance/'; Expected = 'GET /arrays/performance' }
        @{ Method = ' delete '; Path = ' node-groups/nodes '; Expected = 'DELETE /node-groups/nodes' }
    ) {
        ConvertTo-PfbDriftEndpoint -Method $Method -Path $Path | Should -BeExactly $Expected
    }

    It 'normalises a METHOD /path key the same way' {
        ConvertTo-PfbDriftEndpoint -Endpoint 'GET  /api/login-banner' | Should -BeExactly 'GET /api/login-banner'
        ConvertTo-PfbDriftEndpoint -Endpoint 'patch /file-systems/' | Should -BeExactly 'PATCH /file-systems'
    }

    It 'refuses input it cannot normalise' {
        { ConvertTo-PfbDriftEndpoint -Endpoint '/alerts' } | Should -Throw -ExpectedMessage "*not in 'METHOD /path' form*"
        { ConvertTo-PfbDriftEndpoint -Method 'GET' -Path '/' } | Should -Throw -ExpectedMessage '*cannot be normalised*'
        { ConvertTo-PfbDriftEndpoint -Method 'G3T' -Path 'alerts' } | Should -Throw -ExpectedMessage '*not an HTTP method*'
    }
}

Describe 'Get-PfbDriftFamily' {
    It 'takes the first path segment of <Endpoint>' -ForEach @(
        @{ Endpoint = 'GET /api/login-banner'; Expected = 'api' }
        @{ Endpoint = 'POST /file-systems/locks/nlm-reclamations'; Expected = 'file-systems' }
        @{ Endpoint = 'GET /arrays'; Expected = 'arrays' }
        @{ Endpoint = ''; Expected = '' }
    ) {
        Get-PfbDriftFamily -Endpoint $Endpoint | Should -BeExactly $Expected
    }
}

Describe 'Get-PfbDriftSortedString and Get-PfbDriftItem' {
    It 'sorts ordinally and de-duplicates' {
        (@(Get-PfbDriftSortedString -Value @('b', 'B', 'a', 'a')) -join ',') | Should -BeExactly 'B,a,b'
    }

    It 'orders a hyphen before a letter, which culture-aware sorting on 5.1 does not' {
        $sorted = @(Get-PfbDriftSortedString -Value @('GET /policies/file-systems', 'GET /policies/file-system-snapshots'))
        $sorted[0] | Should -BeExactly 'GET /policies/file-system-snapshots'
    }

    It 'returns nothing for an empty or null list' {
        @(Get-PfbDriftSortedString -Value @()).Count | Should -Be 0
        @(Get-PfbDriftSortedString -Value $null).Count | Should -Be 0
    }

    It 'drops nulls, so a JSON null never becomes a one-element list' {
        @(Get-PfbDriftItem $null).Count | Should -Be 0
        @(Get-PfbDriftItem @($null, 'a', $null)).Count | Should -Be 1
        @(Get-PfbDriftItem ([PSCustomObject]@{ a = 1 })).Count | Should -Be 1
    }
}
