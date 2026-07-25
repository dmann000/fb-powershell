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
        [PSCustomObject]@{ Cmdlet = 'Get-PfbFixtureArraySpace'; Parameter = 'Type'; Surface = 'Typed'; WireName = 'type'; HasValidateSet = $false; ValidateSetValues = $null; Endpoint = 'arrays/space'; Method = 'GET' }
    )
    $script:notFullyMappedInventory = @(
        [PSCustomObject]@{ Cmdlet = 'Get-PfbFixtureWidget'; Parameter = 'Name'; Surface = 'Typed'; WireName = 'name'; HasValidateSet = $false; ValidateSetValues = $null; Endpoint = 'widgets'; Method = 'GET' }
        [PSCustomObject]@{ Cmdlet = 'Get-PfbFixtureWidget'; Parameter = 'Attributes'; Surface = 'AttributesOnly'; WireName = $null; HasValidateSet = $false; ValidateSetValues = $null; Endpoint = $null; Method = $null }
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
    It 'flags a missing parameter on a fully-mapped cmdlet''s endpoint' {
        $endpoints = @([PSCustomObject]@{ Key = 'GET /arrays/space'; Method = 'GET'; Endpoint = '/arrays/space'; Resolved = $true; Cmdlet = 'Get-PfbFixtureArraySpace'; File = 'x' })
        $result = Get-PfbParameterCoverageGaps -CapabilityMap $capabilityMap -CmdletInventory $fullyMappedInventory -CalledEndpoints $endpoints
        $gap = $result.ParameterGaps | Where-Object { $_.Endpoint -eq 'GET /arrays/space' }
        $gap.MissingParameters | Should -Contain 'new_field'
    }

    It 'produces not-verified instead of a guessed gap for a cmdlet with an AttributesOnly parameter' {
        $endpoints = @([PSCustomObject]@{ Key = 'GET /widgets'; Method = 'GET'; Endpoint = '/widgets'; Resolved = $true; Cmdlet = 'Get-PfbFixtureWidget'; File = 'x' })
        $capMapWithWidgets = [PSCustomObject]@{ endpoints = [PSCustomObject]@{ 'GET /widgets' = [PSCustomObject]@{ minVersion = '2.0'; parameters = [PSCustomObject]@{ name = '2.0' }; bodyProperties = [PSCustomObject]@{} } } }
        $result = Get-PfbParameterCoverageGaps -CapabilityMap $capMapWithWidgets -CmdletInventory $notFullyMappedInventory -CalledEndpoints $endpoints
        $result.ParameterGaps | Where-Object { $_.Endpoint -eq 'GET /widgets' } | Should -BeNullOrEmpty
        ($result.NotVerified | Where-Object { $_.Endpoint -eq 'GET /widgets' }).Reason | Should -Be 'has attributes/unresolved surface'
    }

    It 'with -SinceVersion, keeps a missing parameter introduced after that version' {
        $endpoints = @([PSCustomObject]@{ Key = 'GET /arrays/space'; Method = 'GET'; Endpoint = '/arrays/space'; Resolved = $true; Cmdlet = 'Get-PfbFixtureArraySpace'; File = 'x' })
        $result = Get-PfbParameterCoverageGaps -CapabilityMap $capabilityMap -CmdletInventory $fullyMappedInventory -CalledEndpoints $endpoints -SinceVersion '2.0'
        $gap = $result.ParameterGaps | Where-Object { $_.Endpoint -eq 'GET /arrays/space' }
        $gap.MissingParameters | Should -Contain 'new_field'
    }

    It 'with -SinceVersion, drops a gap whose only missing parameter was introduced at or before that version' {
        $endpoints = @([PSCustomObject]@{ Key = 'GET /arrays/space'; Method = 'GET'; Endpoint = '/arrays/space'; Resolved = $true; Cmdlet = 'Get-PfbFixtureArraySpace'; File = 'x' })
        $result = Get-PfbParameterCoverageGaps -CapabilityMap $capabilityMap -CmdletInventory $fullyMappedInventory -CalledEndpoints $endpoints -SinceVersion '2.27'
        $result.ParameterGaps | Where-Object { $_.Endpoint -eq 'GET /arrays/space' } | Should -BeNullOrEmpty
    }

    It 'flags X-Request-ID as a missing parameter when -ExcludedFields is not given' {
        $endpoints = @([PSCustomObject]@{ Key = 'GET /arrays/space'; Method = 'GET'; Endpoint = '/arrays/space'; Resolved = $true; Cmdlet = 'Get-PfbFixtureArraySpace'; File = 'x' })
        $result = Get-PfbParameterCoverageGaps -CapabilityMap $capabilityMap -CmdletInventory $fullyMappedInventory -CalledEndpoints $endpoints
        $gap = $result.ParameterGaps | Where-Object { $_.Endpoint -eq 'GET /arrays/space' }
        $gap.MissingParameters | Should -Contain 'X-Request-ID'
    }

    It 'with -ExcludedFields, excludes a named field but keeps other real gaps on the same endpoint' {
        $endpoints = @([PSCustomObject]@{ Key = 'GET /arrays/space'; Method = 'GET'; Endpoint = '/arrays/space'; Resolved = $true; Cmdlet = 'Get-PfbFixtureArraySpace'; File = 'x' })
        $result = Get-PfbParameterCoverageGaps -CapabilityMap $capabilityMap -CmdletInventory $fullyMappedInventory -CalledEndpoints $endpoints -ExcludedFields @('X-Request-ID')
        $gap = $result.ParameterGaps | Where-Object { $_.Endpoint -eq 'GET /arrays/space' }
        $gap.MissingParameters | Should -Not -Contain 'X-Request-ID'
        $gap.MissingParameters | Should -Contain 'new_field'
    }

    It 'with -ExcludedFields, drops a gap entirely when every missing field is excluded' {
        $endpoints = @([PSCustomObject]@{ Key = 'GET /widgets'; Method = 'GET'; Endpoint = '/widgets'; Resolved = $true; Cmdlet = 'Get-PfbFixtureWidget'; File = 'x' })
        $capMapOnlyXRid = [PSCustomObject]@{ endpoints = [PSCustomObject]@{ 'GET /widgets' = [PSCustomObject]@{ minVersion = '2.0'; parameters = [PSCustomObject]@{ 'X-Request-ID' = '2.12' }; bodyProperties = [PSCustomObject]@{} } } }
        $inventory = @([PSCustomObject]@{ Cmdlet = 'Get-PfbFixtureWidget'; Parameter = 'Name'; Surface = 'Typed'; WireName = 'name'; HasValidateSet = $false; ValidateSetValues = $null; Endpoint = 'widgets'; Method = 'GET' })
        $result = Get-PfbParameterCoverageGaps -CapabilityMap $capMapOnlyXRid -CmdletInventory $inventory -CalledEndpoints $endpoints -ExcludedFields @('X-Request-ID')
        $result.ParameterGaps | Where-Object { $_.Endpoint -eq 'GET /widgets' } | Should -BeNullOrEmpty
    }

    It 'returns MissingParameters in deterministic alphabetical order regardless of capability-map field order' {
        # Field names deliberately declared in reverse/scrambled order below -- MissingParameters
        # is internally staged through a plain Hashtable (not [ordered]), whose .Keys enumeration
        # order depends on .NET's per-process-randomized string hash codes, so without an explicit
        # sort this list's order silently varies run-to-run on identical input (confirmed live:
        # regenerating Reports/PfbApiDriftReport.md twice produced two byte-different files for the
        # exact same drift content). The fix must sort regardless of insertion order, so this test
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
        $gap = $result.ParameterGaps | Where-Object { $_.Endpoint -eq 'GET /widgets' }
        $gap.MissingParameters | Should -Be @('apple', 'mango', 'zebra')
    }

    Context 'a cmdlet contributing zero inventory rows is vacuously fully mapped' {
        # Regression guard for the null-vs-empty conflation: the per-cmdlet lookup is a
        # Group-Object -AsHashTable, which returns $null for an absent key, and @($null) is
        # a ONE-element array whose element is $null -- so the surface loop used to run once
        # with $row = $null, read $null.Surface -ne 'Typed' as true, and discard the whole
        # endpoint into NotVerified. The real shape is the -Attributes-only write cmdlet
        # (Update-PfbArray, Update-PfbPasswordPolicy, Update-PfbSupport): every parameter it
        # declares is -Array or -Attributes, both inventory-exempt, so the inventory holds no
        # row for it at all -- nothing contradicts full mapping.
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

        It 'reports gaps rather than NotVerified when the inventory holds no row for the cmdlet' {
            # Inventory deliberately non-empty but for a DIFFERENT cmdlet, so the hashtable
            # lookup for Update-PfbFixtureWidget misses and yields $null.
            $result = Get-PfbParameterCoverageGaps -CapabilityMap $attributesOnlyCapMap -CmdletInventory $fullyMappedInventory -CalledEndpoints $attributesOnlyEndpoints
            $result.NotVerified | Where-Object { $_.Endpoint -eq 'PATCH /widgets' } | Should -BeNullOrEmpty
            $gap = $result.ParameterGaps | Where-Object { $_.Endpoint -eq 'PATCH /widgets' }
            $gap | Should -Not -BeNullOrEmpty
            $gap.MissingParameters | Should -Be @('banner', 'ntp_servers')
        }

        It 'still reports NotVerified when a second cmdlet on the same endpoint has an unresolved surface' {
            # The vacuous-mapping rule must not become a blanket amnesty: a real
            # AttributesOnly/TypedUnresolved row anywhere on the endpoint still gates it.
            $twoCmdletEndpoints = @(
                $attributesOnlyEndpoints[0]
                [PSCustomObject]@{ Key = 'PATCH /widgets'; Method = 'PATCH'; Endpoint = '/widgets'; Resolved = $true; Cmdlet = 'Get-PfbFixtureWidget'; File = 'x' }
            )
            $result = Get-PfbParameterCoverageGaps -CapabilityMap $attributesOnlyCapMap -CmdletInventory $notFullyMappedInventory -CalledEndpoints $twoCmdletEndpoints
            $result.ParameterGaps | Where-Object { $_.Endpoint -eq 'PATCH /widgets' } | Should -BeNullOrEmpty
            ($result.NotVerified | Where-Object { $_.Endpoint -eq 'PATCH /widgets' }).Reason | Should -Be 'has attributes/unresolved surface'
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
