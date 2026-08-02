#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Unit tests for tools/lib/PfbContextRuleTools.ps1 and the module's single declared
    context-cardinality rule, Private/Test-PfbContextMultiValueCapable.ps1.
.DESCRIPTION
    Note on InModuleScope: deliberately NOT used. PfbContextRuleTools.ps1 is dot-sourced
    from tools/lib/ and its functions are therefore directly callable, and it in turn
    dot-sources the Private/ predicate itself -- so the predicate is in scope here without
    importing the module at all. That is the point of the design: the rule has exactly one
    home, and both the check and these tests reach the same copy.

    Note on what is asserted: SPECIFIC ENDPOINTS and STRUCTURE, never population totals.
    The capability map is regenerated whenever specs are refreshed, so a test pinning "135
    capable" or "376 endpoints" would break on unrelated maintenance. The four fleet-scoped
    endpoints confirmed size-1 on the wire on 2026-08-01 are stable fixtures and are used
    as such.
#>

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'tools/lib/PfbSpecTools.ps1')
    . (Join-Path $repoRoot 'tools/lib/PfbContextRuleTools.ps1')

    $script:repoRoot = $repoRoot

    # The four fleet-scoped GETs that reference the multi-value component but reject a
    # two-name context with 400 code 15. Upstream defect, still present at fb2.28.
    $script:defectiveFleetScopedGets = @(
        'GET /presets/workload'
        'GET /topology-groups'
        'GET /topology-groups/arrays'
        'GET /topology-groups/members'
    )

    # Synthetic capability map exercising every branch of the documented
    # defaults/overrides resolution contract and every disagreement shape.
    $script:fixtureMap = [PSCustomObject]@{
        parameterComponentDefaults = [PSCustomObject]@{
            context_names = 'Context_names'
            allow_errors  = 'Allow_errors'
        }
        endpoints                  = [PSCustomObject]@{
            # Multi-value component + allow_errors + 207 -> capable, all signals agree.
            'GET /widgets'            = [PSCustomObject]@{
                parameters                  = [PSCustomObject]@{ context_names = '2.26'; allow_errors = '2.26' }
                parameterComponentOverrides = [PSCustomObject]@{ context_names = 'Context_names_get' }
            }
            # Default component (size-1), no allow_errors -> not capable, signals agree.
            'DELETE /widgets'         = [PSCustomObject]@{
                parameters = [PSCustomObject]@{ context_names = '2.26'; ids = '2.0' }
            }
            # The defective shape: multi-value component, no allow_errors. A GET, so the
            # withdrawn verb rule would have called this capable; the ratified rule does not.
            'GET /fleet-scoped'       = [PSCustomObject]@{
                parameters                  = [PSCustomObject]@{ context_names = '2.26' }
                parameterComponentOverrides = [PSCustomObject]@{ context_names = 'Context_names_get' }
            }
            # The mirror: size-1 component that declares allow_errors.
            'PATCH /mirror'           = [PSCustomObject]@{
                parameters = [PSCustomObject]@{ context_names = '2.26'; allow_errors = '2.26' }
            }
            # Capable by the rule, but declares no 207.
            'GET /capable-no-207'     = [PSCustomObject]@{
                parameters                  = [PSCustomObject]@{ context_names = '2.26'; allow_errors = '2.26' }
                parameterComponentOverrides = [PSCustomObject]@{ context_names = 'Context_names_get' }
            }
            # Nothing says it fans out, yet it declares a partial-failure response.
            'GET /size1-with-207'     = [PSCustomObject]@{
                parameters = [PSCustomObject]@{ context_names = '2.26' }
            }
            # Override key PRESENT with a null value == "no component here", which must be
            # honoured over the default rather than silently falling through to it.
            'GET /inline-context'     = [PSCustomObject]@{
                parameters                  = [PSCustomObject]@{ context_names = '2.26' }
                parameterComponentOverrides = [PSCustomObject]@{ context_names = $null }
            }
            # No context_names at all -- must be ignored entirely.
            'GET /unrelated'          = [PSCustomObject]@{
                parameters = [PSCustomObject]@{ ids = '2.0'; allow_errors = '2.26' }
            }
        }
    }

    # 'GET /capable-no-207' is deliberately absent from this set; 'GET /size1-with-207' is
    # deliberately in it despite having no other multi-value signal.
    $script:fixture207 = @('GET /widgets', 'GET /size1-with-207')

    $script:facts = @(Get-PfbContextParameterFact -CapabilityMap $script:fixtureMap -Http207Endpoint $script:fixture207)
    $script:factsNo207 = @(Get-PfbContextParameterFact -CapabilityMap $script:fixtureMap)
}

Describe 'Test-PfbContextMultiValueCapable (the single declared rule)' {
    It 'is capable only when the multi-value component AND allow_errors are both present' {
        Test-PfbContextMultiValueCapable -Method 'GET' -ContextComponent 'Context_names_get' -DeclaresAllowErrors $true |
            Should -BeTrue
    }

    It 'is not capable when the component says multi-value but allow_errors is absent' {
        # The four fleet-scoped GETs. Under the withdrawn verb rule this returned $true.
        Test-PfbContextMultiValueCapable -Method 'GET' -ContextComponent 'Context_names_get' -DeclaresAllowErrors $false |
            Should -BeFalse
    }

    It 'is not capable when allow_errors is present but the component is size-1' {
        Test-PfbContextMultiValueCapable -Method 'PATCH' -ContextComponent 'Context_names' -DeclaresAllowErrors $true |
            Should -BeFalse
    }

    It 'does not let the verb override an evidence-backed verdict' {
        # A mutation verb with both signals present is capable; a GET without them is not.
        Test-PfbContextMultiValueCapable -Method 'DELETE' -ContextComponent 'Context_names_get' -DeclaresAllowErrors $true |
            Should -BeTrue
        Test-PfbContextMultiValueCapable -Method 'GET' -ContextComponent 'Context_names' -DeclaresAllowErrors $false |
            Should -BeFalse
    }

    It 'falls back to the verb only when no component signal exists' -ForEach @(
        @{ Component = $null; Expected = $true }
        @{ Component = ''; Expected = $true }
    ) {
        Test-PfbContextMultiValueCapable -Method 'GET' -ContextComponent $Component -DeclaresAllowErrors $false |
            Should -Be $Expected
    }

    It 'treats <Method> as size-1 in the no-signal fallback' -ForEach @(
        @{ Method = 'POST' }
        @{ Method = 'PUT' }
        @{ Method = 'PATCH' }
        @{ Method = 'DELETE' }
    ) {
        Test-PfbContextMultiValueCapable -Method $Method -ContextComponent $null -DeclaresAllowErrors $true |
            Should -BeFalse
    }

    It 'is case-insensitive in both the component test and the fallback' {
        Test-PfbContextMultiValueCapable -Method 'get' -ContextComponent $null -DeclaresAllowErrors $false | Should -BeTrue
        Test-PfbContextMultiValueCapable -Method 'delete' -ContextComponent 'Context_names_get' -DeclaresAllowErrors $true | Should -BeTrue
    }

    It 'throws rather than assuming a default for a verb it has no verdict for' {
        # Only reachable on the fallback path. A silent $false would quietly assume
        # "size-1" for a verb nobody has reasoned about. (-Method is supplied, so no
        # interactive mandatory-parameter prompt.)
        { Test-PfbContextMultiValueCapable -Method 'TRACE' -ContextComponent $null -DeclaresAllowErrors $false } |
            Should -Throw -ExpectedMessage '*no context-cardinality verdict*'
    }

    It 'does not throw for an unknown verb when a component signal decides it' {
        { Test-PfbContextMultiValueCapable -Method 'TRACE' -ContextComponent 'Context_names' -DeclaresAllowErrors $false } |
            Should -Not -Throw
    }
}

Describe 'Get-PfbContextParameterFact' {
    It 'returns only endpoints declaring context_names' {
        $script:facts.Endpoint | Should -Not -Contain 'GET /unrelated'
    }

    It 'falls back to parameterComponentDefaults when no override is present' {
        $f = $script:facts | Where-Object Endpoint -EQ 'DELETE /widgets'
        $f.ContextComponent | Should -Be 'Context_names'
        $f.ComponentSaysMultiValue | Should -BeFalse
    }

    It 'prefers a per-endpoint override over the default' {
        $f = $script:facts | Where-Object Endpoint -EQ 'GET /widgets'
        $f.ContextComponent | Should -Be 'Context_names_get'
        $f.ComponentSaysMultiValue | Should -BeTrue
    }

    It 'honours an override key present with a null value as "no component"' {
        $f = $script:facts | Where-Object Endpoint -EQ 'GET /inline-context'
        $f.ContextComponent | Should -BeNullOrEmpty
        $f.ComponentSaysMultiValue | Should -BeNullOrEmpty
    }

    It 'splits the endpoint key on the first space only' {
        $f = $script:facts | Where-Object Endpoint -EQ 'PATCH /mirror'
        $f.Method | Should -Be 'PATCH'
        $f.Path | Should -Be '/mirror'
    }

    It 'records the rule verdict from the declared predicate, not from the verb' {
        # A GET with a multi-value component but no allow_errors must NOT be capable.
        ($script:facts | Where-Object Endpoint -EQ 'GET /fleet-scoped').RuleSaysMultiValue | Should -BeFalse
        ($script:facts | Where-Object Endpoint -EQ 'GET /widgets').RuleSaysMultiValue | Should -BeTrue
    }

    It 'carries the 207 signal when supplied' {
        ($script:facts | Where-Object Endpoint -EQ 'GET /widgets').DeclaresHttp207 | Should -BeTrue
        ($script:facts | Where-Object Endpoint -EQ 'GET /capable-no-207').DeclaresHttp207 | Should -BeFalse
    }

    It 'carries 207 as $null (UNKNOWN) when not supplied, never as false' {
        # Unknown must stay distinguishable from "declares no 207" -- scoring unknown as
        # false would invent disagreements that the data does not support.
        foreach ($f in $script:factsNo207) { $f.DeclaresHttp207 | Should -BeNullOrEmpty }
    }

    It 'emits a deterministically sorted collection' {
        @($script:facts.Endpoint) | Should -Be @($script:facts.Endpoint | Sort-Object)
    }
}

Describe 'Get-PfbContextSignalDisagreement' {
    BeforeAll {
        $script:findings = @(Get-PfbContextSignalDisagreement -Fact $script:facts)
        $script:findingsNo207 = @(Get-PfbContextSignalDisagreement -Fact $script:factsNo207)
    }

    It 'reports nothing for an endpoint whose signals all agree' {
        $script:findings.Endpoint | Should -Not -Contain 'GET /widgets'
        $script:findings.Endpoint | Should -Not -Contain 'DELETE /widgets'
    }

    It 'reports a multi-value component that declares no allow_errors' {
        $f = $script:findings | Where-Object Endpoint -EQ 'GET /fleet-scoped'
        $f | Should -Not -BeNullOrEmpty
        $f.Shape | Should -Be 'component-says-multi-value-but-no-allow-errors'
    }

    It 'reports the size-1-component-declaring-allow_errors mirror' {
        ($script:findings | Where-Object Endpoint -EQ 'PATCH /mirror').Shape |
            Should -Be 'size-1-component-but-declares-allow-errors'
    }

    It 'reports an endpoint declaring a 207 while nothing else says it fans out' {
        ($script:findings | Where-Object Endpoint -EQ 'GET /size1-with-207').Shape |
            Should -Be 'size-1-but-declares-207'
    }

    It 'covers every disagreement shape, so none goes untested' {
        @($script:findings.Shape | Sort-Object -Unique) | Should -Be @(
            'component-says-multi-value-but-no-allow-errors'
            'rule-says-capable-but-declares-no-207'
            'size-1-but-declares-207'
            'size-1-component-but-declares-allow-errors'
        )
    }

    It 'reports a rule-capable endpoint that declares no 207' {
        # THE CASE THE OLD TWO-SIGNAL DESIGN COULD NOT SEE: rule and component agree,
        # and the remaining signal dissents.
        $f = $script:findings | Where-Object Endpoint -EQ 'GET /capable-no-207'
        $f | Should -Not -BeNullOrEmpty
        $f.Shape | Should -Be 'rule-says-capable-but-declares-no-207'
        $f.RuleSaysMultiValue | Should -BeTrue
        $f.ComponentSaysMultiValue | Should -BeTrue
    }

    It 'excludes the 207 signal from comparison when it is unknown' {
        # Without 207 data, GET /capable-no-207's remaining signals are unanimous, so it
        # must not be reported -- an unknown signal narrows the check, never invents a
        # finding.
        $script:findingsNo207.Endpoint | Should -Not -Contain 'GET /capable-no-207'
        $script:findingsNo207.Endpoint | Should -Contain 'GET /fleet-scoped'
    }

    It 'records which signals fell on each side' {
        $f = $script:findings | Where-Object Endpoint -EQ 'GET /fleet-scoped'
        @($f.MultiValueSignals) | Should -Be @('component')
        @($f.SizeOneSignals) | Should -Be @('allow_errors', 'http207')
    }

    It 'words the summary neutrally, without prejudging which signal is wrong' {
        $summary = ($script:findings | Where-Object Endpoint -EQ 'GET /fleet-scoped').Summary
        $summary | Should -BeLike '*signals split*'
        $summary | Should -Not -BeLike '*bug*'
        $summary | Should -Not -BeLike '*defect*'
    }

    It 'excludes endpoints whose component could not be resolved' {
        $script:findings.Endpoint | Should -Not -Contain 'GET /inline-context'
    }

    It 'emits a deterministically sorted collection' {
        @($script:findings.Endpoint) | Should -Be @($script:findings.Endpoint | Sort-Object)
    }
}

Describe 'Get-PfbContextSizeOneWithAllowErrors' {
    It 'returns the mirror case only' {
        @(Get-PfbContextSizeOneWithAllowErrors -Fact $script:facts).Endpoint | Should -Be @('PATCH /mirror')
    }

    It 'is a strict subset of the signal disagreements, never an extra finding' {
        $mirror = @(Get-PfbContextSizeOneWithAllowErrors -Fact $script:facts).Endpoint
        $all = @(Get-PfbContextSignalDisagreement -Fact $script:facts).Endpoint
        foreach ($m in $mirror) { $all | Should -Contain $m }
    }
}

Describe 'Get-PfbContextUnresolvedComponent' {
    It 'surfaces endpoints whose context_names has no resolvable component' {
        @(Get-PfbContextUnresolvedComponent -Fact $script:facts).Endpoint | Should -Be @('GET /inline-context')
    }
}

Describe 'Get-PfbContextHttp207Endpoint' {
    It 'finds a declared 207 and normalizes the endpoint key' {
        $spec = [PSCustomObject]@{
            paths = [PSCustomObject]@{
                '/api/2.26/widgets' = [PSCustomObject]@{
                    get    = [PSCustomObject]@{ responses = [PSCustomObject]@{ '200' = @{}; '207' = @{} } }
                    delete = [PSCustomObject]@{ responses = [PSCustomObject]@{ '200' = @{} } }
                }
            }
        }
        @(Get-PfbContextHttp207Endpoint -Spec $spec) | Should -Be @('GET /widgets')
    }

    It 'returns an empty collection for a spec with no paths' {
        @(Get-PfbContextHttp207Endpoint -Spec ([PSCustomObject]@{})).Count | Should -Be 0
    }
}

Describe 'Empty-collection contracts' {
    # PowerShell collapses a bare empty array returned from a function to $null, so these
    # functions follow the repo-wide tools/lib convention: they `return @(...)` and CALL
    # SITES wrap in @(). These tests pin the caller-side contract -- an empty result must
    # be a zero-length collection once wrapped, never a one-element collection containing
    # something. (An earlier attempt to make the functions themselves never return $null,
    # via `return ,$array`, is exactly what breaks that: @() does not flatten a nested
    # array, so every wrapped call site would have silently seen Count 1.)
    BeforeAll {
        $script:emptyMap = [PSCustomObject]@{
            parameterComponentDefaults = [PSCustomObject]@{ context_names = 'Context_names' }
            endpoints                  = [PSCustomObject]@{
                'GET /nothing' = [PSCustomObject]@{ parameters = [PSCustomObject]@{ ids = '2.0' } }
            }
        }
        $script:noFacts = Get-PfbContextParameterFact -CapabilityMap $script:emptyMap
        $script:agreeingFacts = Get-PfbContextParameterFact -CapabilityMap ([PSCustomObject]@{
                parameterComponentDefaults = [PSCustomObject]@{ context_names = 'Context_names' }
                endpoints                  = [PSCustomObject]@{
                    'DELETE /q' = [PSCustomObject]@{ parameters = [PSCustomObject]@{ context_names = '2.26' } }
                }
            })
    }

    It 'Get-PfbContextParameterFact yields zero facts when nothing matches' {
        @($script:noFacts).Count | Should -Be 0
    }

    It 'Get-PfbContextParameterFact yields zero facts for a map with no endpoints' {
        @(Get-PfbContextParameterFact -CapabilityMap ([PSCustomObject]@{ endpoints = $null })).Count |
            Should -Be 0
    }

    It 'Get-PfbContextHttp207Endpoint yields zero endpoints for a spec with no paths' {
        @(Get-PfbContextHttp207Endpoint -Spec ([PSCustomObject]@{})).Count | Should -Be 0
    }

    It '<Function> yields zero findings when there is nothing to report' -ForEach @(
        @{ Function = 'Get-PfbContextSignalDisagreement' }
        @{ Function = 'Get-PfbContextSizeOneWithAllowErrors' }
        @{ Function = 'Get-PfbContextUnresolvedComponent' }
    ) {
        # Count 1 here would mean a nested array leaked through the @() wrap.
        @(& $Function -Fact $script:agreeingFacts).Count | Should -Be 0
    }

    It 'treats an EMPTY 207 set as "checked, none declare it" rather than "unknown"' {
        # The distinction is load-bearing: scoring "none" as "unknown" would silently drop
        # the 207 signal from comparison for a spec that legitimately declares no 207.
        $withEmpty = Get-PfbContextParameterFact -CapabilityMap ([PSCustomObject]@{
                parameterComponentDefaults = [PSCustomObject]@{ context_names = 'Context_names' }
                endpoints                  = [PSCustomObject]@{
                    'GET /w' = [PSCustomObject]@{ parameters = [PSCustomObject]@{ context_names = '2.26' } }
                }
            }) -Http207Endpoint ([string[]]@())
        # Asserted as an explicit null check, not -BeNullOrEmpty: $false IS "empty" to that
        # operator, so it could not tell the two states apart here.
        ($null -eq $withEmpty[0].DeclaresHttp207) | Should -BeFalse -Because 'the spec was checked, so this is false rather than unknown'
        $withEmpty[0].DeclaresHttp207 | Should -BeFalse
    }

    It 'keeps the 207 lookup case-insensitive (the HashSet comparer must survive assignment)' {
        $f = Get-PfbContextParameterFact -CapabilityMap ([PSCustomObject]@{
                parameterComponentDefaults = [PSCustomObject]@{ context_names = 'Context_names' }
                endpoints                  = [PSCustomObject]@{
                    'GET /w' = [PSCustomObject]@{ parameters = [PSCustomObject]@{ context_names = '2.26' } }
                }
            }) -Http207Endpoint @('get /W')
        $f[0].DeclaresHttp207 | Should -BeTrue
    }
}

Describe 'Against real specs' {
    BeforeAll {
        # tools/specs/ is gitignored, so these skip wherever the cache is absent (a fresh
        # clone, or CI without the spec-fetch step) rather than failing.
        $script:spec227Path = Join-Path $script:repoRoot 'tools/specs/fb2.27.json'
        $script:spec228Path = Join-Path $script:repoRoot 'tools/specs/fb2.28.json'
    }

    It 'flags all four fleet-scoped GETs at fb<Version>, where the wire says size-1' -ForEach @(
        @{ Version = '2.27' }
        @{ Version = '2.28' }
    ) -Skip:(-not (Test-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'tools/specs/fb2.28.json'))) {
        # The acceptance criterion for the restructure. Under the withdrawn verb rule these
        # four were invisible: rule said multi-value (GET), component said multi-value, so
        # the old check reported nothing while all four reject a two-name context with
        # 400 code 15. They must appear at BOTH versions -- the upstream fix is still only
        # in review, so a sudden disappearance here means the fix landed, not that the
        # check improved.
        $specPath = Join-Path $script:repoRoot "tools/specs/fb$Version.json"
        $spec = Get-Content -Path $specPath -Raw | ConvertFrom-Json
        $facts = @(Get-PfbContextParameterFact `
                -SpecCapabilities @(Get-PfbSpecCapabilities -Spec $spec) `
                -Http207Endpoint @(Get-PfbContextHttp207Endpoint -Spec $spec))
        $findings = @(Get-PfbContextSignalDisagreement -Fact $facts)

        foreach ($endpoint in $script:defectiveFleetScopedGets) {
            $f = $findings | Where-Object Endpoint -EQ $endpoint
            $f | Should -Not -BeNullOrEmpty -Because "$endpoint is a known size-1 fleet-scoped endpoint referencing the multi-value component"
            $f.Shape | Should -Be 'component-says-multi-value-but-no-allow-errors'
        }
    }

    It 'holds the module rule to size-1 for all four fleet-scoped GETs at fb<Version>' -ForEach @(
        @{ Version = '2.27' }
        @{ Version = '2.28' }
    ) -Skip:(-not (Test-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'tools/specs/fb2.28.json'))) {
        $specPath = Join-Path $script:repoRoot "tools/specs/fb$Version.json"
        $spec = Get-Content -Path $specPath -Raw | ConvertFrom-Json
        $facts = @(Get-PfbContextParameterFact -SpecCapabilities @(Get-PfbSpecCapabilities -Spec $spec))

        foreach ($endpoint in $script:defectiveFleetScopedGets) {
            ($facts | Where-Object Endpoint -EQ $endpoint).RuleSaysMultiValue |
                Should -BeFalse -Because "$endpoint rejects a two-name context on the wire (400 code 15)"
        }
    }

    It 'tracks the 2.28 correction of DELETE /management-access-policies' -Skip:(-not (Test-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'tools/specs/fb2.28.json'))) {
        # Pins a real upstream change: the component flipped to size-1 in 2.28, so the
        # endpoint stops being a component-vs-allow_errors disagreement. Together with the
        # fleet-scoped assertions above this shows the check tracks the spec rather than
        # reporting a constant.
        foreach ($case in @(
                @{ Path = $script:spec227Path; Expected = 'Context_names_get'; ShouldDisagree = $true }
                @{ Path = $script:spec228Path; Expected = 'Context_names'; ShouldDisagree = $false }
            )) {
            if (-not (Test-Path $case.Path)) { continue }
            $spec = Get-Content -Path $case.Path -Raw | ConvertFrom-Json
            $facts = @(Get-PfbContextParameterFact `
                    -SpecCapabilities @(Get-PfbSpecCapabilities -Spec $spec) `
                    -Http207Endpoint @(Get-PfbContextHttp207Endpoint -Spec $spec))
            $target = $facts | Where-Object Endpoint -EQ 'DELETE /management-access-policies'
            $target.ContextComponent | Should -Be $case.Expected
            $target.RuleSaysMultiValue | Should -BeFalse

            $findings = @(Get-PfbContextSignalDisagreement -Fact $facts)
            $hit = @($findings | Where-Object Endpoint -EQ 'DELETE /management-access-policies').Count -gt 0
            $hit | Should -Be $case.ShouldDisagree
        }
    }

    It 'finds no unresolved context_names components in any spec on disk' -Skip:(-not (Test-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'tools/specs/fb2.28.json'))) {
        # context_names does not exist before 2.17, so versions without it contribute zero
        # facts rather than zero-of-many -- both are fine here.
        foreach ($specFile in (Get-ChildItem -Path (Join-Path $script:repoRoot 'tools/specs') -Filter 'fb*.json')) {
            $spec = Get-Content -Path $specFile.FullName -Raw | ConvertFrom-Json
            $facts = @(Get-PfbContextParameterFact -SpecCapabilities @(Get-PfbSpecCapabilities -Spec $spec))
            @(Get-PfbContextUnresolvedComponent -Fact $facts).Count |
                Should -Be 0 -Because "$($specFile.BaseName) should declare no inline context_names"
        }
    }
}

Describe 'Committed capability map' {
    BeforeAll {
        $script:mapFacts = @(Get-PfbContextParameterFact -CapabilityMap (
                Get-Content -Path (Join-Path $script:repoRoot 'Data/PfbCapabilityMap.json') -Raw | ConvertFrom-Json))
    }

    It 'resolves every context_names component (none unresolved)' {
        $script:mapFacts.Count | Should -BeGreaterThan 0
        @(Get-PfbContextUnresolvedComponent -Fact $script:mapFacts).Count | Should -Be 0
    }

    It 'holds the four fleet-scoped GETs to size-1' {
        # Asserted against the map rather than a spec because this is the source the
        # runtime injection path will read. No totals asserted -- the map is regenerated
        # whenever specs are refreshed.
        foreach ($endpoint in $script:defectiveFleetScopedGets) {
            $f = $script:mapFacts | Where-Object Endpoint -EQ $endpoint
            $f | Should -Not -BeNullOrEmpty -Because "$endpoint should be present in the capability map"
            $f.ComponentSaysMultiValue | Should -BeTrue -Because 'the spec defect is still open upstream'
            $f.DeclaresAllowErrors | Should -BeFalse
            $f.RuleSaysMultiValue | Should -BeFalse
        }
    }
}
