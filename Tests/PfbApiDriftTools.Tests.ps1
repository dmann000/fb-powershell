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

Describe 'Non-actionable parameter allowlist (X-Request-ID: no functional effect; continuation_token/offset: superseded by -AutoPaginate)' {
    It 'contains exactly the three confirmed non-actionable fields, no more, no fewer' {
        $script:PfbNonActionableParameters | Sort-Object | Should -Be @(
            'continuation_token',
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
