#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Unit tests for tools/Build-PfbFieldCmdletMap.ps1's classification logic, against
    small synthetic inventory + spec fixtures. Also includes one real-artifact check that
    skips gracefully if tools/specs/ isn't present, matching
    Tests/Build-PfbValueEnumMap.Tests.ps1's convention.
#>

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'tools/lib/PfbSpecTools.ps1')
    . (Join-Path $repoRoot 'tools/lib/PfbValueEnumTools.ps1')
    . (Join-Path $repoRoot 'tools/lib/PfbCmdletParamTools.ps1')
    $script:buildScript = Join-Path $repoRoot 'tools/Build-PfbFieldCmdletMap.ps1'

    $script:specsDir = Join-Path $TestDrive 'specs'
    New-Item -ItemType Directory -Path $specsDir -Force | Out-Null

    # Two versions: v1 introduces both a stable field (present unchanged in both versions)
    # and a field whose value set changes between versions (must NOT be recommended
    # ValidateSet even though it has full history). v-only-in-2 exists only in the newer
    # version (short history) and must also fall back to ArgumentCompleter.
    $specV1 = @{
        components = @{
            schemas = @{
                Widget = @{
                    properties = @{
                        stable_field    = @{ description = 'Valid values are `a`, `b`.' }
                        changing_field  = @{ description = 'Valid values are `x`, `y`.' }
                        collision_field = @{ description = 'Valid values are `m`, `n`.' }
                    }
                }
                WidgetSpecial = @{
                    properties = @{
                        # Same wire name as Widget.collision_field, different value set,
                        # and "WidgetSpecial" still prefix-matches the "Widget" resource
                        # hint -- must produce 'collision', not a guessed pick.
                        collision_field = @{ description = 'Valid values are `m`, `o`.' }
                    }
                }
                OtherThing = @{
                    properties = @{
                        # Real field, but under a schema the "Widget" hint never matches --
                        # must produce 'not-found-in-resource', not a false match.
                        elsewhere_field = @{ description = 'Valid values are `q`, `r`.' }
                    }
                }
            }
            # Reproduces the real Get-PfbArraySpace -Type bug pattern: Kind='parameter'
            # records are keyed by an OpenAPI components.parameters dictionary name with
            # NO relationship to the owning resource/cmdlet, so the resource-hint filter
            # (built for schema keys) can never match them. Two distinct
            # components.parameters definitions can share the same wire "name" -- if
            # they disagree on value set, the field is genuinely ambiguous (collision);
            # if they agree, it's safe to resolve regardless of which definition this
            # cmdlet's endpoint actually references (matched).
            parameters = @{
                ParamKindAmbiguousA  = @{ name = 'param_kind_ambiguous';  description = 'Valid values are `t1`, `t2`.' }
                ParamKindAmbiguousB  = @{ name = 'param_kind_ambiguous';  description = 'Valid values are `t1`, `t3`.' }
                ParamKindConsistentA = @{ name = 'param_kind_consistent'; description = 'Valid values are `k1`, `k2`.' }
                ParamKindConsistentB = @{ name = 'param_kind_consistent'; description = 'Valid values are `k1`, `k2`.' }
                # Reproduces the real Get-PfbArraySpace -Type bug exactly: two
                # components.parameters definitions share wire name 'endpoint_field' with
                # DIFFERENT value sets (ambiguous on their own), but one specific endpoint
                # (GET /widgets/endpoint below) inline-defines the SAME field with a value
                # set matching EndpointFieldA -- an inline-parameter record keyed to that
                # exact endpoint, which must resolve the field despite the param-kind
                # ambiguity, not report 'collision'.
                EndpointFieldA = @{ name = 'endpoint_field'; description = 'Valid values are `e1`, `e2`.' }
                EndpointFieldB = @{ name = 'endpoint_field'; description = 'Valid values are `e1`, `e3`.' }
            }
        }
        paths = @{
            '/api/1.0/widgets/endpoint' = @{
                get = @{
                    parameters = @(
                        @{ name = 'endpoint_field'; 'in' = 'query'; description = 'Valid values are `e1`, `e2`.' }
                    )
                }
            }
        }
    }
    $specV2 = @{
        components = @{
            schemas = @{
                Widget = @{
                    properties = @{
                        stable_field    = @{ description = 'Valid values are `a`, `b`.' }
                        changing_field  = @{ description = 'Valid values are `x`, `y`, `z`.' }
                        new_in_v2       = @{ description = 'Valid values are `p`, `q`.' }
                        collision_field = @{ description = 'Valid values are `m`, `n`.' }
                    }
                }
                WidgetSpecial = @{
                    properties = @{
                        collision_field = @{ description = 'Valid values are `m`, `o`.' }
                    }
                }
                OtherThing = @{
                    properties = @{
                        elsewhere_field = @{ description = 'Valid values are `q`, `r`.' }
                    }
                }
            }
            parameters = @{
                ParamKindAmbiguousA  = @{ name = 'param_kind_ambiguous';  description = 'Valid values are `t1`, `t2`.' }
                ParamKindAmbiguousB  = @{ name = 'param_kind_ambiguous';  description = 'Valid values are `t1`, `t3`.' }
                ParamKindConsistentA = @{ name = 'param_kind_consistent'; description = 'Valid values are `k1`, `k2`.' }
                ParamKindConsistentB = @{ name = 'param_kind_consistent'; description = 'Valid values are `k1`, `k2`.' }
                # Reproduces the real Get-PfbArraySpace -Type bug exactly: two
                # components.parameters definitions share wire name 'endpoint_field' with
                # DIFFERENT value sets (ambiguous on their own), but one specific endpoint
                # (GET /widgets/endpoint below) inline-defines the SAME field with a value
                # set matching EndpointFieldA -- an inline-parameter record keyed to that
                # exact endpoint, which must resolve the field despite the param-kind
                # ambiguity, not report 'collision'.
                EndpointFieldA = @{ name = 'endpoint_field'; description = 'Valid values are `e1`, `e2`.' }
                EndpointFieldB = @{ name = 'endpoint_field'; description = 'Valid values are `e1`, `e3`.' }
            }
        }
        paths = @{
            '/api/1.1/widgets/endpoint' = @{
                get = @{
                    parameters = @(
                        @{ name = 'endpoint_field'; 'in' = 'query'; description = 'Valid values are `e1`, `e2`.' }
                    )
                }
            }
        }
    }
    $specV1 | ConvertTo-Json -Depth 20 | Set-Content -Path (Join-Path $specsDir 'fb1.0.json')
    $specV2 | ConvertTo-Json -Depth 20 | Set-Content -Path (Join-Path $specsDir 'fb1.1.json')

    $script:publicDir = Join-Path $TestDrive 'Public'
    New-Item -ItemType Directory -Path $publicDir -Force | Out-Null
    # Cmdlet is named "New-PfbWidget" (not "New-PfbFixtureWidget") deliberately: the
    # resource-hint resolver strips the "New-Pfb" verb prefix to get "Widget", which must
    # prefix-match the fixture spec's "Widget.stable_field" etc. schema keys below.
    Set-Content -Path (Join-Path $publicDir 'New-PfbWidget.ps1') -Value @'
function New-PfbWidget {
    param(
        [Parameter()] [string]$StableField,
        [Parameter()] [string]$ChangingField,
        [Parameter()] [string]$NewInV2,
        [Parameter()] [string]$CollisionField,
        [Parameter()] [string]$ElsewhereField,
        [Parameter()] [string]$NoSpecField,
        [Parameter()] [string]$ParamKindField,
        [Parameter()] [string]$ParamKindConsistentField,
        [Parameter()] [string]$EndpointField,
        [Parameter()] [PSCustomObject]$Array
    )
    $body = @{}
    if ($StableField)     { $body["stable_field"]     = $StableField }
    if ($ChangingField)   { $body["changing_field"]   = $ChangingField }
    if ($NewInV2)          { $body["new_in_v2"]        = $NewInV2 }
    if ($CollisionField)  { $body["collision_field"]  = $CollisionField }
    if ($ElsewhereField)  { $body["elsewhere_field"]  = $ElsewhereField }
    if ($NoSpecField)      { $body["totally_unknown_field"] = $NoSpecField }
    if ($ParamKindField)   { $body["param_kind_ambiguous"] = $ParamKindField }
    if ($ParamKindConsistentField) { $body["param_kind_consistent"] = $ParamKindConsistentField }
    $queryParams = @{}
    if ($EndpointField) { $queryParams["endpoint_field"] = $EndpointField }
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'widgets/endpoint' -Body $body -QueryParams $queryParams
}
'@

    $script:outputDir = Join-Path $TestDrive 'output'
    $script:manifestPath = Join-Path $outputDir 'map.json'
    $script:reportPath = Join-Path $outputDir 'report.md'

    & $buildScript -SpecsDirectory $specsDir -PublicDirectory $publicDir -OutputPath $manifestPath -ReportPath $reportPath
    $script:manifest = Get-Content -Path $manifestPath -Raw | ConvertFrom-Json -Depth 20
}

Describe 'Build-PfbFieldCmdletMap' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
    It 'recommends ValidateSet only for a field with full version history and no value-set changes' {
        $rec = $manifest.entries | Where-Object { $_.parameter -eq 'StableField' }
        $rec.status | Should -Be 'matched'
        $rec.stableSinceOldestVersion | Should -BeTrue
        $rec.recommendation | Should -Be 'ValidateSet'
    }

    It 'recommends ArgumentCompleter for a field with full history but a value-set change' {
        $rec = $manifest.entries | Where-Object { $_.parameter -eq 'ChangingField' }
        $rec.status | Should -Be 'matched'
        $rec.stableSinceOldestVersion | Should -BeFalse
        $rec.recommendation | Should -Be 'ArgumentCompleter'
    }

    It 'recommends ArgumentCompleter for a field introduced only in the newest version' {
        $rec = $manifest.entries | Where-Object { $_.parameter -eq 'NewInV2' }
        $rec.status | Should -Be 'matched'
        $rec.stableSinceOldestVersion | Should -BeFalse
        $rec.recommendation | Should -Be 'ArgumentCompleter'
    }

    It 'writes the reconciliation-style Markdown report' {
        Test-Path $reportPath | Should -BeTrue
        (Get-Content $reportPath -Raw) | Should -Match 'ValidateSet'
    }

    It 'includes a Summary section with correct per-status counts for the fixture set' {
        $reportText = Get-Content $reportPath -Raw
        $reportText | Should -Match '## Summary'
        # Fixture distribution: matched = StableField, ChangingField, NewInV2,
        # ParamKindConsistentField, EndpointField (5); collision = CollisionField,
        # ParamKindField (2); not-found-in-resource = ElsewhereField (1);
        # no-spec-enum-found = NoSpecField (1).
        $reportText | Should -Match '- matched: 5'
        $reportText | Should -Match '- collision: 2'
        $reportText | Should -Match '- not-found-in-resource: 1'
        $reportText | Should -Match '- no-spec-enum-found: 1'
    }

    It 'does not emit the zero-matched note when matched candidates exist' {
        (Get-Content $reportPath -Raw) | Should -Not -Match 'No `matched` candidates this run'
    }

    It 'omits no-spec-enum-found rows from the detailed table but keeps matched/collision/not-found-in-resource rows' {
        $reportText = Get-Content $reportPath -Raw
        $reportText | Should -Not -Match '\| `New-PfbWidget` \| `-NoSpecField` \|'
        $reportText | Should -Match '\| `New-PfbWidget` \| `-StableField` \|'
        $reportText | Should -Match '\| `New-PfbWidget` \| `-CollisionField` \|'
        $reportText | Should -Match '\| `New-PfbWidget` \| `-ElsewhereField` \|'
    }

    It 'classifies a wire name matching multiple hinted schemas with different value sets as collision, not a guess' {
        $rec = $manifest.entries | Where-Object { $_.parameter -eq 'CollisionField' }
        $rec.status | Should -Be 'collision'
        $rec.recommendation | Should -BeNullOrEmpty
        $rec.matchedKey | Should -BeNullOrEmpty
    }

    It 'classifies a wire name found only under an unrelated schema as not-found-in-resource, not a false match' {
        $rec = $manifest.entries | Where-Object { $_.parameter -eq 'ElsewhereField' }
        $rec.status | Should -Be 'not-found-in-resource'
        $rec.recommendation | Should -BeNullOrEmpty
    }

    It 'classifies a wire name absent from the spec entirely as no-spec-enum-found' {
        $rec = $manifest.entries | Where-Object { $_.parameter -eq 'NoSpecField' }
        $rec.status | Should -Be 'no-spec-enum-found'
        $rec.recommendation | Should -BeNullOrEmpty
    }

    It 'classifies a parameter-kind wire name with disagreeing value sets across components.parameters definitions as collision, not not-found-in-resource' {
        $rec = $manifest.entries | Where-Object { $_.parameter -eq 'ParamKindField' }
        $rec.status | Should -Be 'collision'
        $rec.recommendation | Should -BeNullOrEmpty
        $rec.matchedKey | Should -BeNullOrEmpty
    }

    It 'resolves a parameter-kind wire name to matched when every components.parameters definition sharing it agrees on the same value set' {
        $rec = $manifest.entries | Where-Object { $_.parameter -eq 'ParamKindConsistentField' }
        $rec.status | Should -Be 'matched'
        $rec.specValues | Should -Be @('k1', 'k2')
    }

    It 'resolves the real Get-PfbArraySpace -Type shape: an exact inline-parameter endpoint match overrides an otherwise-ambiguous parameter-kind wire name' {
        # EndpointFieldA/EndpointFieldB disagree on value set (like Type/Type_for_performance)
        # -- would be 'collision' on their own -- but New-PfbWidget's -EndpointField resolves
        # to exactly one Invoke-PfbApiRequest call (GET widgets/endpoint), matching an
        # inline-parameter record keyed to that exact endpoint, which settles it.
        $rec = $manifest.entries | Where-Object { $_.parameter -eq 'EndpointField' }
        $rec.status | Should -Be 'matched'
        $rec.specValues | Should -Be @('e1', 'e2')
        $rec.stableSinceOldestVersion | Should -BeTrue
        $rec.recommendation | Should -Be 'ValidateSet'
    }

    It 'still reports collision for an ambiguous parameter-kind wire name when no inline-parameter record matches this cmdlet''s own endpoint' {
        # ParamKindField's cmdlet (New-PfbWidget) DOES now resolve an Endpoint/Method (GET
        # widgets/endpoint, shared with -EndpointField above) -- but no inline-parameter
        # record exists keyed "GET widgets/endpoint#param_kind_ambiguous", so the exact-match
        # override never applies here and the pre-existing ambiguous-collision behavior for
        # parameter-kind records must still hold.
        $rec = $manifest.entries | Where-Object { $_.parameter -eq 'ParamKindField' }
        $rec.status | Should -Be 'collision'
        $rec.recommendation | Should -BeNullOrEmpty
    }
}

Describe 'Every inventory row lands in exactly one of five buckets (issue #141 Task 4, Step 8)' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
    # Before Task 4 this script had three buckets and no reconciliation: a row whose Surface
    # it had not been taught was filtered out by all three `Where-Object`s and vanished from
    # the report without a word. That is the quietest possible failure, and the two
    # non-applicable surfaces Task 4 adds are exactly the kind of value that would have hit
    # it. The fixture tree below deliberately populates all five buckets at once so the
    # partition assertion has something to be wrong about.

    BeforeAll {
        $script:partPublicDir = Join-Path $TestDrive 'PublicPartition'
        New-Item -ItemType Directory -Path $partPublicDir -Force | Out-Null

        # Buckets 1 and 2: a typed parameter with no ValidateSet (reported) and one with a
        # ValidateSet (deliberately reported nowhere -- this script recommends ADDING one).
        Set-Content -Path (Join-Path $partPublicDir 'New-PfbPartitionWidget.ps1') -Value @'
function New-PfbPartitionWidget {
    param(
        [Parameter()] [string]$StableField,
        [Parameter()] [ValidateSet('x', 'y')] [string]$ValidatedField,
        [Parameter()] [PSCustomObject]$Array
    )
    $body = @{}
    if ($StableField)    { $body["stable_field"]   = $StableField }
    if ($ValidatedField) { $body["changing_field"] = $ValidatedField }
    Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'widgets' -Body $body
}
'@

        # Bucket 3: typed, unresolvable, and no -Attributes escape hatch.
        Set-Content -Path (Join-Path $partPublicDir 'Get-PfbPartitionUnresolved.ps1') -Value @'
function Get-PfbPartitionUnresolved {
    param([Parameter()] [string]$Mystery, [Parameter()] [PSCustomObject]$Array)
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'widgets'
}
'@

        # Bucket 4: same unresolvable shape, but an -Attributes escape hatch exists.
        Set-Content -Path (Join-Path $partPublicDir 'Get-PfbPartitionAttributed.ps1') -Value @'
function Get-PfbPartitionAttributed {
    param([Parameter()] [string]$Mystery, [Parameter()] [hashtable]$Attributes, [Parameter()] [PSCustomObject]$Array)
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'widgets'
}
'@

        # Bucket 5a: NotWireParameter. The function is named Remove-PfbBucket on purpose --
        # the surface is keyed on the audited 'Cmdlet|Parameter' identity, never on the
        # parameter's name, so a fixture called anything else could not reach this branch and
        # a test that renamed it would silently stop testing it.
        Set-Content -Path (Join-Path $partPublicDir 'Remove-PfbBucket.ps1') -Value @'
function Remove-PfbBucket {
    param([Parameter()] [string]$Name, [Parameter()] [switch]$Eradicate, [Parameter()] [PSCustomObject]$Array)
    if (-not $Eradicate) { throw 'refusing without -Eradicate' }
    $queryParams = @{}
    $queryParams["names"] = $Name
    Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'buckets' -QueryParams $queryParams
}
'@

        # Bucket 5b: OutsideStandardRequest -- no Invoke-PfbApiRequest call anywhere.
        Set-Content -Path (Join-Path $partPublicDir 'Set-PfbPartitionContext.ps1') -Value @'
function Set-PfbPartitionContext {
    param([Parameter()] [string]$Context)
    $script:PfbPartitionContext = $Context
}
'@

        $script:partOutput = Join-Path $TestDrive 'partitionOutput/map.json'
        $script:partReport = Join-Path $TestDrive 'partitionOutput/report.md'
        & $buildScript -SpecsDirectory $specsDir -PublicDirectory $partPublicDir -OutputPath $partOutput -ReportPath $partReport
        $script:partManifest = Get-Content -Path $partOutput -Raw | ConvertFrom-Json -Depth 20
        $script:partInventory = @(Get-PfbCmdletParameterInventory -PublicDirectory $partPublicDir)

        function script:Get-PfbPartitionIdentity {
            param($Rows, [string]$CmdletProperty = 'cmdlet', [string]$ParameterProperty = 'parameter')
            @($Rows | ForEach-Object { '{0}|{1}' -f $_.$CmdletProperty, $_.$ParameterProperty })
        }
    }

    It 'accounts for every row exactly once across the four emitted buckets plus the deliberately-unemitted fifth' {
        $emitted = @()
        $emitted += Get-PfbPartitionIdentity -Rows $partManifest.entries
        $emitted += Get-PfbPartitionIdentity -Rows $partManifest.attributesOnly
        $emitted += Get-PfbPartitionIdentity -Rows $partManifest.typedUnresolved
        $emitted += Get-PfbPartitionIdentity -Rows $partManifest.notApplicable
        $unemitted = Get-PfbPartitionIdentity -Rows @($partInventory | Where-Object { $_.Surface -eq 'Typed' -and $_.HasValidateSet }) -CmdletProperty 'Cmdlet' -ParameterProperty 'Parameter'

        $all = @($emitted) + @($unemitted)
        $expected = Get-PfbPartitionIdentity -Rows $partInventory -CmdletProperty 'Cmdlet' -ParameterProperty 'Parameter'

        # Count first: set equality alone would pass if one row were classified into two
        # buckets, which is the other half of "exactly one".
        $all.Count | Should -Be $expected.Count
        @($all | Sort-Object) | Should -Be @($expected | Sort-Object)
    }

    It 'populates the <Bucket> bucket, so the reconciliation above is not vacuous' -ForEach @(
        @{ Bucket = 'entries' }
        @{ Bucket = 'attributesOnly' }
        @{ Bucket = 'typedUnresolved' }
        @{ Bucket = 'notApplicable' }
    ) {
        @($partManifest.$Bucket).Count | Should -BeGreaterThan 0
    }

    It 'keeps the non-applicable rows out of typedUnresolved and records which reason applies to each' {
        $notApplicable = @($partManifest.notApplicable)
        $notApplicable.Count | Should -Be 2
        ($notApplicable | Where-Object { $_.cmdlet -eq 'Remove-PfbBucket' }).surface | Should -Be 'NotWireParameter'
        ($notApplicable | Where-Object { $_.cmdlet -eq 'Set-PfbPartitionContext' }).surface | Should -Be 'OutsideStandardRequest'

        # The control for the two exclusions below: typedUnresolved is populated, so
        # -Not -Contain is testing separation and not an empty list.
        @($partManifest.typedUnresolved).Count | Should -Be 1
        (Get-PfbPartitionIdentity -Rows $partManifest.typedUnresolved) | Should -Not -Contain 'Remove-PfbBucket|Eradicate'
        (Get-PfbPartitionIdentity -Rows $partManifest.typedUnresolved) | Should -Not -Contain 'Set-PfbPartitionContext|Context'
    }

    It 'gives the non-applicable rows their own Markdown heading, with the reason on each line' {
        $text = Get-Content -Path $partReport -Raw
        $text | Should -Match '## Not a wire field \(nothing to inspect\): 2'
        $text | Should -Match '- `Remove-PfbBucket -Eradicate` \(NotWireParameter\)'
        $text | Should -Match '- `Set-PfbPartitionContext -Context` \(OutsideStandardRequest\)'
        # And the section it must NOT have been folded into still reports its own single row.
        $text | Should -Match '## Typed but unresolved wire name \(needs manual inspection\): 1'
    }

    It 'emits a typed parameter that already has a ValidateSet nowhere at all' {
        $withValidateSet = @($partInventory | Where-Object { $_.Surface -eq 'Typed' -and $_.HasValidateSet })
        $withValidateSet.Count | Should -Be 1 -Because 'the fixture must actually contain one, or this test proves nothing'
        (Get-PfbPartitionIdentity -Rows $partManifest.entries) | Should -Not -Contain 'New-PfbPartitionWidget|ValidatedField'
        (Get-PfbPartitionIdentity -Rows $partManifest.attributesOnly) | Should -Not -Contain 'New-PfbPartitionWidget|ValidatedField'
        (Get-PfbPartitionIdentity -Rows $partManifest.typedUnresolved) | Should -Not -Contain 'New-PfbPartitionWidget|ValidatedField'
        (Get-PfbPartitionIdentity -Rows $partManifest.notApplicable) | Should -Not -Contain 'New-PfbPartitionWidget|ValidatedField'
        (Get-Content -Path $partReport -Raw) | Should -Not -Match 'ValidatedField'
    }
}

Describe 'The partition assertion refuses a Surface the script has not been taught (issue #141 Task 4, Step 8)' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
    # No Public/ fixture can produce an unknown Surface -- the ladder only ever emits the five
    # declared values -- so the only honest way to exercise the assertion is to replace the
    # inventory function the script depends on. The script dot-sources tools/lib/ relative to
    # its OWN location, which would overwrite any override made from here, so the whole
    # script + lib pair is copied to TestDrive and the override appended to the copied lib.

    BeforeAll {
        $script:shimDir = Join-Path $TestDrive 'toolsShim'
        New-Item -ItemType Directory -Path $shimDir -Force | Out-Null
        Copy-Item -Path (Join-Path $repoRoot 'tools/lib') -Destination $shimDir -Recurse -Force
        Copy-Item -Path $buildScript -Destination $shimDir -Force
        $script:shimScript = Join-Path $shimDir 'Build-PfbFieldCmdletMap.ps1'

        Add-Content -Path (Join-Path $shimDir 'lib/PfbCmdletParamTools.ps1') -Value @'

# --- issue #141 Task 4 test shim, appended by Tests/Build-PfbFieldCmdletMap.Tests.ps1 ---
function Get-PfbCmdletParameterInventory {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$PublicDirectory)
    return @([PSCustomObject]@{
            File = 'shim.ps1'; Line = 1; Cmdlet = 'Get-PfbShimmed'; Parameter = 'Zeta'
            HasValidateSet = $false; ValidateSetValues = $null
            WireName = $env:PFB_T4_SHIM_WIRENAME; TargetVariable = $null; WireSurface = $null
            Surface = $env:PFB_T4_SHIM_SURFACE; Endpoint = $null; Method = $null
        })
}
'@
        $script:shimOutput = Join-Path $TestDrive 'shimOutput/map.json'
        $script:shimReport = Join-Path $TestDrive 'shimOutput/report.md'
    }

    AfterAll {
        Remove-Item -Path Env:PFB_T4_SHIM_SURFACE -ErrorAction SilentlyContinue
        Remove-Item -Path Env:PFB_T4_SHIM_WIRENAME -ErrorAction SilentlyContinue
    }

    It 'throws, naming the counts, when a row carries a Surface no bucket claims' {
        $env:PFB_T4_SHIM_SURFACE = 'SomethingNew'
        $env:PFB_T4_SHIM_WIRENAME = ''
        { & $shimScript -SpecsDirectory $specsDir -PublicDirectory $publicDir -OutputPath $shimOutput -ReportPath $shimReport } |
            Should -Throw -ExpectedMessage '*Inventory partition is incomplete: 1 rows in, 0 classified*'
    }

    It 'builds cleanly through the same shim when the row carries a Surface a bucket does claim' {
        # The control. Without it the test above would still pass against a script that threw
        # unconditionally, or one whose copied-and-shimmed harness was broken in some way that
        # had nothing to do with the Surface value.
        $env:PFB_T4_SHIM_SURFACE = 'Typed'
        $env:PFB_T4_SHIM_WIRENAME = 'stable_field'
        { & $shimScript -SpecsDirectory $specsDir -PublicDirectory $publicDir -OutputPath $shimOutput -ReportPath $shimReport } |
            Should -Not -Throw
        (Get-Content -Path $shimOutput -Raw | ConvertFrom-Json -Depth 20).entries.parameter | Should -Be 'Zeta'
    }
}

Describe 'Build-PfbFieldCmdletMap (real generated artifacts, skips gracefully if absent)' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
    It 'produces a manifest against the real Public/ tree and tools/specs/ cache' {
        $realSpecsDir = Join-Path $repoRoot 'tools/specs'
        $realPublicDir = Join-Path $repoRoot 'Public'
        if (-not (Test-Path $realSpecsDir) -or -not (Get-ChildItem $realSpecsDir -Filter 'fb*.json' -ErrorAction SilentlyContinue)) {
            Set-ItResult -Skipped -Because 'tools/specs/ not present locally (gitignored, run Update-PfbApiSpecs.ps1 first)'
            return
        }

        $realOutput = Join-Path $TestDrive 'realOutput/map.json'
        $realReport = Join-Path $TestDrive 'realOutput/report.md'
        & $buildScript -SpecsDirectory $realSpecsDir -PublicDirectory $realPublicDir -OutputPath $realOutput -ReportPath $realReport
        Test-Path $realOutput | Should -BeTrue
    }
}
