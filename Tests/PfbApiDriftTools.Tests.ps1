#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Unit tests for tools/lib/PfbApiDriftTools.ps1 -- category 1 (uncovered endpoints) and
    category 2 (parameter gaps) of the API drift report.
#>

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'tools/lib/PfbApiDriftTools.ps1')

    $script:publicFixtureDir = Join-Path $TestDrive 'Public/Fixture'
    $script:privateFixtureDir = Join-Path $TestDrive 'Private'
    New-Item -ItemType Directory -Path $publicFixtureDir -Force | Out-Null
    New-Item -ItemType Directory -Path $privateFixtureDir -Force | Out-Null

    Set-Content -Path (Join-Path $publicFixtureDir 'Get-PfbFixtureWidget.ps1') -Value @'
function Get-PfbFixtureWidget {
    [CmdletBinding()]
    param([Parameter()] [PSCustomObject]$Array, [Parameter()] [string]$Name)
    $queryParams = @{}
    if ($Name) { $queryParams['name'] = $Name }
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'widgets' -QueryParams $queryParams -AutoPaginate
}
'@

    Set-Content -Path (Join-Path $publicFixtureDir 'Get-PfbFixtureDynamic.ps1') -Value @'
function Get-PfbFixtureDynamic {
    [CmdletBinding()]
    param([Parameter()] [PSCustomObject]$Array, [Parameter()] [string]$Kind)
    $endpoint = "widgets/$Kind"
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint $endpoint -AutoPaginate
}
'@

    # A Private/ helper that also happens to use the standard Invoke-PfbApiRequest
    # convention -- Get-PfbModuleCalledEndpoints must scan Private/ too, not just Public/.
    Set-Content -Path (Join-Path $privateFixtureDir 'Invoke-PfbFixtureInternalHelper.ps1') -Value @'
function Invoke-PfbFixtureInternalHelper {
    [CmdletBinding()]
    param([Parameter()] [PSCustomObject]$Array)
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'internal-only' -AutoPaginate
}
'@

    $script:calledEndpoints = Get-PfbModuleCalledEndpoints -PublicDirectory $publicFixtureDir -PrivateDirectory $privateFixtureDir

    $script:capabilityMap = [PSCustomObject]@{
        endpoints = [PSCustomObject]@{
            'GET /widgets'        = [PSCustomObject]@{ minVersion = '2.0' }
            'GET /internal-only'  = [PSCustomObject]@{ minVersion = '2.0' }
            'GET /gadgets'        = [PSCustomObject]@{ minVersion = '2.20' }
            'POST /api/login'    = [PSCustomObject]@{ minVersion = '2.26' }
        }
    }

    $script:capabilityMap.endpoints | Add-Member -NotePropertyName 'GET /arrays/space' -NotePropertyValue ([PSCustomObject]@{
        minVersion     = '2.0'
        parameters     = [PSCustomObject]@{ type = '2.0'; new_field = '2.27'; 'X-Request-ID' = '2.12' }
        bodyProperties = [PSCustomObject]@{}
    })

    $script:fullyMappedInventory = @(
        [PSCustomObject]@{ Cmdlet = 'Get-PfbFixtureArraySpace'; Parameter = 'Type'; Surface = 'Typed'; WireName = 'type'; HasValidateSet = $false; ValidateSetValues = $null; Endpoint = 'arrays/space'; Method = 'GET'; File = 'Public/Fixture/Get-PfbFixtureArraySpace.ps1'; Line = 5 }
    )
    # A non-empty inventory containing only an UNRELATED cmdlet -- for tests that need to
    # exercise "this endpoint's cmdlet has no inventory rows at all" without passing a
    # literally empty array. Group-Object -AsHashTable returns $null for a whole-hashtable
    # MISS on an empty input array (not merely for one absent key on an otherwise-populated
    # one), and indexing into that null hashtable is itself a non-terminating error --
    # noisy in test output even though functionally harmless. A single unrelated row keeps
    # the hashtable itself real, so a miss on the cmdlet actually under test stays a clean,
    # silent $null (the "vacuous mapping" case Get-PfbParameterCoverageGaps is built to
    # tolerate), not a null-hashtable index error.
    $script:noopInventory = @(
        [PSCustomObject]@{ Cmdlet = 'Get-PfbFixtureUnrelated'; Parameter = 'Unused'; Surface = 'Typed'; WireName = 'unused'; HasValidateSet = $false; ValidateSetValues = $null; Endpoint = $null; Method = $null; File = 'x'; Line = 1 }
    )
    $script:notFullyMappedInventory = @(
        [PSCustomObject]@{ Cmdlet = 'Get-PfbFixtureWidget'; Parameter = 'Name'; Surface = 'Typed'; WireName = 'name'; HasValidateSet = $false; ValidateSetValues = $null; Endpoint = 'widgets'; Method = 'GET'; File = 'Public/Fixture/Get-PfbFixtureWidget.ps1'; Line = 3 }
        [PSCustomObject]@{ Cmdlet = 'Get-PfbFixtureWidget'; Parameter = 'Attributes'; Surface = 'AttributesOnly'; WireName = $null; HasValidateSet = $false; ValidateSetValues = $null; Endpoint = $null; Method = $null; File = 'Public/Fixture/Get-PfbFixtureWidget.ps1'; Line = 4 }
    )

    $script:driftHistory = [ordered]@{
        'ArrayPerformance.protocol' = [ordered]@{
            Name = 'protocol'; Kind = 'schema'; MinVersion = '2.0'
            CurrentValues = @('all', 'nfs', 'smb', 'http', 's3')
            DistinctValueSets = [System.Collections.Generic.HashSet[string]]::new([string[]]@('all,http,nfs,s3,smb'))
        }
    }
    $script:driftInventory = @(
        [PSCustomObject]@{ Cmdlet = 'Get-PfbArrayPerformance'; Parameter = 'Protocol'; Surface = 'Typed'; WireName = 'protocol'; HasValidateSet = $true; ValidateSetValues = @('nfs', 'smb', 'http', 's3'); Endpoint = 'arrays/performance'; Method = 'GET' }
    )

    # Hoisted to file scope (not a per-Describe BeforeAll) because it is consumed by TWO
    # separate Describe blocks below (the array-item-type/synopsis tests and the
    # Get-PfbBodyPropertyEnrichment tests) -- a Describe-local BeforeAll only runs before
    # its OWN Describe's tests, so the other Describe block would see a $null
    # $enrichmentSpec whenever it runs without the first Describe having already executed
    # in the same session (e.g. `-Filter.FullName` isolating just one Describe).
    $script:enrichmentSpec = [PSCustomObject]@{
        components = [PSCustomObject]@{
            schemas = [PSCustomObject]@{
                Widget     = [PSCustomObject]@{
                    type       = 'object'
                    properties = [PSCustomObject]@{
                        color    = [PSCustomObject]@{ type = 'string'; description = 'The widget color. Valid values are `red`, `blue`, and `green`.' }
                        count    = [PSCustomObject]@{ type = 'integer'; format = 'int64'; description = "Count of widgets available`nin this pool. Additional prose about counting follows here." }
                        tags     = [PSCustomObject]@{ type = 'array'; items = [PSCustomObject]@{ type = 'string' }; description = 'Tag list. Additional prose about tags follows this first sentence.' }
                        ref_tags = [PSCustomObject]@{ type = 'array'; items = [PSCustomObject]@{ '$ref' = '#/components/schemas/_tagRef' } }
                        linked   = [PSCustomObject]@{ '$ref' = '#/components/schemas/_linkedRef' }
                        bare     = [PSCustomObject]@{ type = 'string' }
                    }
                }
                _linkedRef = [PSCustomObject]@{ type = 'string'; description = 'Should never be read directly off Widget.linked (PIN: this function reads only the OWNER schema''s own declared property node, never following the property''s own $ref).' }
            }
        }
    }
}

Describe 'Get-PfbModuleCalledEndpoints' {
    It 'resolves a literal -Method/-Endpoint pair to the capability-map key format' {
        $rec = $calledEndpoints | Where-Object { $_.Cmdlet -eq 'Get-PfbFixtureWidget' }
        $rec.Key | Should -Be 'GET /widgets'
        $rec.Resolved | Should -BeTrue
    }

    It 'scans Private/*.ps1 as well as Public/*.ps1' {
        $rec = $calledEndpoints | Where-Object { $_.Cmdlet -eq 'Invoke-PfbFixtureInternalHelper' }
        $rec.Key | Should -Be 'GET /internal-only'
    }

    It 'marks a dynamically-built -Endpoint as unresolved, never silently dropped or guessed' {
        $rec = $calledEndpoints | Where-Object { $_.Cmdlet -eq 'Get-PfbFixtureDynamic' }
        $rec.Resolved | Should -BeFalse
        $rec.Key | Should -BeNullOrEmpty
    }
}

Describe 'Get-PfbEndpointCoverageGaps' {
    It 'flags a capability-map endpoint no cmdlet calls at all' {
        $gaps = Get-PfbEndpointCoverageGaps -CapabilityMap $capabilityMap -CalledEndpoints $calledEndpoints
        ($gaps | Where-Object { $_.Endpoint -eq 'GET /gadgets' }) | Should -Not -BeNullOrEmpty
    }

    It 'does not flag an endpoint a fixture cmdlet already calls' {
        $gaps = Get-PfbEndpointCoverageGaps -CapabilityMap $capabilityMap -CalledEndpoints $calledEndpoints
        ($gaps | Where-Object { $_.Endpoint -eq 'GET /widgets' }) | Should -BeNullOrEmpty
    }

    It 'excludes a bespoke-allowlisted endpoint even though no cmdlet calls it directly' {
        $gaps = Get-PfbEndpointCoverageGaps -CapabilityMap $capabilityMap -CalledEndpoints $calledEndpoints -BespokeAllowlist @('POST /api/login')
        ($gaps | Where-Object { $_.Endpoint -eq 'POST /api/login' }) | Should -BeNullOrEmpty
    }

    It 'with -SinceVersion, excludes a gap endpoint introduced at or before that version' {
        $gaps = Get-PfbEndpointCoverageGaps -CapabilityMap $capabilityMap -CalledEndpoints $calledEndpoints -SinceVersion '2.20'
        ($gaps | Where-Object { $_.Endpoint -eq 'GET /gadgets' }) | Should -BeNullOrEmpty
    }

    It 'with -SinceVersion, keeps a gap endpoint introduced after that version' {
        $gaps = Get-PfbEndpointCoverageGaps -CapabilityMap $capabilityMap -CalledEndpoints $calledEndpoints -SinceVersion '2.20'
        ($gaps | Where-Object { $_.Endpoint -eq 'POST /api/login' }) | Should -Not -BeNullOrEmpty
    }
}

Describe 'Bespoke auth-endpoint allowlist (real, confirmed by reading Private/ + Connect-PfbArray.ps1)' {
    It 'contains exactly the four confirmed bespoke endpoints, no more, no fewer' {
        $script:PfbBespokeAuthEndpoints | Sort-Object | Should -Be @(
            'GET /api/api_version',
            'POST /api/login',
            'POST /api/logout',
            'POST /oauth2/1.0/token'
        ) | Sort-Object
    }
}

Describe 'Non-actionable parameter allowlist (X-Request-ID/offset: no Private/ injection site exists for either -- confirmed hand-written; continuation_token is DERIVED now, see Get-PfbNonActionableParameters)' {
    It 'contains exactly the two hand-written fields, no more, no fewer -- continuation_token is no longer hardcoded here' {
        $script:PfbNonActionableParameters | Sort-Object | Should -Be @(
            'offset',
            'X-Request-ID'
        ) | Sort-Object
    }
}

Describe 'Get-PfbParameterCoverageGaps' {
    It 'flags a missing query parameter on a fully-mapped cmdlet''s endpoint, with high confidence' {
        $endpoints = @([PSCustomObject]@{ Key = 'GET /arrays/space'; Method = 'GET'; Endpoint = '/arrays/space'; Resolved = $true; Cmdlet = 'Get-PfbFixtureArraySpace'; File = 'x' })
        $result = Get-PfbParameterCoverageGaps -CapabilityMap $capabilityMap -CmdletInventory $fullyMappedInventory -CalledEndpoints $endpoints
        $gap = $result | Where-Object { $_.Endpoint -eq 'GET /arrays/space' }
        $gap.MissingQueryParameters | Should -Contain 'new_field'
        $gap.MissingBodyProperties | Should -BeNullOrEmpty
        $gap.ReadOnlyFields | Should -BeNullOrEmpty
        $gap.Confidence.Level | Should -Be 'high'
        $gap.Confidence.UnresolvedParameters | Should -BeNullOrEmpty
        $gap.Confidence.EscapeHatchOnly | Should -BeNullOrEmpty
        $gap.Confidence.Caveat | Should -BeNullOrEmpty
    }

    It 'never gates an endpoint out entirely for an AttributesOnly parameter -- still reports its resolved gaps, with partial confidence and an escape-hatch annotation' {
        $endpoints = @([PSCustomObject]@{ Key = 'GET /widgets'; Method = 'GET'; Endpoint = '/widgets'; Resolved = $true; Cmdlet = 'Get-PfbFixtureWidget'; File = 'x' })
        $capMapWithWidgets = [PSCustomObject]@{ endpoints = [PSCustomObject]@{ 'GET /widgets' = [PSCustomObject]@{ minVersion = '2.0'; parameters = [PSCustomObject]@{ name = '2.0'; kind = '2.0' }; bodyProperties = [PSCustomObject]@{} } } }
        $result = Get-PfbParameterCoverageGaps -CapabilityMap $capMapWithWidgets -CmdletInventory $notFullyMappedInventory -CalledEndpoints $endpoints
        $gap = $result | Where-Object { $_.Endpoint -eq 'GET /widgets' }
        $gap | Should -Not -BeNullOrEmpty
        $gap.MissingQueryParameters | Should -Be @('kind')
        $gap.Confidence.Level | Should -Be 'partial'
        $gap.Confidence.UnresolvedParameters.Parameter | Should -Contain 'Attributes'
        ($gap.Confidence.UnresolvedParameters | Where-Object Parameter -eq 'Attributes').Surface | Should -Be 'AttributesOnly'
        ($gap.Confidence.UnresolvedParameters | Where-Object Parameter -eq 'Attributes').Line | Should -Be 4
        $gap.Confidence.EscapeHatchOnly | Should -Be @('Attributes')
        $gap.Confidence.Caveat | Should -Not -BeNullOrEmpty
    }

    It 'with -SinceVersion, keeps a missing query parameter introduced after that version' {
        $endpoints = @([PSCustomObject]@{ Key = 'GET /arrays/space'; Method = 'GET'; Endpoint = '/arrays/space'; Resolved = $true; Cmdlet = 'Get-PfbFixtureArraySpace'; File = 'x' })
        $result = Get-PfbParameterCoverageGaps -CapabilityMap $capabilityMap -CmdletInventory $fullyMappedInventory -CalledEndpoints $endpoints -SinceVersion '2.0'
        $gap = $result | Where-Object { $_.Endpoint -eq 'GET /arrays/space' }
        $gap.MissingQueryParameters | Should -Contain 'new_field'
    }

    It 'with -SinceVersion, drops a gap whose only missing field was introduced at or before that version' {
        $endpoints = @([PSCustomObject]@{ Key = 'GET /arrays/space'; Method = 'GET'; Endpoint = '/arrays/space'; Resolved = $true; Cmdlet = 'Get-PfbFixtureArraySpace'; File = 'x' })
        $result = Get-PfbParameterCoverageGaps -CapabilityMap $capabilityMap -CmdletInventory $fullyMappedInventory -CalledEndpoints $endpoints -SinceVersion '2.27'
        $result | Where-Object { $_.Endpoint -eq 'GET /arrays/space' } | Should -BeNullOrEmpty
    }

    It 'flags X-Request-ID as a missing query parameter when -ExcludedFields is not given' {
        $endpoints = @([PSCustomObject]@{ Key = 'GET /arrays/space'; Method = 'GET'; Endpoint = '/arrays/space'; Resolved = $true; Cmdlet = 'Get-PfbFixtureArraySpace'; File = 'x' })
        $result = Get-PfbParameterCoverageGaps -CapabilityMap $capabilityMap -CmdletInventory $fullyMappedInventory -CalledEndpoints $endpoints
        $gap = $result | Where-Object { $_.Endpoint -eq 'GET /arrays/space' }
        $gap.MissingQueryParameters | Should -Contain 'X-Request-ID'
    }

    It 'with -ExcludedFields, excludes a named field but keeps other real gaps on the same endpoint' {
        $endpoints = @([PSCustomObject]@{ Key = 'GET /arrays/space'; Method = 'GET'; Endpoint = '/arrays/space'; Resolved = $true; Cmdlet = 'Get-PfbFixtureArraySpace'; File = 'x' })
        $result = Get-PfbParameterCoverageGaps -CapabilityMap $capabilityMap -CmdletInventory $fullyMappedInventory -CalledEndpoints $endpoints -ExcludedFields @('X-Request-ID')
        $gap = $result | Where-Object { $_.Endpoint -eq 'GET /arrays/space' }
        $gap.MissingQueryParameters | Should -Not -Contain 'X-Request-ID'
        $gap.MissingQueryParameters | Should -Contain 'new_field'
    }

    It 'with -ExcludedFields, excludes a named BODY field too -- the filter is not query-only' {
        $endpoints = @([PSCustomObject]@{ Key = 'PATCH /excl'; Method = 'PATCH'; Endpoint = '/excl'; Resolved = $true; Cmdlet = 'Update-PfbFixtureExcl'; File = 'x' })
        $capMap = [PSCustomObject]@{ endpoints = [PSCustomObject]@{ 'PATCH /excl' = [PSCustomObject]@{ minVersion = '2.0'; parameters = [PSCustomObject]@{}; bodyProperties = [PSCustomObject]@{ banner = '2.0'; internal_only = '2.0' } } } }
        $result = Get-PfbParameterCoverageGaps -CapabilityMap $capMap -CmdletInventory $noopInventory -CalledEndpoints $endpoints -ExcludedFields @('internal_only')
        $gap = $result | Where-Object { $_.Endpoint -eq 'PATCH /excl' }
        $gap.MissingBodyProperties | Should -Be @('banner')
        $gap.MissingBodyProperties | Should -Not -Contain 'internal_only'
    }

    It 'with -ExcludedFields, drops a gap entirely when every missing field is excluded' {
        $endpoints = @([PSCustomObject]@{ Key = 'GET /widgets'; Method = 'GET'; Endpoint = '/widgets'; Resolved = $true; Cmdlet = 'Get-PfbFixtureWidget'; File = 'x' })
        $capMapOnlyXRid = [PSCustomObject]@{ endpoints = [PSCustomObject]@{ 'GET /widgets' = [PSCustomObject]@{ minVersion = '2.0'; parameters = [PSCustomObject]@{ 'X-Request-ID' = '2.12' }; bodyProperties = [PSCustomObject]@{} } } }
        $inventory = @([PSCustomObject]@{ Cmdlet = 'Get-PfbFixtureWidget'; Parameter = 'Name'; Surface = 'Typed'; WireName = 'name'; HasValidateSet = $false; ValidateSetValues = $null; Endpoint = 'widgets'; Method = 'GET' })
        $result = Get-PfbParameterCoverageGaps -CapabilityMap $capMapOnlyXRid -CmdletInventory $inventory -CalledEndpoints $endpoints -ExcludedFields @('X-Request-ID')
        $result | Where-Object { $_.Endpoint -eq 'GET /widgets' } | Should -BeNullOrEmpty
    }

    It 'returns MissingQueryParameters in deterministic alphabetical order regardless of capability-map field order' {
        # Field names deliberately declared in reverse/scrambled order below -- the field-name
        # collections are staged through a Dictionary[string,string] whose insertion order
        # traces back to JSON property order, which is not a documented contract for
        # PSCustomObject.PSObject.Properties enumeration, so without an explicit sort this
        # list's order is not guaranteed to be stable (confirmed live in an earlier version of
        # this function, staged through a plain Hashtable instead: regenerating
        # Reports/PfbApiDriftReport.md twice produced two byte-different files for the exact
        # same drift content). The fix must sort regardless of insertion order, so this test
        # deliberately supplies fields already out of alphabetical order.
        $capMapScrambled = [PSCustomObject]@{
            endpoints = [PSCustomObject]@{
                'GET /widgets' = [PSCustomObject]@{
                    minVersion = '2.0'
                    parameters = [PSCustomObject]@{ zebra = '2.0'; apple = '2.0'; mango = '2.0' }
                    bodyProperties = [PSCustomObject]@{}
                }
            }
        }
        $endpoints = @([PSCustomObject]@{ Key = 'GET /widgets'; Method = 'GET'; Endpoint = '/widgets'; Resolved = $true; Cmdlet = 'Get-PfbFixtureWidget'; File = 'x' })
        $inventory = @([PSCustomObject]@{ Cmdlet = 'Get-PfbFixtureWidget'; Parameter = 'Name'; Surface = 'Typed'; WireName = 'name'; HasValidateSet = $false; ValidateSetValues = $null; Endpoint = 'widgets'; Method = 'GET' })
        $result = Get-PfbParameterCoverageGaps -CapabilityMap $capMapScrambled -CmdletInventory $inventory -CalledEndpoints $endpoints
        $gap = $result | Where-Object { $_.Endpoint -eq 'GET /widgets' }
        $gap.MissingQueryParameters | Should -Be @('apple', 'mango', 'zebra')
    }

    It 'returns MissingBodyProperties and ReadOnlyFields in deterministic alphabetical order too' {
        $capMapScrambled = [PSCustomObject]@{
            endpoints = [PSCustomObject]@{
                'PATCH /widgets' = [PSCustomObject]@{
                    minVersion = '2.0'
                    parameters = [PSCustomObject]@{}
                    bodyProperties = [PSCustomObject]@{ zebra = '2.0'; apple = '2.0'; mango = '2.0'; yak = '2.0'; banana = '2.0' }
                    readOnlyBodyProperties = @('zebra', 'yak')
                }
            }
        }
        $endpoints = @([PSCustomObject]@{ Key = 'PATCH /widgets'; Method = 'PATCH'; Endpoint = '/widgets'; Resolved = $true; Cmdlet = 'Update-PfbFixtureWidget'; File = 'x' })
        $result = Get-PfbParameterCoverageGaps -CapabilityMap $capMapScrambled -CmdletInventory $noopInventory -CalledEndpoints $endpoints
        $gap = $result | Where-Object { $_.Endpoint -eq 'PATCH /widgets' }
        $gap.MissingBodyProperties | Should -Be @('apple', 'banana', 'mango')
        $gap.ReadOnlyFields | Should -Be @('yak', 'zebra')
    }

    Context 'body fields read-only in the newest analysed spec are split into ReadOnlyFields, never MissingBodyProperties' {
        BeforeAll {
            $script:roCapMap = [PSCustomObject]@{
                endpoints = [PSCustomObject]@{
                    'PATCH /ro-fixture' = [PSCustomObject]@{
                        minVersion             = '2.0'
                        parameters              = [PSCustomObject]@{}
                        bodyProperties          = [PSCustomObject]@{ name = '2.0'; owner = '2.0' }
                        readOnlyBodyProperties  = @('owner')
                    }
                }
            }
            $script:roEndpoints = @([PSCustomObject]@{ Key = 'PATCH /ro-fixture'; Method = 'PATCH'; Endpoint = '/ro-fixture'; Resolved = $true; Cmdlet = 'Update-PfbFixtureRo'; File = 'x' })
        }

        It 'puts the addable field in MissingBodyProperties and the read-only one in ReadOnlyFields, never both' {
            $result = Get-PfbParameterCoverageGaps -CapabilityMap $roCapMap -CmdletInventory $noopInventory -CalledEndpoints $roEndpoints
            $gap = $result | Where-Object { $_.Endpoint -eq 'PATCH /ro-fixture' }
            $gap.MissingBodyProperties | Should -Be @('name')
            $gap.ReadOnlyFields | Should -Be @('owner')
            $gap.MissingBodyProperties | Should -Not -Contain 'owner'
            $gap.ReadOnlyFields | Should -Not -Contain 'name'
        }

        It 'still emits the endpoint when the only gap is a read-only field (an endpoint is emitted if ANY list is non-empty)' {
            $roOnlyCapMap = [PSCustomObject]@{
                endpoints = [PSCustomObject]@{
                    'PATCH /ro-fixture' = [PSCustomObject]@{
                        minVersion             = '2.0'
                        parameters              = [PSCustomObject]@{}
                        bodyProperties          = [PSCustomObject]@{ owner = '2.0' }
                        readOnlyBodyProperties  = @('owner')
                    }
                }
            }
            $result = Get-PfbParameterCoverageGaps -CapabilityMap $roOnlyCapMap -CmdletInventory $noopInventory -CalledEndpoints $roEndpoints
            $gap = $result | Where-Object { $_.Endpoint -eq 'PATCH /ro-fixture' }
            $gap | Should -Not -BeNullOrEmpty
            $gap.MissingBodyProperties | Should -BeNullOrEmpty
            $gap.ReadOnlyFields | Should -Be @('owner')
        }
    }

    Context '-SinceVersion on the BODY/read-only side ($bodyFieldVersions is separate code from the query-side $queryFieldVersions lookup -- mirrors the query-side -SinceVersion tests above)' {
        BeforeAll {
            $script:bodySinceCapMap = [PSCustomObject]@{
                endpoints = [PSCustomObject]@{
                    'PATCH /since-fixture' = [PSCustomObject]@{
                        minVersion             = '2.0'
                        parameters             = [PSCustomObject]@{}
                        bodyProperties         = [PSCustomObject]@{ old_field = '2.0'; new_body_field = '2.27'; new_ro_field = '2.27' }
                        readOnlyBodyProperties = @('new_ro_field')
                    }
                }
            }
            $script:bodySinceEndpoints = @([PSCustomObject]@{ Key = 'PATCH /since-fixture'; Method = 'PATCH'; Endpoint = '/since-fixture'; Resolved = $true; Cmdlet = 'Update-PfbFixtureSince'; File = 'x' })
        }

        It 'with -SinceVersion, keeps a missing body property AND a read-only field introduced after that version' {
            $result = Get-PfbParameterCoverageGaps -CapabilityMap $bodySinceCapMap -CmdletInventory $noopInventory -CalledEndpoints $bodySinceEndpoints -SinceVersion '2.0'
            $gap = $result | Where-Object { $_.Endpoint -eq 'PATCH /since-fixture' }
            $gap.MissingBodyProperties | Should -Contain 'new_body_field'
            $gap.ReadOnlyFields | Should -Contain 'new_ro_field'
        }

        It 'with -SinceVersion, drops a gap whose only missing body/read-only fields were introduced at or before that version' {
            $result = Get-PfbParameterCoverageGaps -CapabilityMap $bodySinceCapMap -CmdletInventory $noopInventory -CalledEndpoints $bodySinceEndpoints -SinceVersion '2.27'
            $gap = $result | Where-Object { $_.Endpoint -eq 'PATCH /since-fixture' }
            $gap.MissingBodyProperties | Should -Not -Contain 'new_body_field'
            $gap.ReadOnlyFields | Should -Not -Contain 'new_ro_field'
            # old_field (2.0) is not newer than the 2.27 baseline either, so the whole gap
            # for this endpoint disappears entirely -- same "endpoint dropped, not emitted
            # empty" contract as the query-side equivalent test above.
            $gap | Should -BeNullOrEmpty
        }
    }

    Context 'the keys/count/values-shadowing bug -- a field literally named "keys" must not corrupt or swallow other fields' {
        # Regression test for the bug fixed by this task: `$hashtable.Keys` on a plain
        # Hashtable/PSCustomObject-backed IDictionary is shadowed by a KEY literally named
        # "keys" (PowerShell's dictionary-key-as-member adapter resolves ".Keys" to that
        # key's VALUE instead of the real key collection). The real-world instance was
        # DELETE /workloads/tags, whose capability-map parameters are keys/namespaces/
        # resource_ids/resource_names/context_names -- the "keys" key's value ("2.23")
        # was fabricated as a missing field, and every genuine key (context_names, the
        # one real gap) was silently lost. Reproduced here with a body property named
        # "keys" so both the query and body code paths are covered by this same trap.
        It 'reports a query parameter literally named "keys" as a real gap, not a fabricated version string' {
            $capMap = [PSCustomObject]@{
                endpoints = [PSCustomObject]@{
                    'DELETE /fixture-tags' = [PSCustomObject]@{
                        minVersion = '2.0'
                        parameters = [PSCustomObject]@{ keys = '2.23'; namespaces = '2.23'; resource_ids = '2.23'; resource_names = '2.23'; context_names = '2.23' }
                        bodyProperties = [PSCustomObject]@{}
                    }
                }
            }
            $endpoints = @([PSCustomObject]@{ Key = 'DELETE /fixture-tags'; Method = 'DELETE'; Endpoint = '/fixture-tags'; Resolved = $true; Cmdlet = 'Remove-PfbFixtureTag'; File = 'x' })
            $inventory = @(
                [PSCustomObject]@{ Cmdlet = 'Remove-PfbFixtureTag'; Parameter = 'Key'; Surface = 'Typed'; WireName = 'keys'; HasValidateSet = $false; ValidateSetValues = $null; Endpoint = 'fixture-tags'; Method = 'DELETE' }
                [PSCustomObject]@{ Cmdlet = 'Remove-PfbFixtureTag'; Parameter = 'Namespace'; Surface = 'Typed'; WireName = 'namespaces'; HasValidateSet = $false; ValidateSetValues = $null; Endpoint = 'fixture-tags'; Method = 'DELETE' }
                [PSCustomObject]@{ Cmdlet = 'Remove-PfbFixtureTag'; Parameter = 'ResourceId'; Surface = 'Typed'; WireName = 'resource_ids'; HasValidateSet = $false; ValidateSetValues = $null; Endpoint = 'fixture-tags'; Method = 'DELETE' }
                [PSCustomObject]@{ Cmdlet = 'Remove-PfbFixtureTag'; Parameter = 'ResourceName'; Surface = 'Typed'; WireName = 'resource_names'; HasValidateSet = $false; ValidateSetValues = $null; Endpoint = 'fixture-tags'; Method = 'DELETE' }
            )
            $result = Get-PfbParameterCoverageGaps -CapabilityMap $capMap -CmdletInventory $inventory -CalledEndpoints $endpoints
            $gap = $result | Where-Object { $_.Endpoint -eq 'DELETE /fixture-tags' }
            $gap.MissingQueryParameters | Should -Be @('context_names')
            $gap.MissingQueryParameters | Should -Not -Contain '2.23'
        }

        It 'reports a BODY property literally named "keys" as a real gap too (the trap generalises to the new split code)' {
            $capMap = [PSCustomObject]@{
                endpoints = [PSCustomObject]@{
                    'PATCH /fixture-keys-body' = [PSCustomObject]@{
                        minVersion = '2.0'
                        parameters = [PSCustomObject]@{}
                        bodyProperties = [PSCustomObject]@{ keys = '2.0'; count = '2.0'; values = '2.0'; other_field = '2.0' }
                    }
                }
            }
            $endpoints = @([PSCustomObject]@{ Key = 'PATCH /fixture-keys-body'; Method = 'PATCH'; Endpoint = '/fixture-keys-body'; Resolved = $true; Cmdlet = 'Update-PfbFixtureKeysBody'; File = 'x' })
            $result = Get-PfbParameterCoverageGaps -CapabilityMap $capMap -CmdletInventory $noopInventory -CalledEndpoints $endpoints
            $gap = $result | Where-Object { $_.Endpoint -eq 'PATCH /fixture-keys-body' }
            $gap.MissingBodyProperties | Should -Be @('count', 'keys', 'other_field', 'values')
        }
    }

    Context '-CurrentSpecCapabilities excludes phantom fields (present in the accumulated capability map but absent from the newest analysed spec)' {
        BeforeAll {
            $script:phantomCapMap = [PSCustomObject]@{
                endpoints = [PSCustomObject]@{
                    'PATCH /phantom-fixture' = [PSCustomObject]@{
                        minVersion     = '2.0'
                        parameters     = [PSCustomObject]@{ old_query = '2.0'; live_query = '2.0' }
                        bodyProperties = [PSCustomObject]@{ old_body = '2.0'; live_body = '2.0' }
                    }
                }
            }
            $script:phantomEndpoints = @([PSCustomObject]@{ Key = 'PATCH /phantom-fixture'; Method = 'PATCH'; Endpoint = '/phantom-fixture'; Resolved = $true; Cmdlet = 'Update-PfbFixturePhantom'; File = 'x' })
            # Only live_query/live_body still exist in the "current" (newest analysed) spec --
            # old_query/old_body were withdrawn from the API after 2.0 but still linger in the
            # capability map's accumulated (first-sight, never-removed) parameters/bodyProperties.
            $script:currentSpecCaps = @([PSCustomObject]@{ Method = 'PATCH'; Path = '/phantom-fixture'; Parameters = @('live_query'); BodyProperties = @('live_body') })
        }

        It 'drops a phantom query/body field from every list when -CurrentSpecCapabilities is supplied' {
            $result = Get-PfbParameterCoverageGaps -CapabilityMap $phantomCapMap -CmdletInventory $noopInventory -CalledEndpoints $phantomEndpoints -CurrentSpecCapabilities $currentSpecCaps
            $gap = $result | Where-Object { $_.Endpoint -eq 'PATCH /phantom-fixture' }
            $gap.MissingQueryParameters | Should -Be @('live_query')
            $gap.MissingQueryParameters | Should -Not -Contain 'old_query'
            $gap.MissingBodyProperties | Should -Be @('live_body')
            $gap.MissingBodyProperties | Should -Not -Contain 'old_body'
        }

        It 'does NOT filter phantom fields when -CurrentSpecCapabilities is omitted (safe no-op default)' {
            $result = Get-PfbParameterCoverageGaps -CapabilityMap $phantomCapMap -CmdletInventory $noopInventory -CalledEndpoints $phantomEndpoints
            $gap = $result | Where-Object { $_.Endpoint -eq 'PATCH /phantom-fixture' }
            $gap.MissingQueryParameters | Should -Contain 'old_query'
            $gap.MissingBodyProperties | Should -Contain 'old_body'
        }
    }

    It 'reports the same field name in both MissingQueryParameters and MissingBodyProperties without deduping (the real placement_names shape)' {
        # Only 1 of 632 real endpoints has a field name declared as both a query parameter
        # and a body property (POST /workloads/placement-recommendations|placement_names) --
        # this proves that when neither side is covered, both lists legitimately carry it,
        # with no dedup machinery collapsing one away.
        $capMap = [PSCustomObject]@{
            endpoints = [PSCustomObject]@{
                'POST /fixture-dual' = [PSCustomObject]@{
                    minVersion     = '2.0'
                    parameters     = [PSCustomObject]@{ dual_name = '2.0' }
                    bodyProperties = [PSCustomObject]@{ dual_name = '2.0' }
                }
            }
        }
        $endpoints = @([PSCustomObject]@{ Key = 'POST /fixture-dual'; Method = 'POST'; Endpoint = '/fixture-dual'; Resolved = $true; Cmdlet = 'New-PfbFixtureDual'; File = 'x' })
        $result = Get-PfbParameterCoverageGaps -CapabilityMap $capMap -CmdletInventory $noopInventory -CalledEndpoints $endpoints
        $gap = $result | Where-Object { $_.Endpoint -eq 'POST /fixture-dual' }
        $gap.MissingQueryParameters | Should -Contain 'dual_name'
        $gap.MissingBodyProperties | Should -Contain 'dual_name'
    }

    Context 'a cmdlet contributing zero inventory rows leaves nothing unresolved for it' {
        # Regression guard for the null-vs-empty conflation: the per-cmdlet lookup is a
        # Group-Object -AsHashTable, which returns $null for an absent key, and @($null) is
        # a ONE-element array whose element is $null -- so the surface loop used to run once
        # with $row = $null and throw evaluating $null.Surface. The real shape is the
        # -Attributes-only write cmdlet (Update-PfbArray, Update-PfbPasswordPolicy,
        # Update-PfbSupport): every parameter it declares is -Array or -Attributes, both
        # inventory-exempt, so the inventory holds no row for it at all.
        BeforeAll {
            $script:attributesOnlyCapMap = [PSCustomObject]@{
                endpoints = [PSCustomObject]@{
                    'PATCH /widgets' = [PSCustomObject]@{
                        minVersion     = '2.0'
                        parameters     = [PSCustomObject]@{}
                        bodyProperties = [PSCustomObject]@{ banner = '2.0'; ntp_servers = '2.0' }
                    }
                }
            }
            $script:attributesOnlyEndpoints = @(
                [PSCustomObject]@{ Key = 'PATCH /widgets'; Method = 'PATCH'; Endpoint = '/widgets'; Resolved = $true; Cmdlet = 'Update-PfbFixtureWidget'; File = 'x' }
            )
        }

        It 'reports gaps with high confidence when the inventory holds no row for the cmdlet' {
            # Inventory deliberately non-empty but for a DIFFERENT cmdlet, so the hashtable
            # lookup for Update-PfbFixtureWidget misses and yields $null.
            $result = Get-PfbParameterCoverageGaps -CapabilityMap $attributesOnlyCapMap -CmdletInventory $fullyMappedInventory -CalledEndpoints $attributesOnlyEndpoints
            $gap = $result | Where-Object { $_.Endpoint -eq 'PATCH /widgets' }
            $gap | Should -Not -BeNullOrEmpty
            $gap.MissingBodyProperties | Should -Be @('banner', 'ntp_servers')
            $gap.Confidence.Level | Should -Be 'high'
        }

        It 'still surfaces the real gaps AND partial confidence when a second cmdlet on the same endpoint has an unresolved surface' {
            # The vacuous-mapping rule must not become a blanket amnesty: a real
            # AttributesOnly/TypedUnresolved row anywhere on the endpoint still lowers
            # confidence -- but (unlike the old $fullyMapped gate) never discards the gap.
            $twoCmdletEndpoints = @(
                $attributesOnlyEndpoints[0]
                [PSCustomObject]@{ Key = 'PATCH /widgets'; Method = 'PATCH'; Endpoint = '/widgets'; Resolved = $true; Cmdlet = 'Get-PfbFixtureWidget'; File = 'x' }
            )
            $result = Get-PfbParameterCoverageGaps -CapabilityMap $attributesOnlyCapMap -CmdletInventory $notFullyMappedInventory -CalledEndpoints $twoCmdletEndpoints
            $gap = $result | Where-Object { $_.Endpoint -eq 'PATCH /widgets' }
            $gap | Should -Not -BeNullOrEmpty
            $gap.MissingBodyProperties | Should -Be @('banner', 'ntp_servers')
            $gap.Confidence.Level | Should -Be 'partial'
        }
    }
}

Describe 'Get-PfbValidateSetDrift' {
    It 'flags the real Get-PfbArrayPerformance -Protocol bug shape: spec has "all", ValidateSet is missing it' {
        $drift = Get-PfbValidateSetDrift -CmdletInventory $driftInventory -History $driftHistory -OldestVersion '2.0'
        $rec = $drift | Where-Object { $_.Cmdlet -eq 'Get-PfbArrayPerformance' -and $_.Parameter -eq 'Protocol' }
        $rec.MissingValues | Should -Contain 'all'
        $rec.StaleValues | Should -BeNullOrEmpty
    }

    It 'flags a stale ValidateSet value the spec no longer documents' {
        # Cmdlet deliberately follows the module's real <Verb>-Pfb<Noun> convention (not
        # a bare 'Test-Fixture') so Get-PfbResourceHint derives 'ArrayPerformance' and
        # Resolve-PfbFieldValueEnum's resource-hint match actually fires -- otherwise this
        # would vacuously pass/fail on hint-resolution alone rather than on the stale-value
        # comparison this test is meant to exercise.
        $staleInventory = @(
            [PSCustomObject]@{ Cmdlet = 'Test-PfbArrayPerformance'; Parameter = 'Protocol'; Surface = 'Typed'; WireName = 'protocol'; HasValidateSet = $true; ValidateSetValues = @('all', 'nfs', 'smb', 'http', 's3', 'ftp'); Endpoint = 'arrays/performance'; Method = 'GET' }
        )
        $drift = Get-PfbValidateSetDrift -CmdletInventory $staleInventory -History $driftHistory -OldestVersion '2.0'
        $rec = $drift | Where-Object { $_.Cmdlet -eq 'Test-PfbArrayPerformance' }
        $rec.StaleValues | Should -Contain 'ftp'
    }

    It 'does not flag a ValidateSet whose values exactly match the spec' {
        # Same naming-convention reasoning as above -- must actually resolve to 'matched'
        # so this asserts real match-with-no-drift behavior, not vacuous non-resolution.
        $matchingInventory = @(
            [PSCustomObject]@{ Cmdlet = 'Test-PfbArrayPerformance'; Parameter = 'Protocol'; Surface = 'Typed'; WireName = 'protocol'; HasValidateSet = $true; ValidateSetValues = @('all', 'nfs', 'smb', 'http', 's3'); Endpoint = 'arrays/performance'; Method = 'GET' }
        )
        $drift = Get-PfbValidateSetDrift -CmdletInventory $matchingInventory -History $driftHistory -OldestVersion '2.0'
        $drift | Should -BeNullOrEmpty
    }
}

Describe 'Get-PfbSuggestedPowerShellType (Task 5 suggestedPowerShellType mapping)' {
    It 'maps integer + format int64 to [long] -- the 37-real-field truncation-risk case' {
        Get-PfbSuggestedPowerShellType -Type 'integer' -Format 'int64' | Should -Be '[long]'
    }

    It 'maps integer + format int32 to [int]' {
        Get-PfbSuggestedPowerShellType -Type 'integer' -Format 'int32' | Should -Be '[int]'
    }

    It 'maps integer + format uint32 to [int]' {
        Get-PfbSuggestedPowerShellType -Type 'integer' -Format 'uint32' | Should -Be '[int]'
    }

    It 'maps a bare integer with no format to [int], never silently to [long]' {
        Get-PfbSuggestedPowerShellType -Type 'integer' -Format $null | Should -Be '[int]'
    }

    It 'maps number (any format) to [double]' {
        Get-PfbSuggestedPowerShellType -Type 'number' -Format 'double' | Should -Be '[double]'
        Get-PfbSuggestedPowerShellType -Type 'number' -Format 'float' | Should -Be '[double]'
        Get-PfbSuggestedPowerShellType -Type 'number' -Format $null | Should -Be '[double]'
    }

    It 'maps string to [string]' {
        Get-PfbSuggestedPowerShellType -Type 'string' | Should -Be '[string]'
    }

    It 'maps boolean to [bool]' {
        Get-PfbSuggestedPowerShellType -Type 'boolean' | Should -Be '[bool]'
    }

    It 'maps array of string to [string[]]' {
        Get-PfbSuggestedPowerShellType -Type 'array' -ItemType 'string' | Should -Be '[string[]]'
    }

    It 'maps array of integer/int64 to [long[]]' {
        Get-PfbSuggestedPowerShellType -Type 'array' -ItemType 'integer' -ItemFormat 'int64' | Should -Be '[long[]]'
    }

    It 'falls back to [object[]] for an array whose element type could not be resolved' {
        Get-PfbSuggestedPowerShellType -Type 'array' -ItemType $null | Should -Be '[object[]]'
    }

    It 'falls back to [object] for $null/unrecognised/object types, never a guessed scalar type' {
        Get-PfbSuggestedPowerShellType -Type $null | Should -Be '[object]'
        Get-PfbSuggestedPowerShellType -Type '' | Should -Be '[object]'
        Get-PfbSuggestedPowerShellType -Type 'object' | Should -Be '[object]'
    }
}

Describe 'Get-PfbBodyPropertyArrayItemType / Get-PfbBodyPropertySynopsis (direct, non-recursive schema lookups)' {
    # $enrichmentSpec is set in the file-level BeforeAll (top of file) -- it is shared with
    # the Get-PfbBodyPropertyEnrichment Describe below, so it must not be re-declared here.

    It 'Get-PfbBodyPropertyArrayItemType resolves an inline items.type/format' {
        $result = Get-PfbBodyPropertyArrayItemType -Spec $enrichmentSpec -OwnerSchema 'Widget' -FieldName 'tags'
        $result.Type | Should -Be 'string'
    }

    It 'Get-PfbBodyPropertyArrayItemType returns $null when items is itself an unresolved $ref with no inline type (never follows it -- one walker, not two)' {
        $result = Get-PfbBodyPropertyArrayItemType -Spec $enrichmentSpec -OwnerSchema 'Widget' -FieldName 'ref_tags'
        $result | Should -BeNullOrEmpty
    }

    It 'Get-PfbBodyPropertyArrayItemType returns $null for a non-array field' {
        Get-PfbBodyPropertyArrayItemType -Spec $enrichmentSpec -OwnerSchema 'Widget' -FieldName 'color' | Should -BeNullOrEmpty
    }

    It 'Get-PfbBodyPropertyArrayItemType returns $null when -OwnerSchema is $null (no named owner to look up)' {
        Get-PfbBodyPropertyArrayItemType -Spec $enrichmentSpec -OwnerSchema $null -FieldName 'tags' | Should -BeNullOrEmpty
    }

    It 'Get-PfbBodyPropertySynopsis returns only the FIRST sentence, not the trailing enum sentence' {
        Get-PfbBodyPropertySynopsis -Spec $enrichmentSpec -OwnerSchema 'Widget' -FieldName 'color' | Should -Be 'The widget color.'
    }

    It 'Get-PfbBodyPropertySynopsis newline-normalises an embedded line wrap before extracting the first sentence' {
        # The raw description wraps mid-SENTENCE ("...available\nin this pool.") -- real
        # spec prose does this (e.g. "...`all-squash`, and\n`no-root-squash`."). The
        # newline must become a space BEFORE the first-sentence regex runs, and only that
        # first sentence is returned -- the second sentence ("Additional prose...") must
        # NOT appear in the result.
        Get-PfbBodyPropertySynopsis -Spec $enrichmentSpec -OwnerSchema 'Widget' -FieldName 'count' | Should -Be 'Count of widgets available in this pool.'
    }

    It 'Get-PfbBodyPropertySynopsis returns the whole (short) description when it has no sentence terminator at all' {
        # 'bare' has type=string but a description with no trigger sentence -- add one with
        # no terminating punctuation to prove the regex-miss fallback path (whole normalised
        # string) rather than throwing or returning $null.
        $specWithNoTerminator = [PSCustomObject]@{
            components = [PSCustomObject]@{
                schemas = [PSCustomObject]@{
                    Widget = [PSCustomObject]@{
                        properties = [PSCustomObject]@{
                            untamed = [PSCustomObject]@{ type = 'string'; description = 'no terminator here' }
                        }
                    }
                }
            }
        }
        Get-PfbBodyPropertySynopsis -Spec $specWithNoTerminator -OwnerSchema 'Widget' -FieldName 'untamed' | Should -Be 'no terminator here'
    }

    It 'Get-PfbBodyPropertySynopsis returns $null when -OwnerSchema is $null (fully inline body, no named owner -- never re-walks to find one)' {
        Get-PfbBodyPropertySynopsis -Spec $enrichmentSpec -OwnerSchema $null -FieldName 'color' | Should -BeNullOrEmpty
    }

    It 'Get-PfbBodyPropertySynopsis returns $null when the named owner schema does not declare the field' {
        Get-PfbBodyPropertySynopsis -Spec $enrichmentSpec -OwnerSchema 'Widget' -FieldName 'nonexistent' | Should -BeNullOrEmpty
    }

    It 'Get-PfbBodyPropertySynopsis returns $null when the property has no description at all' {
        Get-PfbBodyPropertySynopsis -Spec $enrichmentSpec -OwnerSchema 'Widget' -FieldName 'ref_tags' | Should -BeNullOrEmpty
    }
}

Describe 'Find-PfbOwnSchemaPropertyNode / Get-PfbOwnerSchemaPropertyNode (REGRESSION: OwnerSchema is usually allOf-composed on real data)' {
    BeforeAll {
        # Real-data shape (measured against fb2.27, 2026-07-26): _certificateBase,
        # NfsExportPolicyRuleBase, ActiveDirectoryPatch, and SmbSharePolicyRule -- 4 of 4
        # sampled real OwnerSchema values -- carry NO "properties" directly at their own
        # top level; the field lives one level down inside an ANONYMOUS allOf branch. A
        # naive single-hop `schema.properties.$FieldName` lookup returns $null for nearly
        # every real match. This fixture reproduces that exact shape.
        $script:allOfOwnerSpec = [PSCustomObject]@{
            components = [PSCustomObject]@{
                schemas = [PSCustomObject]@{
                    _certificateBase = [PSCustomObject]@{
                        allOf = @(
                            [PSCustomObject]@{ '$ref' = '#/components/schemas/_wrongOwner' }
                            [PSCustomObject]@{
                                type       = 'object'
                                properties = [PSCustomObject]@{
                                    certificate_type = [PSCustomObject]@{ type = 'string'; description = 'The type of the certificate. Valid values are `appliance` and `external`.' }
                                    tags             = [PSCustomObject]@{ type = 'array'; items = [PSCustomObject]@{ type = 'string' }; description = 'Certificate tags.' }
                                }
                            }
                        )
                    }
                    _wrongOwner      = [PSCustomObject]@{
                        properties = [PSCustomObject]@{
                            certificate_type = [PSCustomObject]@{ type = 'string'; description = 'WRONG -- this is a different schema''s field of the same name and must never be read.' }
                        }
                    }
                }
            }
        }
    }

    It 'finds a field declared inside an ANONYMOUS allOf branch of the owner, not just the owner''s own top-level properties' {
        $node = Get-PfbOwnerSchemaPropertyNode -Spec $allOfOwnerSpec -OwnerSchema '_certificateBase' -FieldName 'certificate_type'
        $node | Should -Not -BeNullOrEmpty
        $node.description | Should -Match '^The type of the certificate\.'
    }

    It 'never crosses into a $ref-branch of the owner to find the field (that branch belongs to a DIFFERENT named schema)' {
        # _certificateBase's allOf[0] is a $ref to _wrongOwner, which ALSO declares
        # certificate_type (with a description that would be an obvious tell if read). The
        # real field must resolve to the allOf[1] (anonymous) branch's description, never
        # _wrongOwner's.
        $node = Get-PfbOwnerSchemaPropertyNode -Spec $allOfOwnerSpec -OwnerSchema '_certificateBase' -FieldName 'certificate_type'
        $node.description | Should -Not -Match 'WRONG'
    }

    It 'Get-PfbBodyPropertySynopsis resolves through the allOf-composed owner correctly' {
        Get-PfbBodyPropertySynopsis -Spec $allOfOwnerSpec -OwnerSchema '_certificateBase' -FieldName 'certificate_type' | Should -Be 'The type of the certificate.'
    }

    It 'Get-PfbBodyPropertyArrayItemType resolves an array field declared inside an allOf-composed owner' {
        $result = Get-PfbBodyPropertyArrayItemType -Spec $allOfOwnerSpec -OwnerSchema '_certificateBase' -FieldName 'tags'
        $result.Type | Should -Be 'string'
    }

    It 'returns $null for a field the owner (searched through its own allOf) never declares at all' {
        Get-PfbOwnerSchemaPropertyNode -Spec $allOfOwnerSpec -OwnerSchema '_certificateBase' -FieldName 'nonexistent' | Should -BeNullOrEmpty
    }
}

Describe 'Get-PfbBodyPropertyEnrichment (Task 5: composed enum join + type + synopsis)' {
    BeforeAll {
        $script:enrichmentHistory = [ordered]@{
            'Widget.color'      = [ordered]@{ Name = 'color'; Kind = 'schema'; MinVersion = '2.0'; CurrentValues = @('red', 'blue', 'green'); DistinctValueSets = [System.Collections.Generic.HashSet[string]]::new([string[]]@('blue,green,red')) }
            'OtherSchema.color' = [ordered]@{ Name = 'color'; Kind = 'schema'; MinVersion = '2.0'; CurrentValues = @('x', 'y'); DistinctValueSets = [System.Collections.Generic.HashSet[string]]::new([string[]]@('x,y')) }
        }
    }

    It 'resolves EnumStatus matched and EnumValues via OwnerSchema as the resource hint' {
        $result = Get-PfbBodyPropertyEnrichment -FieldName 'color' -Type 'string' -Format $null -OwnerSchema 'Widget' `
            -Spec $enrichmentSpec -Endpoint 'widgets' -Method 'PATCH' -History $enrichmentHistory -OldestVersion '2.0'
        $result.EnumStatus | Should -Be 'matched'
        $result.EnumValues | Should -Be @('red', 'blue', 'green')
        $result.Synopsis | Should -Be 'The widget color.'
        $result.SuggestedPowerShellType | Should -Be '[string]'
    }

    It 'never lets a $null OwnerSchema wildcard-match every same-named schema-kind history entry -- resolves not-found-in-resource, not a false matched/collision' {
        # WireName 'color' exists in history under TWO different owners with DIFFERENT
        # value sets (Widget.color, OtherSchema.color). With OwnerSchema $null (this
        # specific gap has no named owner), the sentinel resource hint must prefix-match
        # NEITHER of them -- proving '' is never substituted for the sentinel (a '' hint
        # would wildcard-match both and yield 'collision' instead).
        $result = Get-PfbBodyPropertyEnrichment -FieldName 'color' -Type 'string' -Format $null -OwnerSchema $null `
            -Spec $enrichmentSpec -Endpoint 'widgets' -Method 'PATCH' -History $enrichmentHistory -OldestVersion '2.0'
        $result.EnumStatus | Should -Be 'not-found-in-resource'
        $result.EnumValues | Should -BeNullOrEmpty
        $result.Synopsis | Should -BeNullOrEmpty
    }

    It 'resolves EnumStatus no-spec-enum-found for a field absent from History entirely' {
        $result = Get-PfbBodyPropertyEnrichment -FieldName 'nonexistent_field' -Type 'string' -Format $null -OwnerSchema 'Widget' `
            -Spec $enrichmentSpec -Endpoint 'widgets' -Method 'PATCH' -History $enrichmentHistory -OldestVersion '2.0'
        $result.EnumStatus | Should -Be 'no-spec-enum-found'
        $result.EnumValues | Should -BeNullOrEmpty
    }

    It 'derives SuggestedPowerShellType for an array field via the array-item-type lookup' {
        $result = Get-PfbBodyPropertyEnrichment -FieldName 'tags' -Type 'array' -Format $null -OwnerSchema 'Widget' `
            -Spec $enrichmentSpec -Endpoint 'widgets' -Method 'PATCH' -History $enrichmentHistory -OldestVersion '2.0'
        $result.SuggestedPowerShellType | Should -Be '[string[]]'
    }

    It 'derives SuggestedPowerShellType [long] for an int64 field, never the truncating [int]' {
        $result = Get-PfbBodyPropertyEnrichment -FieldName 'count' -Type 'integer' -Format 'int64' -OwnerSchema 'Widget' `
            -Spec $enrichmentSpec -Endpoint 'widgets' -Method 'PATCH' -History $enrichmentHistory -OldestVersion '2.0'
        $result.SuggestedPowerShellType | Should -Be '[long]'
    }

    It 'EnumValues is always an array, never $null, even when EnumStatus is not matched' {
        # Deliberately NOT `$result.EnumValues | Should -BeOfType ...` -- piping a
        # genuinely EMPTY array to Should never invokes the assertion with a real value at
        # all (Pester's pipeline binding sees zero objects go by and reports $null), which
        # would make this test pass or fail for the wrong reason regardless of the actual
        # array-vs-$null distinction it exists to check. Capture into a scalar first.
        $result = Get-PfbBodyPropertyEnrichment -FieldName 'nonexistent_field' -Type 'string' -Format $null -OwnerSchema 'Widget' `
            -Spec $enrichmentSpec -Endpoint 'widgets' -Method 'PATCH' -History $enrichmentHistory -OldestVersion '2.0'
        $isNull = ($null -eq $result.EnumValues)
        $isNull | Should -BeFalse
        $countIsZero = (@($result.EnumValues).Count -eq 0)
        $countIsZero | Should -BeTrue
    }
}

Describe 'Get-PfbSystemicGaps (Task 6, decision 7: collapse per-endpoint gap lists into one finding per wire name)' {
    BeforeAll {
        $script:systemicGaps = @(
            [PSCustomObject]@{ Endpoint = 'GET /a'; MissingQueryParameters = @('context_names', 'filter'); MissingBodyProperties = @() }
            [PSCustomObject]@{ Endpoint = 'GET /b'; MissingQueryParameters = @('context_names'); MissingBodyProperties = @() }
            [PSCustomObject]@{ Endpoint = 'POST /c'; MissingQueryParameters = @(); MissingBodyProperties = @('context_names') }
            [PSCustomObject]@{ Endpoint = 'DELETE /d'; MissingQueryParameters = @('lonely_field'); MissingBodyProperties = @() }
        )
    }

    It 'collapses a name repeated across many endpoints into ONE finding with the right EndpointCount' {
        $findings = Get-PfbSystemicGaps -Gaps $systemicGaps
        $ctx = $findings | Where-Object { $_.Name -eq 'context_names' }
        $ctx | Should -Not -BeNullOrEmpty
        $ctx.EndpointCount | Should -Be 3
        $ctx.Endpoints | Should -Be @('GET /a', 'GET /b', 'POST /c')
    }

    It 'counts query vs body occurrences separately, informationally, without affecting the deduplicated total' {
        $ctx = (Get-PfbSystemicGaps -Gaps $systemicGaps) | Where-Object { $_.Name -eq 'context_names' }
        $ctx.QueryEndpointCount | Should -Be 2
        $ctx.BodyEndpointCount | Should -Be 1
        $ctx.EndpointCount | Should -Be 3
    }

    It 'dedupes an endpoint appearing in BOTH lists for the same name to ONE endpoint credit (the placement_names shape)' {
        $dualGaps = @([PSCustomObject]@{ Endpoint = 'POST /dual'; MissingQueryParameters = @('dual_name'); MissingBodyProperties = @('dual_name') })
        $finding = (Get-PfbSystemicGaps -Gaps $dualGaps) | Where-Object { $_.Name -eq 'dual_name' }
        $finding.EndpointCount | Should -Be 1
        $finding.QueryEndpointCount | Should -Be 1
        $finding.BodyEndpointCount | Should -Be 1
    }

    It 'still emits a finding for a name that appears on only one endpoint' {
        $finding = (Get-PfbSystemicGaps -Gaps $systemicGaps) | Where-Object { $_.Name -eq 'lonely_field' }
        $finding.EndpointCount | Should -Be 1
    }

    It 'sorts findings by EndpointCount descending, Name ascending as a tiebreak' {
        $findings = @(Get-PfbSystemicGaps -Gaps $systemicGaps)
        $findings[0].Name | Should -Be 'context_names'
        ($findings | Select-Object -Skip 1).EndpointCount | ForEach-Object { $_ | Should -BeLessOrEqual $findings[0].EndpointCount }
    }

    It 'returns an empty array for an empty -Gaps input, never $null or an error' {
        $findings = @(Get-PfbSystemicGaps -Gaps @())
        $findings.Count | Should -Be 0
    }

    It 'tolerates an enriched MissingBodyProperties record shape ({name=...}) via Get-PfbGapFieldName, not just bare strings' {
        $enrichedGaps = @([PSCustomObject]@{ Endpoint = 'PATCH /e'; MissingQueryParameters = @(); MissingBodyProperties = @([PSCustomObject]@{ name = 'enriched_field'; type = 'string' }) })
        $finding = (Get-PfbSystemicGaps -Gaps $enrichedGaps) | Where-Object { $_.Name -eq 'enriched_field' }
        $finding | Should -Not -BeNullOrEmpty
        $finding.EndpointCount | Should -Be 1
    }
}

Describe 'Get-PfbConventionStrength (Task 6, decision 8: mechanical batch-fix vs architectural decision)' {
    BeforeAll {
        $script:strengthInventory = @(
            [PSCustomObject]@{ Cmdlet = 'Get-PfbFixtureA'; Parameter = 'Name'; Surface = 'Typed'; WireName = 'names' }
            [PSCustomObject]@{ Cmdlet = 'Get-PfbFixtureB'; Parameter = 'Name'; Surface = 'Typed'; WireName = 'names' }
            [PSCustomObject]@{ Cmdlet = 'Get-PfbFixtureC'; Parameter = 'Id'; Surface = 'Typed'; WireName = 'ids' }
            # A duplicate (Cmdlet, WireName) pair -- e.g. two parameters on the same cmdlet
            # both feeding 'names' -- must still count Get-PfbFixtureA only ONCE.
            [PSCustomObject]@{ Cmdlet = 'Get-PfbFixtureA'; Parameter = 'Alias'; Surface = 'Typed'; WireName = 'names' }
            # An unresolved surface must never contribute -- only 'Typed' counts.
            [PSCustomObject]@{ Cmdlet = 'Get-PfbFixtureD'; Parameter = 'Weird'; Surface = 'AttributesOnly'; WireName = $null }
        )
    }

    It 'counts DISTINCT cmdlets exposing a wire name, deduping a cmdlet with two parameters feeding the same name' {
        $result = Get-PfbConventionStrength -CmdletInventory $strengthInventory -Names @('names')
        $result.CmdletCount | Should -Be 2
        $result.Cmdlets | Should -Be @('Get-PfbFixtureA', 'Get-PfbFixtureB')
    }

    It 'reports 0/empty (never omitted) for a name no cmdlet exposes -- the architectural-decision signal' {
        $result = Get-PfbConventionStrength -CmdletInventory $strengthInventory -Names @('context_names')
        $result.CmdletCount | Should -Be 0
        $result.Cmdlets | Should -Be @()
    }

    It 'preserves -Names input order across multiple names, one result per name' {
        $results = @(Get-PfbConventionStrength -CmdletInventory $strengthInventory -Names @('ids', 'names', 'context_names'))
        $results[0].Name | Should -Be 'ids'
        $results[1].Name | Should -Be 'names'
        $results[2].Name | Should -Be 'context_names'
    }

    It 'ignores an AttributesOnly/unresolved row entirely' {
        $result = Get-PfbConventionStrength -CmdletInventory $strengthInventory -Names @('weird')
        $result.CmdletCount | Should -Be 0
    }
}

Describe 'Get-PfbDriftAnnotations / Find-PfbDriftAnnotation (Task 6: recorded design decisions, prior conclusions, live-testing hazards)' {
    BeforeAll {
        $script:annotationsFixturePath = Join-Path $TestDrive 'drift-annotations.fixture.json'
        Set-Content -Path $annotationsFixturePath -Value @'
{
  "schemaVersion": 1,
  "annotations": [
    { "matchType": "field", "match": "context_names", "kind": "designDecision", "note": "not yet implemented", "reference": "docs/design/fusion-context-injection.md" },
    { "matchType": "field", "match": "allow_errors", "kind": "designDecision", "note": "not yet implemented", "reference": "docs/design/fusion-context-injection.md" },
    { "matchType": "endpoint", "match": "management-access-policies", "kind": "liveTestingHazard", "note": "POST/PATCH/DELETE return 403 regardless of account; not an implementation bug", "reference": null }
  ]
}
'@
    }

    It 'loads the file and finds a field-keyed annotation by exact wire name' {
        # @(...) wraps the call itself, not just its consumption -- a single-match result
        # is a bare PSCustomObject crossing the function-call boundary (PowerShell always
        # unwraps a one-element pipeline result on return, @() inside the function's own
        # `return` notwithstanding). PowerShell 7+ masks this with an automatic .Count/
        # .Length property on every object, so `$found.Count` reads 1 there regardless --
        # but Windows PowerShell 5.1 has no such property and .Count silently returns
        # $null on a bare object. Confirmed live under real 5.1: without this wrap here,
        # this exact assertion fails with "Expected 1, but got $null."
        $annotations = Get-PfbDriftAnnotations -Path $annotationsFixturePath
        $found = @(Find-PfbDriftAnnotation -Annotations $annotations -FieldName 'context_names')
        $found.Count | Should -Be 1
        $found[0].kind | Should -Be 'designDecision'
        $found[0].reference | Should -Be 'docs/design/fusion-context-injection.md'
    }

    It 'never asserts whether allow_errors injection is endpoint-gated or unconditional -- purely descriptive note only' {
        $annotations = Get-PfbDriftAnnotations -Path $annotationsFixturePath
        $found = Find-PfbDriftAnnotation -Annotations $annotations -FieldName 'allow_errors'
        $found[0].note | Should -Be 'not yet implemented'
        $found[0].note | Should -Not -Match 'gate|gated|unconditional|every endpoint'
    }

    It 'finds an endpoint-keyed annotation via case-insensitive substring match against the endpoint key' {
        $annotations = Get-PfbDriftAnnotations -Path $annotationsFixturePath
        $found = @(Find-PfbDriftAnnotation -Annotations $annotations -Endpoint 'POST /management-access-policies')
        $found.Count | Should -Be 1
        $found[0].kind | Should -Be 'liveTestingHazard'
        $found[0].note | Should -Match '403'
    }

    It 'returns an empty array (never $null/error) for a name/endpoint with no annotation' {
        $annotations = Get-PfbDriftAnnotations -Path $annotationsFixturePath
        @(Find-PfbDriftAnnotation -Annotations $annotations -FieldName 'no_such_field').Count | Should -Be 0
    }

    It 'treats a literal "*" in an endpoint annotation''s match value as a literal character, not a live -like wildcard' {
        # A future endpoint-type annotation could legitimately contain a literal '*'. An
        # unescaped `-like "*$($_.match)*"` would treat it as "match anything" instead of
        # a literal asterisk character.
        $wildcardFixturePath = Join-Path $TestDrive 'drift-annotations-wildcard-star.fixture.json'
        Set-Content -Path $wildcardFixturePath -Value @'
{
  "schemaVersion": 1,
  "annotations": [
    { "matchType": "endpoint", "match": "widgets*prod", "kind": "liveTestingHazard", "note": "literal-asterisk regression fixture", "reference": null }
  ]
}
'@
        $annotations = Get-PfbDriftAnnotations -Path $wildcardFixturePath

        # Endpoint contains the literal substring "widgets*prod" -- must match. @(...)
        # wraps the call itself -- see the file-keyed test above for why a bare single-match
        # result silently fails .Count on Windows PowerShell 5.1.
        @(Find-PfbDriftAnnotation -Annotations $annotations -Endpoint 'GET /widgets*prod-fixture').Count | Should -Be 1

        # Endpoint contains "widgets" ... "prod" but NOT the literal "widgets*prod"
        # substring -- an unescaped -like ("*widgets*prod*") would still match this (the
        # '*' matching "anything" in between), so a miss here proves the match string is
        # treated as a literal substring, not a wildcard pattern.
        @(Find-PfbDriftAnnotation -Annotations $annotations -Endpoint 'GET /widgets-are-in-prod').Count | Should -Be 0
    }

    It 'treats a literal "[" in an endpoint annotation''s match value as a literal character, not a live -like character class' {
        # An unescaped `-like "*$($_.match)*"` would treat "[0]" as a character class
        # (matching a single literal '0' character) rather than the literal 3-character
        # text "[0]".
        $wildcardFixturePath = Join-Path $TestDrive 'drift-annotations-wildcard-bracket.fixture.json'
        Set-Content -Path $wildcardFixturePath -Value @'
{
  "schemaVersion": 1,
  "annotations": [
    { "matchType": "endpoint", "match": "prod[0]", "kind": "liveTestingHazard", "note": "literal-bracket regression fixture", "reference": null }
  ]
}
'@
        $annotations = Get-PfbDriftAnnotations -Path $wildcardFixturePath

        # Endpoint contains the literal substring "prod[0]" -- must match. @(...) wraps
        # the call itself -- see the file-keyed test above for why a bare single-match
        # result silently fails .Count on Windows PowerShell 5.1.
        @(Find-PfbDriftAnnotation -Annotations $annotations -Endpoint 'GET /prod[0]-real').Count | Should -Be 1

        # Endpoint contains "prod" immediately followed by "0" (no brackets) -- an
        # unescaped -like would still match this (the "[0]" character class matching that
        # literal '0'), so a miss here proves the match string is treated as a literal
        # substring, not a wildcard pattern.
        @(Find-PfbDriftAnnotation -Annotations $annotations -Endpoint 'GET /prod0-fixture').Count | Should -Be 0
    }

    It 'returns $null (never throws) when -Path does not exist' {
        Get-PfbDriftAnnotations -Path (Join-Path $TestDrive 'does-not-exist.json') | Should -BeNullOrEmpty
    }

    It 'Find-PfbDriftAnnotation tolerates a $null -Annotations without throwing' {
        @(Find-PfbDriftAnnotation -Annotations $null -FieldName 'context_names').Count | Should -Be 0
    }

    It 'the real checked-in docs/drift-annotations.json loads and carries both required seed entries' {
        $realPath = Join-Path $repoRoot 'docs/drift-annotations.json'
        Test-Path $realPath | Should -BeTrue
        # @(...) wraps each call itself -- see the file-keyed test above for why a bare
        # single-match result silently fails .Count on Windows PowerShell 5.1.
        $realAnnotations = Get-PfbDriftAnnotations -Path $realPath
        @(Find-PfbDriftAnnotation -Annotations $realAnnotations -FieldName 'context_names').Count | Should -Be 1
        @(Find-PfbDriftAnnotation -Annotations $realAnnotations -FieldName 'allow_errors').Count | Should -Be 1
        @(Find-PfbDriftAnnotation -Annotations $realAnnotations -Endpoint 'DELETE /management-access-policies').Count | Should -Be 1
    }
}

Describe 'Get-PfbCentralInjectionSites / Get-PfbDerivedNonActionableParameters / Get-PfbNonActionableParameters (Task 6: central-injection detection)' {
    BeforeAll {
        $script:injectionFixtureDir = Join-Path $TestDrive 'InjectionPrivate'
        New-Item -ItemType Directory -Path $injectionFixtureDir -Force | Out-Null

        # Mirrors the REAL Private/Add-PfbCommonQueryParams.ps1 shape exactly: every
        # assignment here traces its VALUE back to a parameter of this function, either
        # directly (-Names/-Ids) or via the $BoundParameters dictionary the caller
        # forwarded (-Filter/-Sort/-Limit), or via a narrowly-shaped ContainsKey(...) guard
        # whose value is a literal (-TotalOnly).
        Set-Content -Path (Join-Path $injectionFixtureDir 'Add-PfbFixtureCommonQueryParams.ps1') -Value @'
function Add-PfbFixtureCommonQueryParams {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Into,
        [Parameter(Mandatory)][System.Collections.IDictionary]$BoundParameters,
        [string[]]$Names,
        [string[]]$Ids
    )
    if ($BoundParameters.ContainsKey('Filter'))    { $Into['filter']     = $BoundParameters['Filter'] }
    if ($BoundParameters.ContainsKey('TotalOnly')) { $Into['total_only'] = 'true' }
    if ($Names) { $Into['names'] = $Names -join ',' }
}
'@

        # Mirrors the REAL Private/Invoke-PfbApiRequest.ps1 shape exactly: the assigned
        # VALUE traces to $response (server data), and the guarding condition is a compound
        # -and expression that merely INCLUDES -AutoPaginate as one operand -- it must NOT
        # count as "gated on a parameter" for THIS key's value.
        Set-Content -Path (Join-Path $injectionFixtureDir 'Invoke-PfbFixtureApiRequest.ps1') -Value @'
function Invoke-PfbFixtureApiRequest {
    [CmdletBinding()]
    param(
        [hashtable]$QueryParams,
        [switch]$AutoPaginate
    )
    $response = Invoke-RestMethod -Uri 'https://example.invalid'
    $limitReached = $false
    if ($AutoPaginate -and $response.continuation_token -and -not $limitReached) {
        $QueryParams['continuation_token'] = $response.continuation_token
    }
}
'@

        # HTTP-transport plumbing that must be OUT OF SCOPE entirely -- a variable name not
        # in the recognized set (queryParams/body/into).
        Set-Content -Path (Join-Path $injectionFixtureDir 'Invoke-PfbFixtureLogin.ps1') -Value @'
function Invoke-PfbFixtureLogin {
    [CmdletBinding()]
    param([string]$Token)
    $headers = @{}
    $headers['Authorization'] = "Bearer $Token"
}
'@

        $script:injectionSites = Get-PfbCentralInjectionSites -PrivateDirectory $injectionFixtureDir
    }

    It 'classifies filter (via $BoundParameters, a parameter) as parameter-sourced' {
        ($injectionSites | Where-Object { $_.Key -eq 'filter' }).Classification | Should -Be 'parameter-sourced'
    }

    It 'classifies total_only (literal RHS, but ContainsKey-guarded on a parameter) as parameter-sourced' {
        ($injectionSites | Where-Object { $_.Key -eq 'total_only' }).Classification | Should -Be 'parameter-sourced'
    }

    It 'classifies names (direct parameter reference in the RHS) as parameter-sourced' {
        ($injectionSites | Where-Object { $_.Key -eq 'names' }).Classification | Should -Be 'parameter-sourced'
    }

    It 'classifies continuation_token (RHS traces to $response, compound non-parameter guard) as server-or-internal-derived' {
        ($injectionSites | Where-Object { $_.Key -eq 'continuation_token' }).Classification | Should -Be 'server-or-internal-derived'
    }

    It 'never picks up an out-of-scope hashtable variable name (headers is not body/queryParams/into)' {
        $injectionSites | Where-Object { $_.Key -eq 'Authorization' } | Should -BeNullOrEmpty
    }

    It 'every site carries the coverage-not-correctness caveat' {
        $injectionSites | ForEach-Object { $_.Caveat | Should -Match 'coverage' }
    }

    It 'Get-PfbDerivedNonActionableParameters includes continuation_token but excludes filter/total_only/names' {
        $derived = Get-PfbDerivedNonActionableParameters -InjectionSites $injectionSites
        $derived.Name | Should -Contain 'continuation_token'
        $derived.Name | Should -Not -Contain 'filter'
        $derived.Name | Should -Not -Contain 'total_only'
        $derived.Name | Should -Not -Contain 'names'
    }

    It 'marks continuation_token Strength as structural, not the general coverage claim' {
        $derived = Get-PfbDerivedNonActionableParameters -InjectionSites $injectionSites
        ($derived | Where-Object { $_.Name -eq 'continuation_token' }).Strength | Should -Be 'structural'
    }

    It 'Get-PfbNonActionableParameters unions the hardcoded X-Request-ID/offset with the derived continuation_token' {
        $merged = Get-PfbNonActionableParameters -PrivateDirectory $injectionFixtureDir
        $merged | Should -Be @('continuation_token', 'offset', 'X-Request-ID') | Sort-Object
        $merged | Should -Contain 'X-Request-ID'
        $merged | Should -Contain 'offset'
        $merged | Should -Contain 'continuation_token'
        $merged | Should -Not -Contain 'filter'
        $merged | Should -Not -Contain 'names'
    }

    It 'a key with even ONE parameter-sourced site anywhere is never derived, even if another site for it looked server-derived' {
        # Regression guard for the exact mistake this effort already caught and corrected
        # once: a bare "any assignment found" rule would have wrongly flagged
        # Add-PfbCommonQueryParams' own keys. Two sites for the SAME key, one of each
        # classification -- the derived result must still exclude it.
        $mixedDir = Join-Path $TestDrive 'MixedPrivate'
        New-Item -ItemType Directory -Path $mixedDir -Force | Out-Null
        Set-Content -Path (Join-Path $mixedDir 'Test-PfbFixtureMixed.ps1') -Value @'
function Test-PfbFixtureMixed {
    [CmdletBinding()]
    param([string]$Sort)
    $queryParams = @{}
    if ($Sort) { $queryParams['sort'] = $Sort }
    $response = Invoke-RestMethod -Uri 'https://example.invalid'
    $queryParams['sort'] = $response.default_sort
}
'@
        $mixedSites = Get-PfbCentralInjectionSites -PrivateDirectory $mixedDir
        ($mixedSites | Where-Object { $_.Key -eq 'sort' }).Classification | Should -Be @('parameter-sourced', 'server-or-internal-derived')
        $derived = Get-PfbDerivedNonActionableParameters -InjectionSites $mixedSites
        $derived.Name | Should -Not -Contain 'sort'
    }

    It 'X-Request-ID and offset have no Private/ injection site in this fixture, matching the real tree (confirmed separately below)' {
        $injectionSites | Where-Object { $_.Key -eq 'X-Request-ID' } | Should -BeNullOrEmpty
        $injectionSites | Where-Object { $_.Key -eq 'offset' } | Should -BeNullOrEmpty
    }
}

Describe 'Central-injection detection against the REAL Private/ tree (confirms the acceptance-critical claims for real)' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
    BeforeAll {
        $script:realPrivateDirectory = Join-Path $repoRoot 'Private'
    }

    It 'X-Request-ID has no injection site anywhere in the real Private/ tree' {
        $sites = Get-PfbCentralInjectionSites -PrivateDirectory $realPrivateDirectory
        $sites | Where-Object { $_.Key -eq 'X-Request-ID' } | Should -BeNullOrEmpty
    }

    It 'offset has no injection site anywhere in the real Private/ tree' {
        $sites = Get-PfbCentralInjectionSites -PrivateDirectory $realPrivateDirectory
        $sites | Where-Object { $_.Key -eq 'offset' } | Should -BeNullOrEmpty
    }

    It 'filter/sort/limit/total_only/names/ids are all classified parameter-sourced, never a candidate for exclusion' {
        $sites = Get-PfbCentralInjectionSites -PrivateDirectory $realPrivateDirectory
        foreach ($key in @('filter', 'sort', 'limit', 'total_only', 'names', 'ids')) {
            $matching = @($sites | Where-Object { $_.Key -eq $key })
            $matching | Should -Not -BeNullOrEmpty
            $matching | ForEach-Object { $_.Classification | Should -Be 'parameter-sourced' }
        }
        $derived = Get-PfbDerivedNonActionableParameters -InjectionSites $sites
        foreach ($key in @('filter', 'sort', 'limit', 'total_only', 'names', 'ids')) {
            $derived.Name | Should -Not -Contain $key
        }
    }

    It 'continuation_token is derived as server-or-internal-derived / structural from the real Invoke-PfbApiRequest.ps1' {
        $sites = Get-PfbCentralInjectionSites -PrivateDirectory $realPrivateDirectory
        $ctSites = @($sites | Where-Object { $_.Key -eq 'continuation_token' })
        $ctSites | Should -Not -BeNullOrEmpty
        $ctSites | ForEach-Object { $_.Classification | Should -Be 'server-or-internal-derived' }

        $derived = Get-PfbDerivedNonActionableParameters -InjectionSites $sites
        $ctDerived = $derived | Where-Object { $_.Name -eq 'continuation_token' }
        $ctDerived | Should -Not -BeNullOrEmpty
        $ctDerived.Strength | Should -Be 'structural'
    }

    It 'Get-PfbNonActionableParameters against the real tree contains X-Request-ID/offset/continuation_token and nothing from Add-PfbCommonQueryParams' {
        $merged = Get-PfbNonActionableParameters -PrivateDirectory $realPrivateDirectory
        $merged | Should -Contain 'X-Request-ID'
        $merged | Should -Contain 'offset'
        $merged | Should -Contain 'continuation_token'
        foreach ($key in @('filter', 'sort', 'limit', 'total_only', 'names', 'ids')) {
            $merged | Should -Not -Contain $key
        }
    }
}

Describe 'Task 6 real-data invariants (systemic gaps + convention strength, skips gracefully if the real capability map is absent)' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
    BeforeAll {
        $script:realCapabilityMapPath2 = Join-Path $repoRoot 'Data/PfbCapabilityMap.json'
        $script:realPublicDirectory2 = Join-Path $repoRoot 'Public'
        $script:realPrivateDirectory2 = Join-Path $repoRoot 'Private'
        $script:realSpecsDirectory2 = Join-Path $repoRoot 'tools/specs'
        $script:hasRealData = (Test-Path $realCapabilityMapPath2) -and (Test-Path $realSpecsDirectory2) -and (Get-ChildItem $realSpecsDirectory2 -Filter 'fb*.json' -ErrorAction SilentlyContinue)

        if ($hasRealData) {
            # Mirrors tools/Build-PfbApiDriftReport.ps1's own construction exactly (same
            # -CurrentSpecCapabilities phantom-field filtering, same -ExcludedFields via
            # Get-PfbNonActionableParameters) -- Get-PfbSystemicGaps must be fed the SAME
            # gaps the real report actually emits, not a looser, unfiltered set, or the
            # invariants below would no longer reflect the filtering the production report
            # actually applies.
            . (Join-Path $repoRoot 'tools/lib/PfbSpecTools.ps1')

            $script:realCapMap2 = Get-Content -Path $realCapabilityMapPath2 -Raw | ConvertFrom-Json -Depth 20
            $script:realInventory2 = Get-PfbCmdletParameterInventory -PublicDirectory $realPublicDirectory2
            $script:realCalledEndpoints2 = Get-PfbModuleCalledEndpoints -PublicDirectory $realPublicDirectory2 -PrivateDirectory $realPrivateDirectory2

            $newestAnalysedVersion2 = $realCapMap2.generatedFrom | Select-Object -Last 1
            $currentSpecCapabilities2 = @()
            if ($newestAnalysedVersion2) {
                $newestSpecPath2 = Join-Path $realSpecsDirectory2 "fb$newestAnalysedVersion2.json"
                if (Test-Path $newestSpecPath2) {
                    $newestSpec2 = Get-Content -Path $newestSpecPath2 -Raw | ConvertFrom-Json -Depth 64
                    $currentSpecCapabilities2 = @(Get-PfbSpecCapabilities -Spec $newestSpec2)
                }
            }

            $nonActionable2 = Get-PfbNonActionableParameters -PrivateDirectory $realPrivateDirectory2

            $script:realGapsAllConfidence2 = Get-PfbParameterCoverageGaps -CapabilityMap $realCapMap2 -CmdletInventory $realInventory2 -CalledEndpoints $realCalledEndpoints2 -ExcludedFields $nonActionable2 -CurrentSpecCapabilities $currentSpecCapabilities2
            # Filtered to 'high'-confidence endpoints only, same precedent as Task 5's own
            # MissingBodyProperties enrichment gate (Get-PfbBodyPropertyEnrichment is only
            # ever invoked for a 'high'-confidence endpoint) -- a 'partial'-confidence
            # endpoint's gap lists can contain false positives (an unresolved parameter may
            # already cover the apparent gap through a path this AST-only inventory can't
            # see), so surfacing it as a systemic-gaps FINDING would overstate the same
            # confidence Get-PfbParameterCoverageGaps's own `confidence.caveat` explicitly
            # warns against. Get-PfbSystemicGaps/Get-PfbConventionStrength themselves are
            # confidence-agnostic by design (aggregation is a pure grouping over WHATEVER
            # gaps they're handed) -- filtering by confidence is the CALLER's decision, made
            # explicitly here to match tools/Build-PfbApiDriftReport.ps1's own filtering exactly.
            $script:realGaps2 = @($realGapsAllConfidence2 | Where-Object { $_.Confidence.Level -eq 'high' })
            $script:realSystemicGaps2 = @(Get-PfbSystemicGaps -Gaps $realGaps2)

            function Get-RealRecountedEndpointCount2 {
                param([Parameter(Mandatory)][object[]]$Gaps, [Parameter(Mandatory)][string]$FieldName)
                $endpoints = [System.Collections.Generic.HashSet[string]]::new()
                foreach ($g in $Gaps) {
                    $queryNames = @($g.MissingQueryParameters)
                    $bodyNames = @($g.MissingBodyProperties | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.Name } })
                    if (($queryNames -contains $FieldName) -or ($bodyNames -contains $FieldName)) {
                        [void]$endpoints.Add($g.Endpoint)
                    }
                }
                return $endpoints.Count
            }
        }
    }

    # Historical note (Task 6 investigation): the task brief's corrected figure for
    # context_names was 252; three independent methodological variants (with/without
    # phantom-field filtering, with/without -ExcludedFields) all converged on 253 instead,
    # and 252 could not be reproduced. 253 was the actual, honestly-measured, reproducible
    # value AT THE TIME -- kept here as institutional memory, not as a hardcoded expectation.
    # See docs/superpowers/plans/2026-07-30-drift-report-acceptance-figure-invariants.md for
    # why exact real-data counts are the wrong assertion for an ever-growing API surface.
    It 'systemic-gaps EndpointCount for allow_errors/context_names matches an independent recount straight from the same $realGaps2 fed to Get-PfbSystemicGaps' {
        if (-not $hasRealData) { Set-ItResult -Skipped -Because 'Data/PfbCapabilityMap.json not present locally'; return }
        foreach ($fieldName in @('allow_errors', 'context_names')) {
            $finding = $realSystemicGaps2 | Where-Object { $_.Name -eq $fieldName }
            $finding | Should -Not -BeNullOrEmpty -Because "$fieldName is expected to still be a systemic gap in the real API surface"
            $recount = Get-RealRecountedEndpointCount2 -Gaps $realGaps2 -FieldName $fieldName
            $finding.EndpointCount | Should -Be $recount -Because 'EndpointCount must equal a fresh tally over the same input gaps, independent of Get-PfbSystemicGaps'' own aggregation'
            $finding.EndpointCount | Should -BeGreaterThan 0 -Because 'a vacuous/zero count would mean the field silently stopped being a systemic gap without anyone noticing here'
        }
    }

    It 'convention strength: names/ids have a non-vacuous, established convention; context_names has none (0 cmdlets, by design)' {
        if (-not $hasRealData) { Set-ItResult -Skipped -Because 'Data/PfbCapabilityMap.json not present locally'; return }
        $strength = Get-PfbConventionStrength -CmdletInventory $realInventory2 -Names @('names', 'ids', 'context_names')
        foreach ($fieldName in @('names', 'ids')) {
            $entry = $strength | Where-Object { $_.Name -eq $fieldName }
            $entry | Should -Not -BeNullOrEmpty
            # CmdletCount is asserted -BeGreaterThan 0, not an exact number: both grow every
            # time an unrelated PR adds a cmdlet that happens to expose this wire name as a
            # Typed parameter, which is neither a regression nor something worth re-pinning for.
            $entry.CmdletCount | Should -BeGreaterThan 0 -Because "$fieldName is a widely-adopted convention; a drop to zero would be a real regression"
        }
        # context_names is the ONE name Get-PfbConventionStrength's own docstring calls out
        # as an architectural fact, not a live count: "that zero IS the finding". Unlike
        # names/ids above, this stays an exact pin deliberately.
        ($strength | Where-Object { $_.Name -eq 'context_names' }).CmdletCount | Should -Be 0
    }

    It 'the top-10 most-common field names absorb between 30% and 55% of total missing-field (endpoint, name) pairs' {
        if (-not $hasRealData) { Set-ItResult -Skipped -Because 'Data/PfbCapabilityMap.json not present locally'; return }
        $pairCounts = $realSystemicGaps2 | ForEach-Object { $_.QueryEndpointCount + $_.BodyEndpointCount }
        $totalPairs = ($pairCounts | Measure-Object -Sum).Sum
        $top10Sum = (($realSystemicGaps2 | ForEach-Object { [PSCustomObject]@{ Name = $_.Name; Pairs = $_.QueryEndpointCount + $_.BodyEndpointCount } }) |
                Sort-Object Pairs -Descending | Select-Object -First 10 | Measure-Object -Property Pairs -Sum).Sum
        $ratio = $top10Sum / $totalPairs
        Write-Host "Task 6 real-data verification: top-10 aggregation ratio = $top10Sum / $totalPairs = $([Math]::Round($ratio * 100, 2))%"
        # Not bit-for-bit pinned (Task 4/5 changed some list membership per this task's own
        # brief) -- just confirms the aggregation actually matters. Historical note: the
        # independently-measured ratio AT THE TIME these bounds were chosen was ~41.7%
        # (576/1302 pairs); kept here as institutional memory for why 30%/55% were picked,
        # not as an expectation this should still measure exactly that today.
        $ratio | Should -BeGreaterThan 0.30
        $ratio | Should -BeLessThan 0.55
    }
}

Describe 'Get-PfbResponseShapeFindings' {
    BeforeAll {
        $script:fixtureMap = [PSCustomObject]@{
            schemaVersion = 1
            generatedFrom = @('2.0', '2.1', '2.2')
            endpoints     = [PSCustomObject]@{
                'GET /widgets'  = [PSCustomObject]@{
                    minVersion             = '2.0'
                    lastSeenVersion        = '2.2'
                    responseEnvelope       = [PSCustomObject]@{ items = '2.0'; errors = '2.1'; total_item_count = '2.0' }
                    responseItemProperties = [PSCustomObject]@{ name = '2.0'; widget_name = '2.2' }
                    removedResponseFields  = @(
                        [PSCustomObject]@{ field = 'wname'; location = 'items'; introducedVersion = '2.0'; lastSeenVersion = '2.1' }
                    )
                }
                'GET /gadgets' = [PSCustomObject]@{
                    minVersion             = '2.0'
                    lastSeenVersion        = '2.2'
                    responseEnvelope       = [PSCustomObject]@{ items = '2.0'; errors = '2.1' }
                    responseItemProperties = [PSCustomObject]@{ name = '2.0' }
                }
                'POST /keytabs/upload' = [PSCustomObject]@{
                    minVersion             = '2.0'
                    lastSeenVersion        = '2.2'
                    responseEnvelope       = [PSCustomObject]@{}
                    responseItemProperties = [PSCustomObject]@{}
                }
            }
        }

        $script:handlerPath = Join-Path $TestDrive 'Invoke-PfbApiRequest.ps1'
        @'
if ($null -ne $response.items) { $allItems.Add($response.items) }
if ($null -ne $response.total_item_count) { $totalItemCount = $response.total_item_count }
if ($response.continuation_token) { $more = $true }
'@ | Set-Content $script:handlerPath
    }

    It 'flattens removals one record per endpoint and field' {
        $f = Get-PfbResponseShapeFindings -ResponseShapeMap $script:fixtureMap -RequestHandlerPath $script:handlerPath
        @($f.Removals).Count | Should -Be 1
        $f.Removals[0].Endpoint | Should -Be 'GET /widgets'
        $f.Removals[0].Field | Should -Be 'wname'
        $f.Removals[0].LastSeenVersion | Should -Be '2.1'
    }

    It 'pairs a removal with a same-version addition as a rename CANDIDATE' {
        $f = Get-PfbResponseShapeFindings -ResponseShapeMap $script:fixtureMap -RequestHandlerPath $script:handlerPath
        @($f.RenameCandidates).Count | Should -Be 1
        $f.RenameCandidates[0].From | Should -Be 'wname'
        $f.RenameCandidates[0].To | Should -Be 'widget_name'
        $f.RenameCandidates[0].Endpoint | Should -Be 'GET /widgets'
    }

    It 'reports errors as an envelope field the request handler never reads' {
        $f = Get-PfbResponseShapeFindings -ResponseShapeMap $script:fixtureMap -RequestHandlerPath $script:handlerPath
        $names = @($f.UnhandledEnvelopeFields | ForEach-Object { $_.Field })
        $names | Should -Contain 'errors'
        $names | Should -Not -Contain 'items'
        $names | Should -Not -Contain 'total_item_count'
    }

    It 'counts how many endpoints declare each unhandled envelope field, with endpoint count not occurrence count' {
        $f = Get-PfbResponseShapeFindings -ResponseShapeMap $script:fixtureMap -RequestHandlerPath $script:handlerPath
        ($f.UnhandledEnvelopeFields | Where-Object { $_.Field -eq 'errors' }).EndpointCount | Should -Be 2
    }

    It 'sorts removals by Endpoint/Location/Field independent of JSON key order' {
        # Removals declared in non-alphabetical order on GET /apple
        $map = [PSCustomObject]@{
            generatedFrom = @('2.0', '2.1')
            endpoints     = [PSCustomObject]@{
                'GET /apple' = [PSCustomObject]@{
                    minVersion             = '2.0'
                    lastSeenVersion        = '2.1'
                    responseEnvelope       = [PSCustomObject]@{ items = '2.0' }
                    responseItemProperties = [PSCustomObject]@{}
                    removedResponseFields  = @(
                        [PSCustomObject]@{ field = 'yankee'; location = 'items'; introducedVersion = '2.0'; lastSeenVersion = '2.1' }
                        [PSCustomObject]@{ field = 'alpha'; location = 'items'; introducedVersion = '2.0'; lastSeenVersion = '2.1' }
                    )
                }
            }
        }
        $handler = Join-Path $TestDrive 'Invoke-PfbApiRequest-removals.ps1'
        @'
if ($null -ne $response.items) { $allItems.Add($response.items) }
'@ | Set-Content $handler
        $f = Get-PfbResponseShapeFindings -ResponseShapeMap $map -RequestHandlerPath $handler
        # Natural emission order from removedResponseFields array: [yankee, alpha]
        # Sorted order by Endpoint, Location, Field: [alpha, yankee]
        @($f.Removals).Count | Should -Be 2
        $f.Removals[0].Field | Should -Be 'alpha'
        $f.Removals[1].Field | Should -Be 'yankee'
    }

    It 'sorts rename candidates by Endpoint/Location/From independent of removal declaration order' {
        # Three candidates whose NATURAL emission order (removedResponseFields declaration
        # order) contradicts the sorted order on BOTH remaining sort keys. The Endpoint key
        # cannot be defeated by a fixture -- the endpoint loop itself already iterates
        # $endpointNames sorted -- so this fixture puts all three on one endpoint and
        # exercises Location (envelope < items) and From (alpha < zulu) instead.
        #
        # Each removal is given a DISTINCT successor version, and each bag holds exactly one
        # field at that version, so every removal yields exactly one candidate rather than a
        # cross-product of every same-version field in the bag.
        #   zulu  (items)    lastSeen 2.0 -> successor 2.1 -> zulu_new  (2.1)
        #   alpha (items)    lastSeen 2.1 -> successor 2.2 -> alpha_new (2.2)
        #   mike  (envelope) lastSeen 2.2 -> successor 2.3 -> mike_new  (2.3)
        $map = [PSCustomObject]@{
            generatedFrom = @('2.0', '2.1', '2.2', '2.3')
            endpoints     = [PSCustomObject]@{
                'POST /apple' = [PSCustomObject]@{
                    minVersion             = '2.0'
                    lastSeenVersion        = '2.3'
                    responseEnvelope       = [PSCustomObject]@{ items = '2.0'; mike_new = '2.3' }
                    responseItemProperties = [PSCustomObject]@{ zulu_new = '2.1'; alpha_new = '2.2' }
                    removedResponseFields  = @(
                        [PSCustomObject]@{ field = 'zulu'; location = 'items'; introducedVersion = '2.0'; lastSeenVersion = '2.0' }
                        [PSCustomObject]@{ field = 'alpha'; location = 'items'; introducedVersion = '2.0'; lastSeenVersion = '2.1' }
                        [PSCustomObject]@{ field = 'mike'; location = 'envelope'; introducedVersion = '2.0'; lastSeenVersion = '2.2' }
                    )
                }
            }
        }
        $handler = Join-Path $TestDrive 'Invoke-PfbApiRequest-candidates.ps1'
        @'
if ($null -ne $response.items) { $allItems.Add($response.items) }
'@ | Set-Content $handler
        $f = Get-PfbResponseShapeFindings -ResponseShapeMap $map -RequestHandlerPath $handler
        # Natural emission order (declaration order): [zulu(items), alpha(items), mike(envelope)]
        # Sorted by Endpoint, Location, From:          [mike(envelope), alpha(items), zulu(items)]
        @($f.RenameCandidates).Count | Should -Be 3
        @($f.RenameCandidates | ForEach-Object { "$($_.Location)/$($_.From)->$($_.To)" }) | Should -Be @(
            'envelope/mike->mike_new'
            'items/alpha->alpha_new'
            'items/zulu->zulu_new'
        )
    }

    It 'sorts unhandled envelope fields by EndpointCount desc/Field asc with differing counts' {
        # zulu appears on 2 endpoints, alpha and bravo on 1 each
        # Correct sort: zulu (2), alpha (1), bravo (1) — count takes precedence
        $map = [PSCustomObject]@{
            generatedFrom = @('2.0', '2.1')
            endpoints     = [PSCustomObject]@{
                'GET /zebra' = [PSCustomObject]@{
                    minVersion             = '2.0'
                    lastSeenVersion        = '2.1'
                    responseEnvelope       = [PSCustomObject]@{ zulu = '2.0'; alpha = '2.0' }
                    responseItemProperties = [PSCustomObject]@{}
                }
                'POST /apple' = [PSCustomObject]@{
                    minVersion             = '2.0'
                    lastSeenVersion        = '2.1'
                    responseEnvelope       = [PSCustomObject]@{ zulu = '2.0'; bravo = '2.0' }
                    responseItemProperties = [PSCustomObject]@{}
                }
            }
        }
        $handler = Join-Path $TestDrive 'Invoke-PfbApiRequest-envelope.ps1'
        @'
if ($null -ne $response.items) { $allItems.Add($response.items) }
'@ | Set-Content $handler
        $f = Get-PfbResponseShapeFindings -ResponseShapeMap $map -RequestHandlerPath $handler
        # Alphabetical order alone: alpha (1), bravo (1), zulu (2)
        # With EndpointCount desc: zulu (2), alpha (1), bravo (1)
        @($f.UnhandledEnvelopeFields).Count | Should -Be 3
        $f.UnhandledEnvelopeFields[0].Field | Should -Be 'zulu'
        $f.UnhandledEnvelopeFields[0].EndpointCount | Should -Be 2
        $f.UnhandledEnvelopeFields[1].Field | Should -Be 'alpha'
        $f.UnhandledEnvelopeFields[1].EndpointCount | Should -Be 1
        $f.UnhandledEnvelopeFields[2].Field | Should -Be 'bravo'
        $f.UnhandledEnvelopeFields[2].EndpointCount | Should -Be 1
    }

    It 'does not throw when an endpoint has an empty responseEnvelope' {
        # This covers the null-handling fix for envelopes that are empty objects {}
        $f = Get-PfbResponseShapeFindings -ResponseShapeMap $script:fixtureMap -RequestHandlerPath $script:handlerPath
        $f | Should -Not -BeNullOrEmpty
        @($f.Removals).Count | Should -Be 1
    }

    It 'does not treat an unrelated later addition as a rename' {
        $map = [PSCustomObject]@{
            generatedFrom = @('2.0', '2.1', '2.2')
            endpoints     = [PSCustomObject]@{
                'GET /widgets' = [PSCustomObject]@{
                    minVersion             = '2.0'
                    lastSeenVersion        = '2.2'
                    responseEnvelope       = [PSCustomObject]@{ items = '2.0' }
                    # introduced at 2.2, but the removal was last seen at 2.0 -> not adjacent
                    responseItemProperties = [PSCustomObject]@{ unrelated = '2.2' }
                    removedResponseFields  = @(
                        [PSCustomObject]@{ field = 'gone'; location = 'items'; introducedVersion = '2.0'; lastSeenVersion = '2.0' }
                    )
                }
            }
        }
        $f = Get-PfbResponseShapeFindings -ResponseShapeMap $map -RequestHandlerPath $script:handlerPath
        @($f.RenameCandidates).Count | Should -Be 0
    }
}
