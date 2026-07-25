#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Unit tests for tools/lib/PfbCmdletParamTools.ps1 — the AST-based cmdlet parameter
    inventory used by tools/Build-PfbFieldCmdletMap.ps1.
.DESCRIPTION
    Runs against a small synthetic Public/-shaped directory under TestDrive, built from
    real patterns observed in this repo's actual cmdlets (New-PfbAlertWatcher's simple
    $body['wire_name'] = $Param assignment, New-PfbNetworkInterface's -Attributes escape
    hatch and its unresolvable $AttachedServers | ForEach-Object {...} pipeline, and
    Get-PfbArrayPerformance's $queryParams assignment) — no dependency on the real Public/
    tree so the test stays stable if cmdlets change.
#>

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'tools/lib/PfbCmdletParamTools.ps1')

    $script:fixtureDir = Join-Path $TestDrive 'Public/Fixture'
    New-Item -ItemType Directory -Path $fixtureDir -Force | Out-Null

    Set-Content -Path (Join-Path $fixtureDir 'New-PfbFixtureAlertWatcher.ps1') -Value @'
function New-PfbFixtureAlertWatcher {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter()]
        [ValidateSet('info', 'warning', 'critical')]
        [string]$MinimumSeverity,

        [Parameter()] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )

    if ($Attributes) { $body = $Attributes }
    else {
        $body = @{}
        if ($MinimumSeverity) { $body['minimum_notification_severity'] = $MinimumSeverity }
    }
}
'@

    Set-Content -Path (Join-Path $fixtureDir 'New-PfbFixtureNetworkInterface.ps1') -Value @'
function New-PfbFixtureNetworkInterface {
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = "Individual")]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter(ParameterSetName = "Individual")]
        [ValidateSet("data", "egress-only", "management", "replication", "support")]
        [string[]]$Services,

        [Parameter(ParameterSetName = "Individual")]
        [string[]]$AttachedServers,

        [Parameter(Mandatory, ParameterSetName = "Attributes")]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )

    if ($PSCmdlet.ParameterSetName -eq "Attributes") {
        $body = $Attributes
    }
    else {
        $body = @{}
        if ($Services) { $body["services"] = @($Services) }
        if ($AttachedServers) {
            $body["attached_servers"] = @($AttachedServers | ForEach-Object { @{ name = $_ } })
        }
    }
}
'@

    Set-Content -Path (Join-Path $fixtureDir 'Get-PfbFixtureArrayPerformance.ps1') -Value @'
function Get-PfbFixtureArrayPerformance {
    [CmdletBinding()]
    param(
        [Parameter()] [PSCustomObject]$Array,

        [Parameter()]
        [string]$Protocol,

        [Parameter()]
        [int64]$Resolution,

        [Parameter()]
        [datetime]$StartTime
    )

    $queryParams = @{}
    if ($Protocol)   { $queryParams["protocol"]   = $Protocol }
    if ($Resolution) { $queryParams["resolution"] = $Resolution }
    # Deliberately NOT a simple "$queryParams[key] = $Param" assignment -- string
    # interpolation is a real pattern this repo does not currently use, but the resolver
    # must not guess through it. No -Attributes escape hatch exists on this cmdlet either,
    # so this must surface as TypedUnresolved, not silently dropped or force-matched.
    if ($StartTime) { $queryParams["start_time"] = "$StartTime" }

    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'arrays/performance' -QueryParams $queryParams -AutoPaginate
}
'@

    # Real Get-PfbArraySpace shape: exactly one Invoke-PfbApiRequest call, so -Type's
    # $queryParams assignment resolves to exactly one (Method, Endpoint) pair.
    Set-Content -Path (Join-Path $fixtureDir 'Get-PfbFixtureArraySpace.ps1') -Value @'
function Get-PfbFixtureArraySpace {
    [CmdletBinding()]
    param(
        [Parameter()] [PSCustomObject]$Array,
        [Parameter()] [string]$Type
    )
    $queryParams = @{}
    if ($Type) { $queryParams['type'] = $Type }
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'arrays/space' -QueryParams $queryParams -AutoPaginate
}
'@

    # Real Get-PfbNode shape: the SAME $queryParams variable is reused across two calls
    # against two genuinely different endpoints (a try/catch model-support fallback) --
    # must resolve to $null, not a guessed pick of either endpoint.
    Set-Content -Path (Join-Path $fixtureDir 'Get-PfbFixtureNode.ps1') -Value @'
function Get-PfbFixtureNode {
    [CmdletBinding()]
    param(
        [Parameter()] [PSCustomObject]$Array,
        [Parameter()] [string]$Filter
    )
    $queryParams = @{}
    if ($Filter) { $queryParams['filter'] = $Filter }
    try {
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'nodes' -QueryParams $queryParams -AutoPaginate
    } catch {
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'blades' -QueryParams $queryParams -AutoPaginate
    }
}
'@

    # Real Get-PfbPolicyAllMember shape: a plural wire name built by joining a string-array
    # parameter, not assigning it directly or wrapping it in @(...).
    Set-Content -Path (Join-Path $fixtureDir 'Get-PfbFixturePolicyAllMember.ps1') -Value @'
function Get-PfbFixturePolicyAllMember {
    [CmdletBinding()]
    param(
        [Parameter()] [PSCustomObject]$Array,
        [Parameter()] [string[]]$MemberName
    )
    $queryParams = @{}
    if ($MemberName) { $queryParams['member_names'] = $MemberName -join ',' }
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'policies/members' -QueryParams $queryParams -AutoPaginate
}
'@

    # Real Get-PfbFileSystemSession shape: a switch's mere presence is keyed to a
    # hardcoded string literal, not derived from the switch's own value at all.
    Set-Content -Path (Join-Path $fixtureDir 'Get-PfbFixtureFileSystemSession.ps1') -Value @'
function Get-PfbFixtureFileSystemSession {
    [CmdletBinding()]
    param(
        [Parameter()] [PSCustomObject]$Array,
        [Parameter()] [switch]$TotalOnly
    )
    $queryParams = @{}
    if ($TotalOnly) { $queryParams['total_only'] = 'true' }
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'file-system-sessions' -QueryParams $queryParams -AutoPaginate
}
'@

    # Real cross-file idiom (130/130 files that use it at all, byte-for-byte identical):
    # accumulate into a list across `process`, then join it into the wire name in `end`.
    Set-Content -Path (Join-Path $fixtureDir 'Get-PfbFixtureFileSystemByName.ps1') -Value @'
function Get-PfbFixtureFileSystemByName {
    [CmdletBinding()]
    param(
        [Parameter()] [PSCustomObject]$Array,
        [Parameter(ValueFromPipeline)] [string[]]$Name
    )
    begin {
        $allNames = [System.Collections.Generic.List[string]]::new()
        $queryParams = @{}
    }
    process {
        if ($Name) {
            foreach ($n in $Name) {
                $allNames.Add($n)
            }
        }
    }
    end {
        if ($allNames.Count -gt 0) { $queryParams['names'] = $allNames -join ',' }
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'file-systems' -QueryParams $queryParams -AutoPaginate
    }
}
'@

    # Ambiguous-accumulator case: the SAME accumulator is fed by two different parameters'
    # foreach loops -- must bail to TypedUnresolved for both, never guess which one "owns"
    # the eventual wire name.
    Set-Content -Path (Join-Path $fixtureDir 'Get-PfbFixtureSharedAccumulator.ps1') -Value @'
function Get-PfbFixtureSharedAccumulator {
    [CmdletBinding()]
    param(
        [Parameter()] [PSCustomObject]$Array,
        [Parameter()] [string[]]$FirstNames,
        [Parameter()] [string[]]$SecondNames
    )
    $allNames = [System.Collections.Generic.List[string]]::new()
    $queryParams = @{}
    foreach ($n in $FirstNames) { $allNames.Add($n) }
    foreach ($n in $SecondNames) { $allNames.Add($n) }
    if ($allNames.Count -gt 0) { $queryParams['names'] = $allNames -join ',' }
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'shared' -QueryParams $queryParams -AutoPaginate
}
'@

    # --- Add-PfbCommonQueryParams (issue #32/#33) fixtures -----------------------------
    # Real Get-PfbBucketPerformance shape: -Name/-Id handed straight to the shared helper,
    # and -Filter/-Sort/-Limit/-TotalOnly reaching the wire only via $PSBoundParameters.
    Set-Content -Path (Join-Path $fixtureDir 'Get-PfbFixtureHelperDirect.ps1') -Value @'
function Get-PfbFixtureHelperDirect {
    [CmdletBinding()]
    param(
        [Parameter()] [PSCustomObject]$Array,
        [Parameter()] [string[]]$Name,
        [Parameter()] [string[]]$Id,
        [Parameter()] [string]$Filter,
        [Parameter()] [string]$Sort,
        [Parameter()] [int]$Limit,
        [Parameter()] [switch]$TotalOnly
    )
    $queryParams = @{}
    Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters -Names $Name -Ids $Id
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'helper-direct' -QueryParams $queryParams -AutoPaginate
}
'@

    # Real Get-PfbFileSystem shape: the helper receives the `process`-block accumulators,
    # not the parameters -- so resolution must go parameter -> accumulator -> helper argument.
    Set-Content -Path (Join-Path $fixtureDir 'Get-PfbFixtureHelperAccumulator.ps1') -Value @'
function Get-PfbFixtureHelperAccumulator {
    [CmdletBinding()]
    param(
        [Parameter()] [PSCustomObject]$Array,
        [Parameter(ValueFromPipeline)] [string[]]$Name,
        [Parameter()] [string[]]$Id
    )
    begin {
        $allNames = [System.Collections.Generic.List[string]]::new()
        $allIds = [System.Collections.Generic.List[string]]::new()
    }
    process {
        if ($Name) { foreach ($n in $Name) { $allNames.Add($n) } }
        if ($Id)   { foreach ($i in $Id)   { $allIds.Add($i) } }
    }
    end {
        $queryParams = @{}
        Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters -Names $allNames -Ids $allIds
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'helper-accumulator' -QueryParams $queryParams -AutoPaginate
    }
}
'@

    # Real Get-PfbObjectStoreAccessPolicyRule shape: the genuinely MIXED case. -Name goes
    # through the helper's generic 'names', while -PolicyName deliberately kept its own
    # explicit non-generic 'policy_names' line after the helper call (issue #32's design).
    # Both must resolve, and the explicit line must not be shadowed by the helper.
    Set-Content -Path (Join-Path $fixtureDir 'Get-PfbFixtureHelperMixed.ps1') -Value @'
function Get-PfbFixtureHelperMixed {
    [CmdletBinding()]
    param(
        [Parameter()] [PSCustomObject]$Array,
        [Parameter(ValueFromPipeline)] [string[]]$PolicyName,
        [Parameter()] [string[]]$Name,
        [Parameter()] [string]$Filter
    )
    begin {
        $allPolicyNames = [System.Collections.Generic.List[string]]::new()
        $allNames = [System.Collections.Generic.List[string]]::new()
    }
    process {
        if ($PolicyName) { foreach ($n in $PolicyName) { $allPolicyNames.Add($n) } }
        if ($Name)       { foreach ($n in $Name)       { $allNames.Add($n) } }
    }
    end {
        $queryParams = @{}
        Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters -Names $allNames
        if ($allPolicyNames.Count -gt 0) { $queryParams['policy_names'] = $allPolicyNames -join ',' }
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'helper-mixed' -QueryParams $queryParams -AutoPaginate
    }
}
'@

    # Negative guard: the ByParameterName half of the mapping is only true because the helper
    # reads the CALLER's $PSBoundParameters. A call that does not forward it cannot be assumed
    # to map -Filter, so -Filter must stay unresolved rather than be credited to 'filter'.
    Set-Content -Path (Join-Path $fixtureDir 'Get-PfbFixtureHelperNoBoundParams.ps1') -Value @'
function Get-PfbFixtureHelperNoBoundParams {
    [CmdletBinding()]
    param(
        [Parameter()] [PSCustomObject]$Array,
        [Parameter()] [string]$Filter
    )
    $queryParams = @{}
    $someOtherDictionary = @{}
    Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $someOtherDictionary
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'helper-no-bound' -QueryParams $queryParams -AutoPaginate
}
'@

    # --- Hashtable-literal-initializer fixtures ---------------------------------------
    # Real New-PfbApiClient/New-PfbObjectStoreAccount shape: the wire key exists ONLY inside
    # a hashtable literal, never as a later $queryParams['names'] = ... index assignment.
    Set-Content -Path (Join-Path $fixtureDir 'New-PfbFixtureLiteralOnly.ps1') -Value @'
function New-PfbFixtureLiteralOnly {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)] [string]$Name,
        [Parameter()] [PSCustomObject]$Array
    )
    $queryParams = @{ 'names' = $Name }
    Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'literal-only' -QueryParams $queryParams
}
'@

    # Real New-PfbBucket/New-PfbFileSystem shape: a literal initializer AND later index
    # assignments into $body coexist in one cmdlet, against two different target variables.
    # Both key sets must resolve, each to its own target variable.
    Set-Content -Path (Join-Path $fixtureDir 'New-PfbFixtureLiteralMixed.ps1') -Value @'
function New-PfbFixtureLiteralMixed {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)] [string]$Name,
        [Parameter()] [string]$NewName,
        [Parameter()] [string]$Hostname,
        [Parameter()] [PSCustomObject]$Array
    )
    $queryParams = @{ 'names' = $Name }
    $body = @{ 'name' = $NewName }
    if ($Hostname) { $body['host_name'] = $Hostname }
    Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'literal-mixed' -Body $body -QueryParams $queryParams
}
'@

    # Real New-PfbWorkload/Remove-PfbWorkloadTag shape: the literal's value is an EXPRESSION
    # wrapping the parameter (@(...) or -join), not a bare variable reference.
    Set-Content -Path (Join-Path $fixtureDir 'New-PfbFixtureLiteralWrapped.ps1') -Value @'
function New-PfbFixtureLiteralWrapped {
    [CmdletBinding()]
    param(
        [Parameter()] [string[]]$Name,
        [Parameter()] [string[]]$Key,
        [Parameter()] [PSCustomObject]$Array
    )
    $queryParams = @{ 'names' = @($Name); 'keys' = $Key -join ',' }
    Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'literal-wrapped' -QueryParams $queryParams
}
'@

    # Real New-PfbQuotaGroup shape: a NESTED single-key sub-object inside a hashtable-literal
    # initializer. The wire field is the OUTER key ('group') -- never the inner 'name', which
    # would both mis-name the field and collide with every other sub-object's 'name'.
    Set-Content -Path (Join-Path $fixtureDir 'New-PfbFixtureNestedLiteral.ps1') -Value @'
function New-PfbFixtureNestedLiteral {
    [CmdletBinding()]
    param(
        [Parameter()] [string]$GroupName,
        [Parameter()] [int64]$Quota,
        [Parameter()] [PSCustomObject]$Array
    )
    $body = @{ group = @{ name = $GroupName }; quota = $Quota }
    Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'nested-literal' -Body $body
}
'@

    # Real New-PfbBucket/New-PfbFileSystem/New-PfbServer shape: a nested single-key reference
    # object keyed in by INDEX assignment. Covers, in order: the plain reference object; two
    # parameters legitimately resolving to the SAME outer key ('account' addressed by name and
    # by id -- correct, not a collision to suppress); a non-'name' inner key (real
    # New-PfbFileSystem: eradication_config = @{ eradication_mode = ... }); a plain sibling key
    # that must keep resolving directly; a MULTI-key sub-object, whose per-field ownership
    # cannot be attributed to one parameter; and two levels of nesting, which is not descended.
    Set-Content -Path (Join-Path $fixtureDir 'New-PfbFixtureNestedReference.ps1') -Value @'
function New-PfbFixtureNestedReference {
    [CmdletBinding()]
    param(
        [Parameter()] [string]$Account,
        [Parameter()] [string]$AccountId,
        [Parameter()] [string]$EradicationMode,
        [Parameter()] [string]$Versioning,
        [Parameter()] [string]$SourceName,
        [Parameter()] [string]$SourceId,
        [Parameter()] [string]$Deep,
        [Parameter()] [PSCustomObject]$Array
    )
    $body = @{}
    if ($Account)         { $body['account'] = @{ name = $Account } }
    if ($AccountId)       { $body['account'] = @{ id = $AccountId } }
    if ($EradicationMode) { $body['eradication_config'] = @{ eradication_mode = $EradicationMode } }
    if ($Versioning)      { $body['versioning'] = $Versioning }
    if ($SourceName -or $SourceId) { $body['source'] = @{ name = $SourceName; id = $SourceId } }
    if ($Deep)            { $body['outer'] = @{ middle = @{ name = $Deep } } }
    Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'nested-reference' -Body $body
}
'@

    $script:helperPath = Join-Path $repoRoot 'Private/Add-PfbCommonQueryParams.ps1'
    $script:inventory = Get-PfbCmdletParameterInventory -PublicDirectory $fixtureDir
}

Describe 'Get-PfbCmdletParameterInventory' {
    It 'always skips the Array parameter' {
        $inventory | Where-Object { $_.Parameter -eq 'Array' } | Should -BeNullOrEmpty
    }

    It 'always skips the Attributes parameter itself' {
        $inventory | Where-Object { $_.Parameter -eq 'Attributes' } | Should -BeNullOrEmpty
    }

    It 'records an existing ValidateSet and marks HasValidateSet true' {
        $rec = $inventory | Where-Object { $_.Cmdlet -eq 'New-PfbFixtureAlertWatcher' -and $_.Parameter -eq 'MinimumSeverity' }
        $rec.HasValidateSet | Should -BeTrue
        $rec.ValidateSetValues | Should -Be @('info', 'warning', 'critical')
    }

    It 'resolves a simple $body[wire_name] = $Param assignment' {
        $rec = $inventory | Where-Object { $_.Cmdlet -eq 'New-PfbFixtureAlertWatcher' -and $_.Parameter -eq 'MinimumSeverity' }
        $rec.WireName | Should -Be 'minimum_notification_severity'
        $rec.Surface | Should -Be 'Typed'
    }

    It 'resolves a simple $queryParams[wire_name] = $Param assignment' {
        $rec = $inventory | Where-Object { $_.Cmdlet -eq 'Get-PfbFixtureArrayPerformance' -and $_.Parameter -eq 'Protocol' }
        $rec.WireName | Should -Be 'protocol'
        $rec.Surface | Should -Be 'Typed'
    }

    It 'resolves an array parameter wrapped in @(...)' {
        $rec = $inventory | Where-Object { $_.Cmdlet -eq 'New-PfbFixtureNetworkInterface' -and $_.Parameter -eq 'Services' }
        $rec.WireName | Should -Be 'services'
        $rec.Surface | Should -Be 'Typed'
    }

    It 'classifies a parameter fed through a pipeline transform as AttributesOnly, not a guessed wire name' {
        # $AttachedServers is assigned via `@($AttachedServers | ForEach-Object { @{ name = $_ } })`
        # -- deliberately NOT matched by the simple-assignment resolver. Since this cmdlet also
        # has an -Attributes escape hatch, it must be classified AttributesOnly, not silently
        # dropped and not force-matched to a wrong wire name.
        $rec = $inventory | Where-Object { $_.Cmdlet -eq 'New-PfbFixtureNetworkInterface' -and $_.Parameter -eq 'AttachedServers' }
        $rec.WireName | Should -BeNullOrEmpty
        $rec.Surface | Should -Be 'AttributesOnly'
    }

    It 'resolves a parameter with no -Attributes escape hatch via a simple assignment' {
        $rec = $inventory | Where-Object { $_.Cmdlet -eq 'Get-PfbFixtureArrayPerformance' -and $_.Parameter -eq 'Resolution' }
        $rec.WireName | Should -Be 'resolution'
        $rec.Surface | Should -Be 'Typed'
    }

    It 'classifies a parameter with no -Attributes escape hatch and no resolvable assignment as TypedUnresolved' {
        $rec = $inventory | Where-Object { $_.Cmdlet -eq 'Get-PfbFixtureArrayPerformance' -and $_.Parameter -eq 'StartTime' }
        $rec.WireName | Should -BeNullOrEmpty
        $rec.Surface | Should -Be 'TypedUnresolved'
    }

    It 'resolves a parameter joined into a plural wire name via -join' {
        $rec = $inventory | Where-Object { $_.Cmdlet -eq 'Get-PfbFixturePolicyAllMember' -and $_.Parameter -eq 'MemberName' }
        $rec.WireName | Should -Be 'member_names'
        $rec.Surface | Should -Be 'Typed'
    }

    It 'resolves a [switch] parameter keyed to a hardcoded literal, guarded by if ($Param)' {
        $rec = $inventory | Where-Object { $_.Cmdlet -eq 'Get-PfbFixtureFileSystemSession' -and $_.Parameter -eq 'TotalOnly' }
        $rec.WireName | Should -Be 'total_only'
        $rec.Surface | Should -Be 'Typed'
    }

    It 'resolves a parameter traced through a foreach-accumulator-then-join pipeline' {
        $rec = $inventory | Where-Object { $_.Cmdlet -eq 'Get-PfbFixtureFileSystemByName' -and $_.Parameter -eq 'Name' }
        $rec.WireName | Should -Be 'names'
        $rec.Surface | Should -Be 'Typed'
    }

    It 'bails to TypedUnresolved when an accumulator is fed by more than one parameter (never guesses ownership)' {
        $first = $inventory | Where-Object { $_.Cmdlet -eq 'Get-PfbFixtureSharedAccumulator' -and $_.Parameter -eq 'FirstNames' }
        $second = $inventory | Where-Object { $_.Cmdlet -eq 'Get-PfbFixtureSharedAccumulator' -and $_.Parameter -eq 'SecondNames' }
        $first.WireName | Should -BeNullOrEmpty
        $first.Surface | Should -Be 'TypedUnresolved'
        $second.WireName | Should -BeNullOrEmpty
        $second.Surface | Should -Be 'TypedUnresolved'
    }
}

Describe 'Get-PfbWireNameForParameter' {
    It 'returns $null when the parameter name never appears on the right-hand side of a body/queryParams assignment' {
        $tokens = $null; $errs = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput(
            'function Test-Fixture { param([string]$Unused) $body = @{} }', [ref]$tokens, [ref]$errs)
        $funcAst = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | Select-Object -First 1
        Get-PfbWireNameForParameter -FunctionAst $funcAst -ParameterName 'Unused' | Should -BeNullOrEmpty
    }
}

Describe 'Get-PfbWireNameForParameter: switch-to-literal pattern' {
    It 'does NOT treat an unguarded literal assignment as switch-derived (false-positive guard)' {
        $tokens = $null; $errs = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput(
            'function Test-Fixture { param([switch]$Foo) $body = @{}; $body["bar"] = "literal" }', [ref]$tokens, [ref]$errs)
        $funcAst = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | Select-Object -First 1
        Get-PfbWireNameForParameter -FunctionAst $funcAst -ParameterName 'Foo' -IsSwitchParameter | Should -BeNullOrEmpty
    }

    It 'does NOT apply the switch-literal match when -IsSwitchParameter is not passed' {
        $tokens = $null; $errs = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput(
            'function Test-Fixture { param([switch]$Foo) if ($Foo) { $body["bar"] = "literal" } }', [ref]$tokens, [ref]$errs)
        $funcAst = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | Select-Object -First 1
        Get-PfbWireNameForParameter -FunctionAst $funcAst -ParameterName 'Foo' | Should -BeNullOrEmpty
    }
}

Describe 'Endpoint/Method resolution (Get-PfbEndpointForVariable, via the inventory)' {
    It 'resolves Endpoint/Method for a parameter whose variable feeds exactly one Invoke-PfbApiRequest call' {
        $rec = $inventory | Where-Object { $_.Cmdlet -eq 'Get-PfbFixtureArraySpace' -and $_.Parameter -eq 'Type' }
        $rec.Endpoint | Should -Be 'arrays/space'
        $rec.Method | Should -Be 'GET'
    }

    It 'leaves Endpoint/Method $null when the same variable feeds two calls with different endpoints (ambiguous, never guessed)' {
        $rec = $inventory | Where-Object { $_.Cmdlet -eq 'Get-PfbFixtureNode' -and $_.Parameter -eq 'Filter' }
        $rec.Endpoint | Should -BeNullOrEmpty
        $rec.Method | Should -BeNullOrEmpty
    }

    It 'leaves Endpoint/Method $null when there is no resolvable wire-name assignment at all' {
        $rec = $inventory | Where-Object { $_.Cmdlet -eq 'Get-PfbFixtureArrayPerformance' -and $_.Parameter -eq 'StartTime' }
        $rec.Endpoint | Should -BeNullOrEmpty
        $rec.Method | Should -BeNullOrEmpty
    }

    It 'directly returns $null from Get-PfbEndpointForVariable for a variable with zero matching Invoke-PfbApiRequest calls' {
        $tokens = $null; $errs = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput(
            'function Test-Fixture { param([string]$Unused) $queryParams = @{} }', [ref]$tokens, [ref]$errs)
        $funcAst = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | Select-Object -First 1
        Get-PfbEndpointForVariable -FunctionAst $funcAst -TargetVariable 'queryParams' | Should -BeNullOrEmpty
    }
}

Describe 'Add-PfbCommonQueryParams awareness (issue #32/#33)' {
    It 'resolves -Name/-Id handed straight to the helper as names/ids' {
        $name = $inventory | Where-Object { $_.Cmdlet -eq 'Get-PfbFixtureHelperDirect' -and $_.Parameter -eq 'Name' }
        $name.WireName | Should -Be 'names'
        $name.Surface | Should -Be 'Typed'
        $id = $inventory | Where-Object { $_.Cmdlet -eq 'Get-PfbFixtureHelperDirect' -and $_.Parameter -eq 'Id' }
        $id.WireName | Should -Be 'ids'
        $id.Surface | Should -Be 'Typed'
    }

    It 'resolves -Filter/-Sort/-Limit/-TotalOnly by PARAMETER NAME, since the helper reads them from $PSBoundParameters' -ForEach @(
        @{ Parameter = 'Filter';    WireName = 'filter' }
        @{ Parameter = 'Sort';      WireName = 'sort' }
        @{ Parameter = 'Limit';     WireName = 'limit' }
        @{ Parameter = 'TotalOnly'; WireName = 'total_only' }
    ) {
        $rec = $inventory | Where-Object { $_.Cmdlet -eq 'Get-PfbFixtureHelperDirect' -and $_.Parameter -eq $Parameter }
        $rec.WireName | Should -Be $WireName
        $rec.Surface | Should -Be 'Typed'
    }

    It 'still resolves the -Into variable to its Invoke-PfbApiRequest endpoint' {
        $rec = $inventory | Where-Object { $_.Cmdlet -eq 'Get-PfbFixtureHelperDirect' -and $_.Parameter -eq 'Filter' }
        $rec.Endpoint | Should -Be 'helper-direct'
        $rec.Method | Should -Be 'GET'
    }

    It 'resolves the accumulator pattern (-Names $allNames where $allNames builds from $Name)' {
        $name = $inventory | Where-Object { $_.Cmdlet -eq 'Get-PfbFixtureHelperAccumulator' -and $_.Parameter -eq 'Name' }
        $name.WireName | Should -Be 'names'
        $name.Surface | Should -Be 'Typed'
        $name.Endpoint | Should -Be 'helper-accumulator'
        $id = $inventory | Where-Object { $_.Cmdlet -eq 'Get-PfbFixtureHelperAccumulator' -and $_.Parameter -eq 'Id' }
        $id.WireName | Should -Be 'ids'
        $id.Surface | Should -Be 'Typed'
    }

    It 'resolves a mixed cmdlet: the helper-routed generic param AND its own explicit non-generic line' {
        $policy = $inventory | Where-Object { $_.Cmdlet -eq 'Get-PfbFixtureHelperMixed' -and $_.Parameter -eq 'PolicyName' }
        $policy.WireName | Should -Be 'policy_names'
        $policy.Surface | Should -Be 'Typed'
        $name = $inventory | Where-Object { $_.Cmdlet -eq 'Get-PfbFixtureHelperMixed' -and $_.Parameter -eq 'Name' }
        $name.WireName | Should -Be 'names'
        $name.Surface | Should -Be 'Typed'
        $filter = $inventory | Where-Object { $_.Cmdlet -eq 'Get-PfbFixtureHelperMixed' -and $_.Parameter -eq 'Filter' }
        $filter.WireName | Should -Be 'filter'
    }

    It 'does NOT credit -Filter when the call does not forward $PSBoundParameters' {
        $rec = $inventory | Where-Object { $_.Cmdlet -eq 'Get-PfbFixtureHelperNoBoundParams' -and $_.Parameter -eq 'Filter' }
        $rec.WireName | Should -BeNullOrEmpty
        $rec.Surface | Should -Be 'TypedUnresolved'
    }

    It 'returns $null from Get-PfbCommonQueryParamHelperWireName when -Into is not a plain variable' {
        $tokens = $null; $errs = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput(
            'function Test-Fixture { param([string]$Filter) Add-PfbCommonQueryParams -Into @{} -BoundParameters $PSBoundParameters }', [ref]$tokens, [ref]$errs)
        $funcAst = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | Select-Object -First 1
        Get-PfbCommonQueryParamHelperWireName -FunctionAst $funcAst -ParameterName 'Filter' | Should -BeNullOrEmpty
    }

    It 'returns $null from Get-PfbCommonQueryParamHelperWireName when the function never calls the helper' {
        $tokens = $null; $errs = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput(
            'function Test-Fixture { param([string]$Filter) $queryParams = @{} }', [ref]$tokens, [ref]$errs)
        $funcAst = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | Select-Object -First 1
        Get-PfbCommonQueryParamHelperWireName -FunctionAst $funcAst -ParameterName 'Filter' | Should -BeNullOrEmpty
    }
}

Describe 'Get-PfbCommonQueryParamMap stays in sync with Private/Add-PfbCommonQueryParams.ps1' {
    # Guards the one hazard of hardcoding the mapping: the helper gains, loses, or renames a
    # key and this tools/ mirror silently keeps reporting the old contract. Derives the truth
    # from the helper's own AST and compares, so drift fails the build instead of quietly
    # dropping endpoints back out of gap analysis.
    BeforeAll {
        $script:derivedByParameterName = @{}
        $script:derivedByHelperArgument = @{}
        $script:derivedHelperName = $null

        $tokens = $null; $errs = $null
        $helperAst = [System.Management.Automation.Language.Parser]::ParseFile($helperPath, [ref]$tokens, [ref]$errs)
        $script:derivedHelperName = ($helperAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) |
            Select-Object -First 1).Name

        $assignments = @($helperAst.FindAll({
            param($n)
            $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $n.Left -is [System.Management.Automation.Language.IndexExpressionAst]
        }, $true)) | Where-Object {
            $t = $_.Left.Target -as [System.Management.Automation.Language.VariableExpressionAst]
            $t -and $t.VariablePath.UserPath -eq 'Into'
        }

        foreach ($assign in $assignments) {
            $wireKey = ($assign.Left.Index -as [System.Management.Automation.Language.StringConstantExpressionAst]).Value

            # Every assignment in the helper sits inside a one-clause `if`; the clause's
            # condition is what says WHERE the value came from.
            $node = $assign.Parent
            while ($node -and $node -isnot [System.Management.Automation.Language.IfStatementAst]) { $node = $node.Parent }
            $condition = ''
            if ($node) {
                foreach ($clause in $node.Clauses) {
                    if (@($clause.Item2.FindAll({ param($n) $n -eq $assign }, $true)).Count -gt 0) {
                        $condition = $clause.Item1.Extent.Text.Trim()
                    }
                }
            }

            if ($condition -match '^\$BoundParameters\.ContainsKey\((?:''|")(\w+)(?:''|")\)$') {
                $derivedByParameterName[$Matches[1]] = $wireKey
            }
            elseif ($condition -match '^\$(\w+)$') {
                $derivedByHelperArgument[$Matches[1]] = $wireKey
            }
            else {
                throw "Unrecognized guard shape around `$Into['$wireKey'] in $helperPath : '$condition'. Get-PfbCommonQueryParamMap's detection rules may no longer describe this helper."
            }
        }
    }

    It 'reads a non-empty mapping out of the real helper (guards against a vacuous pass)' {
        $derivedByParameterName.Count | Should -BeGreaterThan 0
        $derivedByHelperArgument.Count | Should -BeGreaterThan 0
    }

    It 'names the same helper the real file defines' {
        (Get-PfbCommonQueryParamMap).HelperName | Should -Be $derivedHelperName
    }

    It 'mirrors the helper $PSBoundParameters-driven keys exactly' {
        $map = Get-PfbCommonQueryParamMap
        @($map.ByParameterName.Keys) | Sort-Object | Should -Be (@($derivedByParameterName.Keys) | Sort-Object)
        foreach ($k in $derivedByParameterName.Keys) {
            $map.ByParameterName[$k] | Should -Be $derivedByParameterName[$k] -Because "the helper assigns `$Into['$($derivedByParameterName[$k])'] for -$k"
        }
    }

    It 'mirrors the helper own-argument keys exactly' {
        $map = Get-PfbCommonQueryParamMap
        @($map.ByHelperArgument.Keys) | Sort-Object | Should -Be (@($derivedByHelperArgument.Keys) | Sort-Object)
        foreach ($k in $derivedByHelperArgument.Keys) {
            $map.ByHelperArgument[$k] | Should -Be $derivedByHelperArgument[$k] -Because "the helper assigns `$Into['$($derivedByHelperArgument[$k])'] from its own -$k argument"
        }
    }
}

Describe 'Hashtable-literal-initializer awareness' {
    It 'resolves a wire key that exists only inside a $queryParams = @{ ... } literal' {
        $rec = $inventory | Where-Object { $_.Cmdlet -eq 'New-PfbFixtureLiteralOnly' -and $_.Parameter -eq 'Name' }
        $rec.WireName | Should -Be 'names'
        $rec.Surface | Should -Be 'Typed'
        $rec.Endpoint | Should -Be 'literal-only'
        $rec.Method | Should -Be 'POST'
    }

    It 'resolves a literal assigned to $body, and reports body (not queryParams) as the target' {
        $rec = $inventory | Where-Object { $_.Cmdlet -eq 'New-PfbFixtureLiteralMixed' -and $_.Parameter -eq 'NewName' }
        $rec.WireName | Should -Be 'name'
        $rec.Surface | Should -Be 'Typed'
        $rec.Endpoint | Should -Be 'literal-mixed'
    }

    It 'resolves BOTH halves of a cmdlet that uses a literal initializer and index assignments' {
        $fromLiteral = $inventory | Where-Object { $_.Cmdlet -eq 'New-PfbFixtureLiteralMixed' -and $_.Parameter -eq 'Name' }
        $fromLiteral.WireName | Should -Be 'names'
        $fromIndex = $inventory | Where-Object { $_.Cmdlet -eq 'New-PfbFixtureLiteralMixed' -and $_.Parameter -eq 'Hostname' }
        $fromIndex.WireName | Should -Be 'host_name'
        @($fromLiteral, $fromIndex).Surface | Should -Be @('Typed', 'Typed')
    }

    It 'resolves a literal value that wraps the parameter in an expression rather than referencing it bare' -ForEach @(
        @{ Parameter = 'Name'; WireName = 'names' }   # @($Name)
        @{ Parameter = 'Key';  WireName = 'keys' }    # $Key -join ','
    ) {
        $rec = $inventory | Where-Object { $_.Cmdlet -eq 'New-PfbFixtureLiteralWrapped' -and $_.Parameter -eq $Parameter }
        $rec.WireName | Should -Be $WireName
        $rec.Surface | Should -Be 'Typed'
    }

    It 'credits a nested sub-object literal to its OUTER key, never the inner one' {
        $rec = $inventory | Where-Object { $_.Cmdlet -eq 'New-PfbFixtureNestedLiteral' -and $_.Parameter -eq 'GroupName' }
        $rec.WireName | Should -Be 'group'
        $rec.WireName | Should -Not -Be 'name'
        $rec.Surface | Should -Be 'Typed'
    }

    It 'still resolves a sibling top-level key in the same nested literal' {
        $rec = $inventory | Where-Object { $_.Cmdlet -eq 'New-PfbFixtureNestedLiteral' -and $_.Parameter -eq 'Quota' }
        $rec.WireName | Should -Be 'quota'
        $rec.Surface | Should -Be 'Typed'
    }

    It 'does NOT match a literal value that merely mentions the parameter inside a pipeline transform' {
        $tokens = $null; $errs = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput(
            'function Test-Fixture { param([string[]]$Servers) $body = @{ attached_servers = @($Servers | ForEach-Object { @{ name = $_ } }) } }', [ref]$tokens, [ref]$errs)
        $funcAst = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | Select-Object -First 1
        Get-PfbHashtableLiteralWireNameForParameter -FunctionAst $funcAst -ParameterName 'Servers' | Should -BeNullOrEmpty
    }

    It 'ignores a hashtable literal assigned to a variable that is neither body nor queryParams' {
        $tokens = $null; $errs = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput(
            'function Test-Fixture { param([string]$Name) $somethingElse = @{ names = $Name } }', [ref]$tokens, [ref]$errs)
        $funcAst = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | Select-Object -First 1
        Get-PfbHashtableLiteralWireNameForParameter -FunctionAst $funcAst -ParameterName 'Name' | Should -BeNullOrEmpty
    }
}

Describe 'Nested single-key reference-object awareness' {
    # The API models "point this resource at that one" as {"account": {"name": "acct1"}}, and
    # the capability map records TOP-LEVEL body properties only -- there is no `account.name`
    # field in it -- so the wire name such a parameter covers is the OUTER key.
    It 'resolves an index-assigned reference object to its outer key' {
        $rec = $inventory | Where-Object { $_.Cmdlet -eq 'New-PfbFixtureNestedReference' -and $_.Parameter -eq 'Account' }
        $rec.WireName | Should -Be 'account'
        $rec.Surface | Should -Be 'Typed'
        $rec.Endpoint | Should -Be 'nested-reference'
        $rec.Method | Should -Be 'POST'
    }

    It 'lets TWO parameters resolve to the same outer key (addressing one field by name or by id is correct, not a collision)' {
        $byName = $inventory | Where-Object { $_.Cmdlet -eq 'New-PfbFixtureNestedReference' -and $_.Parameter -eq 'Account' }
        $byId   = $inventory | Where-Object { $_.Cmdlet -eq 'New-PfbFixtureNestedReference' -and $_.Parameter -eq 'AccountId' }
        $byName.WireName | Should -Be 'account'
        $byId.WireName | Should -Be 'account'
        $byId.Surface | Should -Be 'Typed'
    }

    It 'does not require the inner key to be "name" (real New-PfbFileSystem eradication_config shape)' {
        $rec = $inventory | Where-Object { $_.Cmdlet -eq 'New-PfbFixtureNestedReference' -and $_.Parameter -eq 'EradicationMode' }
        $rec.WireName | Should -Be 'eradication_config'
        $rec.Surface | Should -Be 'Typed'
    }

    It 'still resolves a plain sibling key in the same cmdlet directly' {
        $rec = $inventory | Where-Object { $_.Cmdlet -eq 'New-PfbFixtureNestedReference' -and $_.Parameter -eq 'Versioning' }
        $rec.WireName | Should -Be 'versioning'
        $rec.Surface | Should -Be 'Typed'
    }

    It 'refuses a MULTI-key sub-object, whose per-field ownership cannot be attributed to one parameter' -ForEach @(
        @{ Parameter = 'SourceName' }
        @{ Parameter = 'SourceId' }
    ) {
        $rec = $inventory | Where-Object { $_.Cmdlet -eq 'New-PfbFixtureNestedReference' -and $_.Parameter -eq $Parameter }
        $rec.WireName | Should -BeNullOrEmpty
        $rec.Surface | Should -Be 'TypedUnresolved'
    }

    It 'descends exactly one level -- a doubly-nested sub-object stays unresolved' {
        $rec = $inventory | Where-Object { $_.Cmdlet -eq 'New-PfbFixtureNestedReference' -and $_.Parameter -eq 'Deep' }
        $rec.WireName | Should -BeNullOrEmpty
        $rec.Surface | Should -Be 'TypedUnresolved'
    }

    It 'lets a DIRECT assignment win over a nested one for the same parameter, whatever the source order' {
        # The ordering guarantee that makes this change strictly additive: nested resolution
        # runs as its own pass after both direct-assignment passes, so it can only ever turn
        # an unresolved parameter Typed -- never rename an already-resolved wire name.
        $tokens = $null; $errs = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput(
            'function Test-Fixture { param([string]$Name) $body = @{}; $body["owner"] = @{ name = $Name }; $body["name"] = $Name }', [ref]$tokens, [ref]$errs)
        $funcAst = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | Select-Object -First 1
        (Get-PfbWireNameForParameter -FunctionAst $funcAst -ParameterName 'Name').WireName | Should -Be 'name'
    }

    It 'ignores a reference object keyed into an intermediate variable that is neither body nor queryParams' {
        # Real New-PfbFileSystem $nfsBody/$smbBody: not traceable to an Invoke-PfbApiRequest
        # call, so there is nothing to attribute the wire name to.
        $tokens = $null; $errs = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput(
            'function Test-Fixture { param([string]$Policy) $nfsBody = @{}; $nfsBody["export_policy"] = @{ name = $Policy } }', [ref]$tokens, [ref]$errs)
        $funcAst = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | Select-Object -First 1
        Get-PfbNestedReferenceWireNameForParameter -FunctionAst $funcAst -ParameterName 'Policy' | Should -BeNullOrEmpty
    }

    It 'refuses a nested value produced by a pipeline transform rather than referencing the parameter' {
        $tokens = $null; $errs = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput(
            'function Test-Fixture { param([string[]]$Servers) $body = @{}; $body["attached_servers"] = @($Servers | ForEach-Object { @{ name = $_ } }) }', [ref]$tokens, [ref]$errs)
        $funcAst = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | Select-Object -First 1
        Get-PfbNestedReferenceWireNameForParameter -FunctionAst $funcAst -ParameterName 'Servers' | Should -BeNullOrEmpty
    }

    It 'refuses a non-literal outer key' {
        $tokens = $null; $errs = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput(
            'function Test-Fixture { param([string]$Name, [string]$Key) $body = @{}; $body[$Key] = @{ name = $Name } }', [ref]$tokens, [ref]$errs)
        $funcAst = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | Select-Object -First 1
        Get-PfbNestedReferenceWireNameForParameter -FunctionAst $funcAst -ParameterName 'Name' | Should -BeNullOrEmpty
    }
}

Describe 'Find-PfbAccumulatorVariable' {
    It 'returns $null when the parameter has no foreach loop over it at all' {
        $tokens = $null; $errs = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput(
            'function Test-Fixture { param([string[]]$Unused) $body = @{} }', [ref]$tokens, [ref]$errs)
        $funcAst = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | Select-Object -First 1
        Find-PfbAccumulatorVariable -FunctionAst $funcAst -ParameterName 'Unused' | Should -BeNullOrEmpty
    }

    It 'returns $null when the loop body calls .Add(...) on more than one target variable' {
        $tokens = $null; $errs = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput(
            'function Test-Fixture { param([string[]]$Name) $a = [System.Collections.Generic.List[string]]::new(); $b = [System.Collections.Generic.List[string]]::new(); foreach ($n in $Name) { $a.Add($n); $b.Add($n) } }', [ref]$tokens, [ref]$errs)
        $funcAst = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | Select-Object -First 1
        Find-PfbAccumulatorVariable -FunctionAst $funcAst -ParameterName 'Name' | Should -BeNullOrEmpty
    }

    It 'returns the accumulator variable name for a single unambiguous foreach-Add loop over the parameter' {
        $tokens = $null; $errs = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput(
            'function Test-Fixture { param([string[]]$Name) $names = [System.Collections.Generic.List[string]]::new(); foreach ($n in $Name) { $names.Add($n) } }', [ref]$tokens, [ref]$errs)
        $funcAst = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | Select-Object -First 1
        Find-PfbAccumulatorVariable -FunctionAst $funcAst -ParameterName 'Name' | Should -Be 'names'
    }
}
