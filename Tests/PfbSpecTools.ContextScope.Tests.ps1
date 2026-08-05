#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $script:repoRoot 'tools/lib/PfbSpecTools.ps1')
}

Describe 'Get-PfbSpecContextScope (synthetic spec)' {

    # No edition guard: Get-PfbSpecContextScope is a pure PSObject walk with no pwsh-7
    # dependency, and these fixtures are shallow enough that Windows PowerShell 5.1's
    # ConvertFrom-Json parses them without -Depth (which it does not support).
    BeforeAll {
        $script:syntheticSpec = @'
{
  "openapi": "3.0.0",
  "paths": {
    "/api/2.28/presets/workload": {
      "get": {
        "x-pure-remote-execution-context-domains-override": ["ARRAY", "FLEET"],
        "responses": { "200": { "description": "ok" } }
      },
      "put": {
        "x-pure-remote-execution-context-domains-override": ["FLEET"],
        "responses": { "200": { "description": "ok" } }
      }
    },
    "/api/2.28/topology-groups": {
      "get": {
        "x-pure-incomplete-gre": true,
        "responses": { "200": { "description": "ok" } }
      }
    },
    "/api/2.28/arrays": {
      "get": {
        "x-pure-block-remote-execution": true,
        "responses": { "200": { "description": "ok" } }
      }
    },
    "/api/2.28/hardware": {
      "get": {
        "x-pure-incomplete-gre": false,
        "responses": { "200": { "description": "ok" } }
      }
    },
    "/api/2.28/alerts": {
      "get": {
        "x-pure-block-remote-execution": false,
        "responses": { "200": { "description": "ok" } }
      }
    },
    "/api/2.28/file-systems": {
      "get": { "responses": { "200": { "description": "ok" } } }
    }
  }
}
'@ | ConvertFrom-Json

        $script:records = @(Get-PfbSpecContextScope -Spec $script:syntheticSpec)
        $script:byEndpoint = @{}
        foreach ($r in $script:records) { $script:byEndpoint[$r.Endpoint] = $r }
    }

    It 'emits one record per operation, sorted by endpoint key' {
        $script:records.Count | Should -Be 7
        $sorted = @($script:records | ForEach-Object { $_.Endpoint } | Sort-Object)
        @($script:records | ForEach-Object { $_.Endpoint }) | Should -Be $sorted
    }

    It 'normalizes the path, stripping the /api/<version> prefix' {
        $script:byEndpoint.Keys | Should -Contain 'GET /presets/workload'
        $script:byEndpoint.Keys | Should -Not -Contain 'GET /api/2.28/presets/workload'
    }

    It 'captures a multi-domain override as an array, preserving both values' {
        $record = $script:byEndpoint['GET /presets/workload']
        @($record.DomainsOverride) | Should -Be @('ARRAY', 'FLEET')
    }

    It 'captures a single-domain override as a one-element array' {
        $record = $script:byEndpoint['PUT /presets/workload']
        @($record.DomainsOverride) | Should -Be @('FLEET')
    }

    It 'reports an EMPTY override array, never $null, when the extension is absent' {
        # Absent must be distinguishable from present-but-empty by the caller without a
        # null check, and an empty array is what the generator's default branch tests.
        $record = $script:byEndpoint['GET /file-systems']
        $null -ne $record.DomainsOverride | Should -BeTrue -Because 'it should be an array object, not $null'
        @($record.DomainsOverride).Count | Should -Be 0
    }

    It 'flags x-pure-incomplete-gre' {
        $script:byEndpoint['GET /topology-groups'].IsIncompleteGre | Should -BeTrue
        $script:byEndpoint['GET /file-systems'].IsIncompleteGre    | Should -BeFalse
    }

    It 'flags x-pure-block-remote-execution' {
        $script:byEndpoint['GET /arrays'].BlocksRemoteExec       | Should -BeTrue
        $script:byEndpoint['GET /file-systems'].BlocksRemoteExec | Should -BeFalse
    }

    It 'reads the VALUE of both flags, not merely the presence of the key' {
        # Upstream emits these only as literal true today, so key-presence alone happens to
        # give the right answer and a presence-only implementation survives every other
        # assertion here. An explicit false must still resolve to false, or an endpoint
        # upstream has deliberately UN-flagged would be forced to unknown/unknown.
        $script:byEndpoint['GET /hardware'].IsIncompleteGre | Should -BeFalse -Because 'x-pure-incomplete-gre is present but false'
        $script:byEndpoint['GET /alerts'].BlocksRemoteExec  | Should -BeFalse -Because 'x-pure-block-remote-execution is present but false'
    }

    It 'returns an empty collection for a spec with no paths' {
        $empty = '{ "openapi": "3.0.0" }' | ConvertFrom-Json
        @(Get-PfbSpecContextScope -Spec $empty).Count | Should -Be 0
    }

    It 'ignores non-HTTP-method keys on a path item' {
        $withParams = @'
{ "openapi": "3.0.0", "paths": { "/api/2.28/x": {
    "parameters": [ { "name": "ignored" } ],
    "get": { "responses": { "200": { "description": "ok" } } } } } }
'@ | ConvertFrom-Json
        @(Get-PfbSpecContextScope -Spec $withParams).Count | Should -Be 1
    }
}

# Edition guard is load-bearing here and must stay: the real fb2.28 spec needs
# ConvertFrom-Json -Depth 64 to parse, and -Depth does not exist before PowerShell 6.2.
Describe 'Get-PfbSpecContextScope (real fb2.28 spec, skips gracefully if absent)' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {

    BeforeAll {
        $script:specPath = Join-Path $script:repoRoot 'tools/specs/fb2.28.json'
        $script:hasSpec = Test-Path $script:specPath
        if ($script:hasSpec) {
            $spec = Get-Content -Path $script:specPath -Raw | ConvertFrom-Json -Depth 64
            $script:realRecords = @(Get-PfbSpecContextScope -Spec $spec)
        }
    }

    It 'finds exactly 5 operations carrying a domains override, all /presets/workload' {
        if (-not $script:hasSpec) { Set-ItResult -Skipped -Because 'tools/specs/fb2.28.json absent'; return }
        $withOverride = @($script:realRecords | Where-Object { @($_.DomainsOverride).Count -gt 0 })
        $withOverride.Count | Should -Be 5
        @($withOverride | ForEach-Object { $_.Path } | Sort-Object -Unique) | Should -Be @('/presets/workload')
    }

    It 'reads the preset overrides as ARRAY+FLEET for GET and FLEET for every write verb' {
        if (-not $script:hasSpec) { Set-ItResult -Skipped -Because 'tools/specs/fb2.28.json absent'; return }
        $byKey = @{}
        foreach ($r in $script:realRecords) { $byKey[$r.Endpoint] = $r }
        @($byKey['GET /presets/workload'].DomainsOverride    | Sort-Object) | Should -Be @('ARRAY', 'FLEET')
        foreach ($verb in 'PUT', 'POST', 'DELETE', 'PATCH') {
            @($byKey["$verb /presets/workload"].DomainsOverride) | Should -Be @('FLEET') -Because "$verb is fleet-only on the wire"
        }
    }

    It 'CANARY: the three extension counts are 5 / 28 / 266 at fb2.28' {
        # Not a correctness assertion -- a tripwire on the upstream annotation pass
        # advancing. When this fails, upstream has filled in more annotations: re-derive
        # the curated table in tools/Build-PfbCapabilityMap.ps1 and retire any entry that
        # has gained an override, then update these numbers deliberately.
        if (-not $script:hasSpec) { Set-ItResult -Skipped -Because 'tools/specs/fb2.28.json absent'; return }
        @($script:realRecords | Where-Object { @($_.DomainsOverride).Count -gt 0 }).Count | Should -Be 5
        @($script:realRecords | Where-Object { $_.IsIncompleteGre }).Count                | Should -Be 28
        @($script:realRecords | Where-Object { $_.BlocksRemoteExec }).Count               | Should -Be 266
    }

    It 'confirms all four curated endpoints are in fact flagged incomplete' {
        # The curated table in the generator only earns its place for FLAGGED endpoints.
        # If one of these ever stops being flagged, its curated value is shadowing data
        # the generator should now be trusting instead.
        if (-not $script:hasSpec) { Set-ItResult -Skipped -Because 'tools/specs/fb2.28.json absent'; return }
        $flagged = @($script:realRecords | Where-Object { $_.IsIncompleteGre } | ForEach-Object { $_.Endpoint })
        foreach ($curated in 'GET /topology-groups', 'GET /topology-groups/arrays', 'GET /topology-groups/members', 'GET /workloads/tags') {
            $flagged | Should -Contain $curated
        }
    }
}
