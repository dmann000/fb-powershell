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

    # Wraps a fragment of report JSON in every property the real report carries, then
    # round-trips it so the fixture has exactly the shape ConvertFrom-Json gives the real file.
    function Build-TestDriftReport {
        param([string]$Json = '{}')
        $report = [ordered]@{
            schemaVersion                   = 1
            analysedVersions                = @('2.27', '2.28')
            uncoveredEndpoints              = @()
            parameterGaps                   = @()
            systemicGaps                    = @()
            conventionStrength              = @()
            validateSetDrift                = @()
            newValidateSetCandidates        = @()
            responseFieldRemovals           = @()
            responseFieldRenameCandidates   = @()
            unhandledResponseEnvelopeFields = @()
        }
        foreach ($property in ($Json | ConvertFrom-Json).PSObject.Properties) { $report[$property.Name] = $property.Value }
        return ([PSCustomObject]$report | ConvertTo-Json -Depth 12 | ConvertFrom-Json)
    }

    function Build-TestDeadKeyReport {
        param([string]$Json = '{}')
        $report = [ordered]@{ specVersion = '2.28'; counts = @{}; deadKeys = @(); noSurvivingSelector = @() }
        foreach ($property in ($Json | ConvertFrom-Json).PSObject.Properties) { $report[$property.Name] = $property.Value }
        return ([PSCustomObject]$report | ConvertTo-Json -Depth 12 | ConvertFrom-Json)
    }

    # One of every category, all in family 'widgets'. Each row is chosen to exercise one
    # shape rule: the partial-confidence row, the string-and-object body entries, the
    # read-only fields that must NOT become findings, and a dead key whose method and
    # slashless path arrive separately.
    $script:fullDriftJson = @'
{
  "uncoveredEndpoints": [ { "endpoint": "GET /widgets", "minVersion": "2.3" } ],
  "parameterGaps": [
    {
      "endpoint": "PATCH /widgets",
      "cmdlets": [ "Update-PfbWidget" ],
      "missingQueryParameters": [ "allow_errors", "ids" ],
      "missingBodyProperties": [ { "name": "name", "type": "string" }, "colour" ],
      "readOnlyFields": [ "id", "created" ],
      "confidence": { "level": "partial", "unresolvedParameters": [], "escapeHatchOnly": [], "caveat": "typed coverage only" },
      "annotations": [ { "matchType": "field", "match": "allow_errors", "kind": "designDecision", "note": "deferred", "reference": null } ]
    }
  ],
  "responseFieldRemovals": [ { "endpoint": "GET /widgets", "field": "colour", "location": "items", "introducedVersion": "2.0", "lastSeenVersion": "2.10" } ],
  "responseFieldRenameCandidates": [ { "endpoint": "GET /widgets", "location": "items", "from": "server", "to": "attached_servers", "version": "2.20" } ],
  "validateSetDrift": [ { "cmdlet": "Get-PfbWidget", "parameter": "Mode", "currentValidateSet": [ "slow" ], "specValues": [ "fast" ], "missingValues": [ "fast" ], "staleValues": [ "slow" ] } ],
  "newValidateSetCandidates": [ { "cmdlet": "Get-PfbWidget", "parameter": "Kind", "wireName": "kind", "specValues": [ "a", "b" ], "recommendation": "ArgumentCompleter" } ],
  "unhandledResponseEnvelopeFields": [ { "field": "errors", "endpointCount": 140 } ]
}
'@
    $script:fullDeadKeyJson = @'
{
  "deadKeys": [ { "severity": "WRONG-RESULTS", "cmdlet": "Get-PfbWidget", "parameter": "Flavour", "wireKey": "flavour", "method": "GET", "endpoint": "widgets", "declared": [ "names" ], "classification": "UNDECLARED", "declaredElsewhere": [] } ],
  "noSurvivingSelector": [ { "cmdlet": "Get-PfbWidgetPart", "method": "GET", "endpoint": "widgets/parts" } ]
}
'@
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

Describe 'Get-PfbDriftFinding' {
    BeforeAll {
        $script:findings = @(Get-PfbDriftFinding -DriftReport (Build-TestDriftReport -Json $script:fullDriftJson) -DeadKeyReport (Build-TestDeadKeyReport -Json $script:fullDeadKeyJson))
        $script:tuples = @($script:findings | ForEach-Object { '{0}|{1}|{2}' -f $_.Category, $_.Endpoint, $_.Field })
    }

    It 'emits one finding per atomic gap, with the documented tuple for every category' {
        $expected = @(
            'uncoveredEndpoint|GET /widgets|'
            'parameterGap|PATCH /widgets|query:allow_errors'
            'parameterGap|PATCH /widgets|query:ids'
            'parameterGap|PATCH /widgets|body:name'
            'parameterGap|PATCH /widgets|body:colour'
            'responseFieldRemoval|GET /widgets|items:colour'
            'responseFieldRename|GET /widgets|items:server->attached_servers'
            'validateSetDrift||Get-PfbWidget:Mode=missing:fast'
            'validateSetDrift||Get-PfbWidget:Mode=stale:slow'
            'newValidateSetCandidate||Get-PfbWidget:Kind'
            'unhandledEnvelopeField||errors'
            'deadKey|GET /widgets|flavour'
            'noSurvivingSelector|GET /widgets/parts|'
        )
        (@(Get-PfbDriftSortedString -Value $script:tuples) -join "`n") | Should -BeExactly (@(Get-PfbDriftSortedString -Value $expected) -join "`n")
    }

    It 'excludes readOnlyFields, which no cmdlet can ever set' {
        @($script:findings | Where-Object { $_.Field -ceq 'body:id' -or $_.Field -ceq 'body:created' }).Count | Should -Be 0
    }

    It 'reads a missingBodyProperties entry whether the report wrote an object or a bare string' {
        @($script:findings | Where-Object { $_.Field -ceq 'body:name' }).Count | Should -Be 1
        @($script:findings | Where-Object { $_.Field -ceq 'body:colour' }).Count | Should -Be 1
    }

    It 'normalises the dead-key report''s separate method and slashless path' {
        $dead = @($script:findings | Where-Object { $_.Category -ceq 'deadKey' })[0]
        $dead.Endpoint | Should -BeExactly 'GET /widgets'
        $dead.Family | Should -BeExactly 'widgets'
        $dead.Fingerprint | Should -BeExactly '1aa1141c6aacfeef'
    }

    It 'carries parameter, cmdlet, confidence and annotation detail for rendering' {
        $gap = @($script:findings | Where-Object { $_.Field -ceq 'query:allow_errors' })[0]
        $gap.Parameter | Should -BeExactly 'allow_errors'
        $gap.Detail.Location | Should -BeExactly 'query'
        ($gap.Detail.Cmdlets -join ',') | Should -BeExactly 'Update-PfbWidget'
        $gap.Detail.Confidence | Should -BeExactly 'partial'
        ($gap.Detail.Annotations -join ';') | Should -BeExactly 'designDecision: deferred'
        @($script:findings | Where-Object { $_.Category -ceq 'newValidateSetCandidate' })[0].Cmdlet | Should -BeExactly 'Get-PfbWidget'
    }

    It 'gives each category its documented severity rank' {
        foreach ($f in $script:findings) { $f.Severity | Should -Be $script:PfbDriftSeverity[$f.Category] }
        @($script:findings | Where-Object { $_.Category -ceq 'deadKey' })[0].Severity | Should -Be 1
        @($script:findings | Where-Object { $_.Category -ceq 'newValidateSetCandidate' })[0].Severity | Should -Be 8
    }

    It 'merges two dead-key rows with one fingerprint into one finding naming both cmdlets' {
        $dead = Build-TestDeadKeyReport -Json @'
{ "deadKeys": [
  { "severity": "WRONG-RESULTS", "cmdlet": "Get-PfbWidgetAll", "parameter": "Flavour", "wireKey": "flavour", "method": "GET", "endpoint": "widgets", "declared": [], "classification": "UNDECLARED", "declaredElsewhere": [] },
  { "severity": "WRONG-RESULTS", "cmdlet": "Get-PfbWidget", "parameter": "Flavour", "wireKey": "flavour", "method": "GET", "endpoint": "widgets", "declared": [], "classification": "UNDECLARED", "declaredElsewhere": [] }
] }
'@
        $result = @(Get-PfbDriftFinding -DriftReport (Build-TestDriftReport) -DeadKeyReport $dead)
        $result.Count | Should -Be 1
        ($result[0].Detail.Cmdlets -join ',') | Should -BeExactly 'Get-PfbWidget,Get-PfbWidgetAll'
    }

    It 'emits findings in ordinal fingerprint order' {
        $fps = @($script:findings | ForEach-Object { $_.Fingerprint })
        ($fps -join ',') | Should -BeExactly (@(Get-PfbDriftSortedString -Value $fps) -join ',')
    }

    It 'returns no findings for empty reports' {
        @(Get-PfbDriftFinding -DriftReport (Build-TestDriftReport) -DeadKeyReport (Build-TestDeadKeyReport)).Count | Should -Be 0
    }

    It 'stops, rather than reading zero findings, when the drift report has no <Name> property' -ForEach @(
        @{ Name = 'uncoveredEndpoints' }
        @{ Name = 'parameterGaps' }
        @{ Name = 'validateSetDrift' }
        @{ Name = 'unhandledResponseEnvelopeFields' }
    ) {
        $report = Build-TestDriftReport
        $report.PSObject.Properties.Remove($Name)
        { Get-PfbDriftFinding -DriftReport $report -DeadKeyReport (Build-TestDeadKeyReport) } | Should -Throw -ExpectedMessage "*$Name*"
    }

    It 'stops on a drift report schemaVersion it does not understand' {
        $report = Build-TestDriftReport -Json '{ "schemaVersion": 2 }'
        { Get-PfbDriftFinding -DriftReport $report -DeadKeyReport (Build-TestDeadKeyReport) } | Should -Throw -ExpectedMessage '*schemaVersion*'
    }

    It 'stops when the dead-key report has no deadKeys property' {
        $dead = Build-TestDeadKeyReport
        $dead.PSObject.Properties.Remove('deadKeys')
        { Get-PfbDriftFinding -DriftReport (Build-TestDriftReport) -DeadKeyReport $dead } | Should -Throw -ExpectedMessage '*deadKeys*'
    }

    It 'reads a missingQueryParameters entry whether the report wrote an object or a bare string' {
        $report = Build-TestDriftReport -Json '{ "parameterGaps": [ { "endpoint": "GET /widgets", "cmdlets": [], "missingQueryParameters": [ { "name": "ids", "type": "string" }, "sort" ], "missingBodyProperties": [], "readOnlyFields": [] } ] }'
        $result = @(Get-PfbDriftFinding -DriftReport $report -DeadKeyReport (Build-TestDeadKeyReport))
        (@(Get-PfbDriftSortedString -Value @($result | ForEach-Object { $_.Field })) -join ',') | Should -BeExactly 'query:ids,query:sort'
        @($result | Where-Object { $_.Field -ceq 'query:ids' })[0].Fingerprint | Should -BeExactly (Get-PfbDriftFingerprint -Category 'parameterGap' -Endpoint 'GET /widgets' -Field 'query:ids')
    }

    It 'stops on a <Location> entry with no name, naming the row' -ForEach @(
        @{ Location = 'query'; Json = '{ "parameterGaps": [ { "endpoint": "GET /widgets", "cmdlets": [], "missingQueryParameters": [ { "type": "string" } ], "missingBodyProperties": [], "readOnlyFields": [] } ] }' }
        @{ Location = 'body'; Json = '{ "parameterGaps": [ { "endpoint": "GET /widgets", "cmdlets": [], "missingQueryParameters": [], "missingBodyProperties": [ { "type": "string" } ], "readOnlyFields": [] } ] }' }
    ) {
        { Get-PfbDriftFinding -DriftReport (Build-TestDriftReport -Json $Json) -DeadKeyReport (Build-TestDeadKeyReport) } | Should -Throw -ExpectedMessage "*GET /widgets*$Location parameter with no name*"
    }

    It 'refuses a field that is a stringified object or carries whitespace, so it is never fingerprinted' {
        { ConvertTo-PfbDriftFindingRecord -Category 'parameterGap' -Endpoint 'GET /widgets' -Field 'query:@{name=ids}' -Detail @{} } | Should -Throw -ExpectedMessage '*stringified object*'
        { ConvertTo-PfbDriftFindingRecord -Category 'parameterGap' -Endpoint 'GET /widgets' -Field 'query:a b' -Detail @{} } | Should -Throw -ExpectedMessage '*stringified object or carries whitespace*'
        $nested = Build-TestDriftReport -Json '{ "parameterGaps": [ { "endpoint": "GET /widgets", "cmdlets": [], "missingQueryParameters": [ { "name": { "text": "ids" } } ], "missingBodyProperties": [], "readOnlyFields": [] } ] }'
        { Get-PfbDriftFinding -DriftReport $nested -DeadKeyReport (Build-TestDeadKeyReport) } | Should -Throw -ExpectedMessage '*stringified object*'
    }
}

Describe 'Get-PfbDriftGroup' {
    BeforeAll {
        $script:groupJson = @'
{ "parameterGaps": [
  { "endpoint": "GET /alpha", "cmdlets": [ "Get-PfbAlpha" ], "missingQueryParameters": [ "sort", "ids" ], "missingBodyProperties": [], "readOnlyFields": [], "confidence": { "level": "high", "caveat": "" }, "annotations": [] },
  { "endpoint": "GET /alpha/things", "cmdlets": [ "Get-PfbAlphaThing" ], "missingQueryParameters": [ "ids" ], "missingBodyProperties": [], "readOnlyFields": [], "confidence": { "level": "high", "caveat": "" }, "annotations": [] },
  { "endpoint": "GET /beta/items", "cmdlets": [ "Get-PfbBetaItem" ], "missingQueryParameters": [ "sort" ], "missingBodyProperties": [], "readOnlyFields": [], "confidence": { "level": "high", "caveat": "" }, "annotations": [] },
  { "endpoint": "PATCH /gamma", "cmdlets": [ "Update-PfbGamma" ], "missingQueryParameters": [], "missingBodyProperties": [ { "name": "sort" } ], "readOnlyFields": [], "confidence": { "level": "high", "caveat": "" }, "annotations": [] }
] }
'@
        function Get-TestGroupKey {
            param([object[]]$Finding, [string]$Field, [string]$Endpoint)
            @($Finding | Where-Object { $_.Field -ceq $Field -and $_.Endpoint -ceq $Endpoint })[0].GroupKey
        }
        $script:grouped = @(Get-PfbDriftFinding -DriftReport (Build-TestDriftReport -Json $script:groupJson) -DeadKeyReport (Build-TestDeadKeyReport))
    }

    It 'files a parameter missing in three families once, as systemic, counting query and body together' {
        Get-TestGroupKey -Finding $script:grouped -Field 'query:sort' -Endpoint 'GET /alpha' | Should -BeExactly 'systemic:sort'
        Get-TestGroupKey -Finding $script:grouped -Field 'query:sort' -Endpoint 'GET /beta/items' | Should -BeExactly 'systemic:sort'
        Get-TestGroupKey -Finding $script:grouped -Field 'body:sort' -Endpoint 'PATCH /gamma' | Should -BeExactly 'systemic:sort'
        @($script:grouped | Where-Object { $_.GroupKey -like 'family:*' -and $_.Parameter -ceq 'sort' }).Count | Should -Be 0
    }

    It 'counts families, not endpoints: two endpoints in one family stay in the family group' {
        Get-TestGroupKey -Finding $script:grouped -Field 'query:ids' -Endpoint 'GET /alpha' | Should -BeExactly 'family:alpha'
        Get-TestGroupKey -Finding $script:grouped -Field 'query:ids' -Endpoint 'GET /alpha/things' | Should -BeExactly 'family:alpha'
    }

    It 'keeps a parameter missing in only two families in its family groups' {
        $report = Build-TestDriftReport -Json $script:groupJson
        $report.parameterGaps = @($report.parameterGaps | Where-Object { $_.endpoint -cne 'PATCH /gamma' })
        $two = @(Get-PfbDriftFinding -DriftReport $report -DeadKeyReport (Build-TestDeadKeyReport))
        Get-TestGroupKey -Finding $two -Field 'query:sort' -Endpoint 'GET /alpha' | Should -BeExactly 'family:alpha'
        Get-TestGroupKey -Finding $two -Field 'query:sort' -Endpoint 'GET /beta/items' | Should -BeExactly 'family:beta'
    }

    It 'honours -SystemicFamilyThreshold' {
        $regrouped = @(Get-PfbDriftGroup -Finding $script:grouped -SystemicFamilyThreshold 4)
        Get-TestGroupKey -Finding $regrouped -Field 'query:sort' -Endpoint 'GET /alpha' | Should -BeExactly 'family:alpha'
    }

    It 'gives every other category its own group kind' {
        $all = @(Get-PfbDriftFinding -DriftReport (Build-TestDriftReport -Json $script:fullDriftJson) -DeadKeyReport (Build-TestDeadKeyReport -Json $script:fullDeadKeyJson))
        $byKey = @{}
        foreach ($f in $all) { $byKey[$f.Category + '|' + $f.Field] = $f.GroupKey }
        $byKey['uncoveredEndpoint|'] | Should -BeExactly 'family:widgets'
        $byKey['parameterGap|query:ids'] | Should -BeExactly 'family:widgets'
        $byKey['responseFieldRemoval|items:colour'] | Should -BeExactly 'family:widgets'
        $byKey['responseFieldRename|items:server->attached_servers'] | Should -BeExactly 'family:widgets'
        $byKey['unhandledEnvelopeField|errors'] | Should -BeExactly 'envelope:errors'
        $byKey['validateSetDrift|Get-PfbWidget:Mode=missing:fast'] | Should -BeExactly 'validateset:Get-PfbWidget'
        $byKey['newValidateSetCandidate|Get-PfbWidget:Kind'] | Should -BeExactly 'validateset:Get-PfbWidget'
        $byKey['deadKey|flavour'] | Should -BeExactly 'deadkey:widgets'
        $byKey['noSurvivingSelector|'] | Should -BeExactly 'deadkey:widgets'
    }
}
