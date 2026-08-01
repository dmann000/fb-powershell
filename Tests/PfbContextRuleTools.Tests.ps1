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
#>

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'tools/lib/PfbSpecTools.ps1')
    . (Join-Path $repoRoot 'tools/lib/PfbContextRuleTools.ps1')

    $script:repoRoot = $repoRoot

    # Synthetic capability map exercising every branch of the documented
    # defaults/overrides resolution contract.
    $script:fixtureMap = [PSCustomObject]@{
        parameterComponentDefaults = [PSCustomObject]@{
            context_names = 'Context_names'
            allow_errors  = 'Allow_errors'
        }
        endpoints                  = [PSCustomObject]@{
            # Falls back to the default component (size-1) and agrees with the rule.
            'DELETE /widgets'          = [PSCustomObject]@{
                parameters = [PSCustomObject]@{ context_names = '2.26'; ids = '2.0' }
            }
            # Override to the multi-value component; GET, so rule and spec agree.
            'GET /widgets'             = [PSCustomObject]@{
                parameters                  = [PSCustomObject]@{ context_names = '2.26'; allow_errors = '2.26' }
                parameterComponentOverrides = [PSCustomObject]@{ context_names = 'Context_names_get' }
            }
            # THE disagreement shape: a mutation verb referencing the multi-value
            # component, and (corroboratingly) not declaring allow_errors.
            'DELETE /gadgets'          = [PSCustomObject]@{
                parameters                  = [PSCustomObject]@{ context_names = '2.26' }
                parameterComponentOverrides = [PSCustomObject]@{ context_names = 'Context_names_get' }
            }
            # Agreed multi-value but no allow_errors -- the SEPARATE anomaly.
            'GET /sprockets'           = [PSCustomObject]@{
                parameters                  = [PSCustomObject]@{ context_names = '2.26' }
                parameterComponentOverrides = [PSCustomObject]@{ context_names = 'Context_names_get' }
            }
            # Agreed size-1 but declares allow_errors -- the mirror-image anomaly.
            'PATCH /cogs'              = [PSCustomObject]@{
                parameters = [PSCustomObject]@{ context_names = '2.26'; allow_errors = '2.26' }
            }
            # Override key PRESENT with a null value == "no component here", which must be
            # honoured over the default rather than silently falling through to it.
            'GET /inline-context'      = [PSCustomObject]@{
                parameters                  = [PSCustomObject]@{ context_names = '2.26' }
                parameterComponentOverrides = [PSCustomObject]@{ context_names = $null }
            }
            # No context_names at all -- must be ignored entirely.
            'GET /unrelated'           = [PSCustomObject]@{
                parameters = [PSCustomObject]@{ ids = '2.0'; allow_errors = '2.26' }
            }
        }
    }

    $script:fixtureFacts = @(Get-PfbContextParameterFact -CapabilityMap $script:fixtureMap)
}

Describe 'Test-PfbContextMultiValueCapable (the single declared rule)' {
    It 'treats GET as multi-context-capable' {
        Test-PfbContextMultiValueCapable -Method 'GET' | Should -BeTrue
    }

    It 'treats <Method> as single-context-only' -ForEach @(
        @{ Method = 'POST' }
        @{ Method = 'PUT' }
        @{ Method = 'PATCH' }
        @{ Method = 'DELETE' }
    ) {
        Test-PfbContextMultiValueCapable -Method $Method | Should -BeFalse
    }

    It 'is case-insensitive' {
        Test-PfbContextMultiValueCapable -Method 'get' | Should -BeTrue
        Test-PfbContextMultiValueCapable -Method 'delete' | Should -BeFalse
    }

    It 'throws rather than assuming a default for a verb it has no verdict for' {
        # A silent $false here would quietly assume "size-1" for a verb nobody has
        # reasoned about -- exactly the silent wrongness this rule's verification exists
        # to catch. (-Method is supplied, so no interactive mandatory-parameter prompt.)
        { Test-PfbContextMultiValueCapable -Method 'TRACE' } | Should -Throw -ExpectedMessage '*no context-cardinality verdict*'
    }
}

Describe 'Get-PfbContextParameterFact' {
    It 'returns only endpoints declaring context_names' {
        $script:fixtureFacts.Endpoint | Should -Not -Contain 'GET /unrelated'
        $script:fixtureFacts.Count | Should -Be 6
    }

    It 'falls back to parameterComponentDefaults when no override is present' {
        $fact = $script:fixtureFacts | Where-Object Endpoint -EQ 'DELETE /widgets'
        $fact.ContextComponent | Should -Be 'Context_names'
        $fact.SpecSaysMultiValue | Should -BeFalse
    }

    It 'prefers a per-endpoint override over the default' {
        $fact = $script:fixtureFacts | Where-Object Endpoint -EQ 'GET /widgets'
        $fact.ContextComponent | Should -Be 'Context_names_get'
        $fact.SpecSaysMultiValue | Should -BeTrue
    }

    It 'honours an override key present with a null value as "no component"' {
        $fact = $script:fixtureFacts | Where-Object Endpoint -EQ 'GET /inline-context'
        $fact.ContextComponent | Should -BeNullOrEmpty
        $fact.SpecSaysMultiValue | Should -BeNullOrEmpty
    }

    It 'splits the endpoint key on the first space only' {
        $fact = $script:fixtureFacts | Where-Object Endpoint -EQ 'PATCH /cogs'
        $fact.Method | Should -Be 'PATCH'
        $fact.Path | Should -Be '/cogs'
    }

    It 'records the module rule verdict from the declared predicate' {
        ($script:fixtureFacts | Where-Object Endpoint -EQ 'GET /widgets').RuleSaysMultiValue | Should -BeTrue
        ($script:fixtureFacts | Where-Object Endpoint -EQ 'DELETE /gadgets').RuleSaysMultiValue | Should -BeFalse
    }

    It 'emits a deterministically sorted collection' {
        $sorted = @($script:fixtureFacts.Endpoint | Sort-Object)
        @($script:fixtureFacts.Endpoint) | Should -Be $sorted
    }
}

Describe 'Get-PfbContextVerbRuleDisagreement' {
    BeforeAll {
        $script:fixtureDisagreements = @(Get-PfbContextVerbRuleDisagreement -Fact $script:fixtureFacts)
    }

    It 'reports exactly the endpoint where the rule and the component identity differ' {
        $script:fixtureDisagreements.Count | Should -Be 1
        $script:fixtureDisagreements[0].Endpoint | Should -Be 'DELETE /gadgets'
    }

    It 'carries the referenced component, both verdicts, and the allow_errors signal' {
        $d = $script:fixtureDisagreements[0]
        $d.ContextComponent | Should -Be 'Context_names_get'
        $d.RuleSaysMultiValue | Should -BeFalse
        $d.SpecSaysMultiValue | Should -BeTrue
        $d.DeclaresAllowErrors | Should -BeFalse
    }

    It 'words the summary neutrally, without prejudging which side is wrong' {
        $summary = $script:fixtureDisagreements[0].Summary
        $summary | Should -BeLike '*module rule says*'
        $summary | Should -BeLike '*spec references*'
        # A future disagreement may be a real API change rather than a spec defect.
        $summary | Should -Not -BeLike '*bug*'
        $summary | Should -Not -BeLike '*wrong*'
    }

    It 'excludes endpoints whose component could not be resolved rather than scoring them size-1' {
        # GET /inline-context has no component. Scored as size-1 it would look like a
        # disagreement against the GET rule; it must simply not be compared.
        $script:fixtureDisagreements.Endpoint | Should -Not -Contain 'GET /inline-context'
    }

    It 'returns an empty collection when every endpoint agrees' {
        $agreeing = @($script:fixtureFacts | Where-Object { $_.Endpoint -ne 'DELETE /gadgets' })
        @(Get-PfbContextVerbRuleDisagreement -Fact $agreeing).Count | Should -Be 0
    }
}

Describe 'Get-PfbContextAllowErrorsAnomaly' {
    BeforeAll {
        $script:fixtureAnomalies = Get-PfbContextAllowErrorsAnomaly -Fact $script:fixtureFacts
    }

    It 'reports agreed multi-value endpoints that do not declare allow_errors' {
        @($script:fixtureAnomalies.MultiValueWithoutAllowErrors).Endpoint | Should -Be @('GET /sprockets')
    }

    It 'reports the mirror image: agreed size-1 endpoints that do declare allow_errors' {
        @($script:fixtureAnomalies.SingleValueWithAllowErrors).Endpoint | Should -Be @('PATCH /cogs')
    }

    It 'never double-counts a cardinality disagreement as an allow_errors anomaly' {
        # DELETE /gadgets is spec-multi-value AND lacks allow_errors, so a naive
        # spec-only filter would list it here too -- inflating one defect into two
        # findings. It belongs to the disagreement category alone.
        @($script:fixtureAnomalies.MultiValueWithoutAllowErrors).Endpoint | Should -Not -Contain 'DELETE /gadgets'
    }

    It 'emits deterministically sorted collections' {
        $multi = @($script:fixtureAnomalies.MultiValueWithoutAllowErrors.Endpoint)
        $multi | Should -Be @($multi | Sort-Object)
    }
}

Describe 'Get-PfbContextUnresolvedComponent' {
    It 'surfaces endpoints whose context_names has no resolvable component' {
        @(Get-PfbContextUnresolvedComponent -Fact $script:fixtureFacts).Endpoint |
            Should -Be @('GET /inline-context')
    }
}

Describe 'Non-vacuity against real specs' {
    BeforeAll {
        # tools/specs/ is gitignored, so these are skipped wherever the cache is absent
        # (a fresh clone, or CI without the spec-fetch step) rather than failing.
        $script:spec227Path = Join-Path $script:repoRoot 'tools/specs/fb2.27.json'
        $script:spec228Path = Join-Path $script:repoRoot 'tools/specs/fb2.28.json'
        $script:haveSpecs = (Test-Path $script:spec227Path) -and (Test-Path $script:spec228Path)
    }

    It 'finds exactly one disagreement in fb2.27: DELETE /management-access-policies' -Skip:(-not (Test-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'tools/specs/fb2.27.json'))) {
        # This is the proof the check is not vacuous. fb2.27 contains a KNOWN, confirmed
        # upstream spec defect -- a multi-value component on a DELETE -- and the check
        # must rediscover it mechanically, with no prior knowledge encoded anywhere.
        $spec = Get-Content -Path $script:spec227Path -Raw | ConvertFrom-Json
        $facts = @(Get-PfbContextParameterFact -SpecCapabilities @(Get-PfbSpecCapabilities -Spec $spec))
        $disagreements = @(Get-PfbContextVerbRuleDisagreement -Fact $facts)

        $disagreements.Count | Should -Be 1
        $disagreements[0].Endpoint | Should -Be 'DELETE /management-access-policies'
        $disagreements[0].ContextComponent | Should -Be 'Context_names_get'
        $disagreements[0].DeclaresAllowErrors | Should -BeFalse
    }

    It 'finds no disagreement in fb2.28, where the defect was fixed upstream' -Skip:(-not (Test-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'tools/specs/fb2.28.json'))) {
        # Pins the observed upstream fix: the same endpoint's reference changed to
        # Context_names. Together with the fb2.27 case above, this proves the check
        # tracks the spec rather than reporting a constant.
        $spec = Get-Content -Path $script:spec228Path -Raw | ConvertFrom-Json
        $facts = @(Get-PfbContextParameterFact -SpecCapabilities @(Get-PfbSpecCapabilities -Spec $spec))

        @(Get-PfbContextVerbRuleDisagreement -Fact $facts).Count | Should -Be 0
        ($facts | Where-Object Endpoint -EQ 'DELETE /management-access-policies').ContextComponent |
            Should -Be 'Context_names'
    }

    It 'keeps the four multi-value GETs without allow_errors separate in fb2.27' -Skip:(-not (Test-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'tools/specs/fb2.27.json'))) {
        $spec = Get-Content -Path $script:spec227Path -Raw | ConvertFrom-Json
        $facts = @(Get-PfbContextParameterFact -SpecCapabilities @(Get-PfbSpecCapabilities -Spec $spec))
        $anomalies = Get-PfbContextAllowErrorsAnomaly -Fact $facts

        @($anomalies.MultiValueWithoutAllowErrors).Endpoint | Should -Be @(
            'GET /presets/workload'
            'GET /topology-groups'
            'GET /topology-groups/arrays'
            'GET /topology-groups/members'
        )
        # The fb2.27 spec defect is a cardinality disagreement, not an allow_errors
        # anomaly, even though it also lacks allow_errors.
        @($anomalies.MultiValueWithoutAllowErrors).Endpoint |
            Should -Not -Contain 'DELETE /management-access-policies'
        @($anomalies.SingleValueWithAllowErrors).Endpoint | Should -Be @('PATCH /directory-services/test')
    }
}

Describe 'Committed capability map' {
    It 'resolves every context_names component (none unresolved)' {
        $mapPath = Join-Path $script:repoRoot 'Data/PfbCapabilityMap.json'
        $map = Get-Content -Path $mapPath -Raw | ConvertFrom-Json
        $facts = @(Get-PfbContextParameterFact -CapabilityMap $map)

        $facts.Count | Should -BeGreaterThan 0
        @(Get-PfbContextUnresolvedComponent -Fact $facts).Count | Should -Be 0
    }
}
