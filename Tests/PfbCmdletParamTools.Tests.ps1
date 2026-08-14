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

    # Nested single-key reference objects keyed in by INDEX assignment. Covers, in order: a
    # plain reference object; two parameters resolving to the same outer key (one field addressed
    # by name or id); a non-'name' inner key; a plain sibling key; a multi-key sub-object whose
    # fields cannot be attributed to one parameter; and two nesting levels, which are not descended.
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

    It 'carries each parameter''s own declaration line ($p.Extent.StartLineNumber), alongside its File, so a caveat is a click-through' {
        # New-PfbFixtureAlertWatcher.ps1 is written verbatim from the here-string above (see
        # BeforeAll): line 1 is 'function ...', and -MinimumSeverity's own declaration --
        # attributes included, since ParameterAst.Extent spans the whole parameter, not just
        # the bare variable -- starts at line 7 ('[Parameter()]').
        $rec = $inventory | Where-Object { $_.Cmdlet -eq 'New-PfbFixtureAlertWatcher' -and $_.Parameter -eq 'MinimumSeverity' }
        $rec.File | Should -Be (Join-Path $fixtureDir 'New-PfbFixtureAlertWatcher.ps1')
        $rec.Line | Should -Be 7
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

    It 'resolves a parameter fed through an array projection to its OUTER key' {
        # $AttachedServers is assigned via `@($AttachedServers | ForEach-Object { @{ name = $_ } })`.
        # PR #60 deliberately refused this shape rather than guess; the projection resolver now
        # credits it with the outer key (`attached_servers`), which is the only name the
        # capability map knows -- there is no `attached_servers.name` field in it.
        $rec = $inventory | Where-Object { $_.Cmdlet -eq 'New-PfbFixtureNetworkInterface' -and $_.Parameter -eq 'AttachedServers' }
        $rec.WireName | Should -Be 'attached_servers'
        $rec.Surface | Should -Be 'Typed'
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
        Get-PfbWireNameForParameter -FunctionAst $funcAst -ParameterName 'Foo' -IsBooleanLikeParameter | Should -BeNullOrEmpty
    }

    It 'does NOT apply the switch-literal match when -IsBooleanLikeParameter is not passed' {
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

    It 'does not require the inner key to be "name"' {
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

    It 'resolves a nested value produced by an array projection of the parameter' {
        # Was 'refuses a nested value produced by a pipeline transform' under PR #60. The
        # projection shape is now recognised; the shapes that genuinely cannot be attributed
        # (multi-key items, $_.Member, filtered pipelines) are covered in the
        # 'Array-of-references projection awareness' Describe block.
        $tokens = $null; $errs = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput(
            'function Test-Fixture { param([string[]]$Servers) $body = @{}; $body["attached_servers"] = @($Servers | ForEach-Object { @{ name = $_ } }) }', [ref]$tokens, [ref]$errs)
        $funcAst = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | Select-Object -First 1
        (Get-PfbNestedReferenceWireNameForParameter -FunctionAst $funcAst -ParameterName 'Servers').WireName | Should -Be 'attached_servers'
    }

    It 'refuses a non-literal outer key' {
        $tokens = $null; $errs = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput(
            'function Test-Fixture { param([string]$Name, [string]$Key) $body = @{}; $body[$Key] = @{ name = $Name } }', [ref]$tokens, [ref]$errs)
        $funcAst = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | Select-Object -First 1
        Get-PfbNestedReferenceWireNameForParameter -FunctionAst $funcAst -ParameterName 'Name' | Should -BeNullOrEmpty
    }
}

Describe 'Array-of-references projection awareness' {
    # The API models a LIST of references as an array of single-key sub-objects, and the
    # module builds it with `@($Param | ForEach-Object { @{ name = $_ } })`. The parameter's
    # identity is the pipeline SOURCE -- the innermost value is $_, which names nothing --
    # so this cannot route through Test-PfbWireValueIsParameter like the scalar form does.
    # As with the scalar form, the wire name is the OUTER key.

    BeforeAll {
        function Get-TestFunctionAst {
            param([string]$Source)
            $tokens = $null; $errs = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseInput($Source, [ref]$tokens, [ref]$errs)
            $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | Select-Object -First 1
        }
    }

    It 'resolves an index-assigned projection to its outer key' {
        $f = Get-TestFunctionAst 'function Test-Fixture { param([string[]]$Servers) $body = @{}; $body["attached_servers"] = @($Servers | ForEach-Object { @{ name = $_ } }) }'
        $result = Get-PfbNestedReferenceWireNameForParameter -FunctionAst $f -ParameterName 'Servers'
        $result.WireName | Should -Be 'attached_servers'
        $result.TargetVariable | Should -Be 'body'
    }

    It 'resolves a projection inside a hashtable-literal initializer' {
        $f = Get-TestFunctionAst 'function Test-Fixture { param([string[]]$DnsName) $body = @{ dns = @($DnsName | ForEach-Object { @{ name = $_ } }) } }'
        (Get-PfbNestedReferenceWireNameForParameter -FunctionAst $f -ParameterName 'DnsName').WireName | Should -Be 'dns'
    }

    It 'resolves a projection that is not wrapped in @()' {
        $f = Get-TestFunctionAst 'function Test-Fixture { param([string[]]$Servers) $body = @{}; $body["attached_servers"] = $Servers | ForEach-Object { @{ name = $_ } } }'
        (Get-PfbNestedReferenceWireNameForParameter -FunctionAst $f -ParameterName 'Servers').WireName | Should -Be 'attached_servers'
    }

    It 'accepts the % alias for ForEach-Object' {
        $f = Get-TestFunctionAst 'function Test-Fixture { param([string[]]$Servers) $body = @{}; $body["attached_servers"] = @($Servers | % { @{ name = $_ } }) }'
        (Get-PfbNestedReferenceWireNameForParameter -FunctionAst $f -ParameterName 'Servers').WireName | Should -Be 'attached_servers'
    }

    It 'does not require the inner key to be "name"' {
        $f = Get-TestFunctionAst 'function Test-Fixture { param([string[]]$Ids) $body = @{}; $body["ports"] = @($Ids | ForEach-Object { @{ id = $_ } }) }'
        (Get-PfbNestedReferenceWireNameForParameter -FunctionAst $f -ParameterName 'Ids').WireName | Should -Be 'ports'
    }

    It 'reports queryParams as the target variable when the projection is keyed there' {
        $f = Get-TestFunctionAst 'function Test-Fixture { param([string[]]$Servers) $queryParams = @{}; $queryParams["attached_servers"] = @($Servers | ForEach-Object { @{ name = $_ } }) }'
        (Get-PfbNestedReferenceWireNameForParameter -FunctionAst $f -ParameterName 'Servers').TargetVariable | Should -Be 'queryParams'
    }

    It 'refuses a MULTI-key projection hashtable, whose per-field ownership cannot be attributed to one parameter' {
        $f = Get-TestFunctionAst 'function Test-Fixture { param([object[]]$Tags) $body = @{}; $body["tags"] = @($Tags | ForEach-Object { @{ key = $_; value = 1 } }) }'
        Get-PfbNestedReferenceWireNameForParameter -FunctionAst $f -ParameterName 'Tags' | Should -BeNullOrEmpty
    }

    It 'refuses an innermost value that is a member access rather than the bare $_' {
        $f = Get-TestFunctionAst 'function Test-Fixture { param([object[]]$Servers) $body = @{}; $body["attached_servers"] = @($Servers | ForEach-Object { @{ name = $_.Name } }) }'
        Get-PfbNestedReferenceWireNameForParameter -FunctionAst $f -ParameterName 'Servers' | Should -BeNullOrEmpty
    }

    It 'refuses an innermost value that is a bare variable OTHER than $_' {
        # Mutation-table coverage (Step 7, "innermost is $_" guard): the member-access test
        # above is caught earlier, by the VariableExpressionAst cast itself failing on
        # `$_.Name`. This shape's innermost value IS a bare VariableExpressionAst, just not
        # named `_` -- so only the UserPath -eq '_' check stops a constant, non-per-element
        # value (here, a sibling parameter) from being wrongly credited to $Servers.
        $f = Get-TestFunctionAst 'function Test-Fixture { param([string[]]$Servers, [string]$Other) $body = @{}; $body["attached_servers"] = @($Servers | ForEach-Object { @{ name = $Other } }) }'
        Get-PfbNestedReferenceWireNameForParameter -FunctionAst $f -ParameterName 'Servers' | Should -BeNullOrEmpty
    }

    It 'refuses a projection whose pipeline source is a DIFFERENT parameter' {
        $f = Get-TestFunctionAst 'function Test-Fixture { param([string[]]$Servers, [string[]]$Other) $body = @{}; $body["attached_servers"] = @($Other | ForEach-Object { @{ name = $_ } }) }'
        Get-PfbNestedReferenceWireNameForParameter -FunctionAst $f -ParameterName 'Servers' | Should -BeNullOrEmpty
    }

    It 'refuses a projection whose pipeline source is not a bare variable' {
        $f = Get-TestFunctionAst 'function Test-Fixture { param([string[]]$Servers) $body = @{}; $body["attached_servers"] = @("literal" | ForEach-Object { @{ name = $_ } }) }'
        Get-PfbNestedReferenceWireNameForParameter -FunctionAst $f -ParameterName 'Servers' | Should -BeNullOrEmpty
    }

    It 'refuses a FILTERED pipeline -- the wire value is a subset, so the parameter does not cover the field' {
        $f = Get-TestFunctionAst 'function Test-Fixture { param([string[]]$Servers) $body = @{}; $body["attached_servers"] = @($Servers | Where-Object { $_ } | ForEach-Object { @{ name = $_ } }) }'
        Get-PfbNestedReferenceWireNameForParameter -FunctionAst $f -ParameterName 'Servers' | Should -BeNullOrEmpty
    }

    It 'refuses a ForEach-Object carrying arguments other than its script block' {
        $f = Get-TestFunctionAst 'function Test-Fixture { param([string[]]$Servers) $body = @{}; $body["attached_servers"] = @($Servers | ForEach-Object -Process { @{ name = $_ } }) }'
        Get-PfbNestedReferenceWireNameForParameter -FunctionAst $f -ParameterName 'Servers' | Should -BeNullOrEmpty
    }

    It 'refuses a projection keyed into a variable that is neither body nor queryParams' {
        $f = Get-TestFunctionAst 'function Test-Fixture { param([string[]]$Servers) $nfsBody = @{}; $nfsBody["attached_servers"] = @($Servers | ForEach-Object { @{ name = $_ } }) }'
        Get-PfbNestedReferenceWireNameForParameter -FunctionAst $f -ParameterName 'Servers' | Should -BeNullOrEmpty
    }

    It 'refuses a projection under a non-literal outer key' {
        $f = Get-TestFunctionAst 'function Test-Fixture { param([string[]]$Servers, [string]$Key) $body = @{}; $body[$Key] = @($Servers | ForEach-Object { @{ name = $_ } }) }'
        Get-PfbNestedReferenceWireNameForParameter -FunctionAst $f -ParameterName 'Servers' | Should -BeNullOrEmpty
    }

    It 'lets a DIRECT assignment win over a projection for the same parameter, whatever the source order' {
        # The ordering guarantee that keeps this change strictly additive: projection matching
        # lives inside the nested resolver, which runs as its own pass AFTER both direct-
        # assignment passes, so it can only turn an unresolved parameter Typed -- never rename
        # an already-resolved wire name. Mirrors the scalar-form test above.
        $f = Get-TestFunctionAst 'function Test-Fixture { param([string[]]$Servers) $body = @{}; $body["attached_servers"] = @($Servers | ForEach-Object { @{ name = $_ } }); $body["servers"] = @($Servers) }'
        (Get-PfbWireNameForParameter -FunctionAst $f -ParameterName 'Servers').WireName | Should -Be 'servers'
    }

    It 'refuses a pipeline with a trailing step after ForEach-Object' {
        # Mutation-table coverage (Step 7, "pipeline length" guard): the FILTERED-pipeline
        # test above puts its extra stage BEFORE ForEach-Object, so it is (redundantly)
        # also caught by the command-name check on element[1]. This shape puts the extra
        # stage AFTER ForEach-Object, so element[1] genuinely IS ForEach-Object and only the
        # pipeline-length check (`-ne 2`, not `-lt 2`) stops it being wrongly credited.
        $f = Get-TestFunctionAst 'function Test-Fixture { param([string[]]$Servers) $body = @{}; $body["attached_servers"] = @($Servers | ForEach-Object { @{ name = $_ } } | Sort-Object) }'
        Get-PfbNestedReferenceWireNameForParameter -FunctionAst $f -ParameterName 'Servers' | Should -BeNullOrEmpty
    }

    It 'refuses a ForEach-Object script block followed by a trailing named argument' {
        # Mutation-table coverage (Step 7, "command arg count" guard): the existing
        # `-Process { ... }` test above puts its extra argument BEFORE the script block, so
        # index 1 is a CommandParameterAst and is (redundantly) also caught by the
        # scriptBlockExpr cast. This shape puts the extra argument AFTER the script block, so
        # index 1 genuinely IS the script block, and only the CommandElements.Count check
        # (`-ne 2`, not `-lt 2`) stops it being wrongly credited.
        $f = Get-TestFunctionAst 'function Test-Fixture { param([string[]]$Servers) $body = @{}; $body["attached_servers"] = @($Servers | ForEach-Object { @{ name = $_ } } -ErrorAction Stop) }'
        Get-PfbNestedReferenceWireNameForParameter -FunctionAst $f -ParameterName 'Servers' | Should -BeNullOrEmpty
    }

    It 'refuses a projection piped through a command other than ForEach-Object/%' {
        # Mutation-table coverage (Step 7, "command name" guard): dropping the
        # -notin @('ForEach-Object','%') check would let any command through, e.g. `Get-Item`.
        $f = Get-TestFunctionAst 'function Test-Fixture { param([string[]]$Servers) $body = @{}; $body["attached_servers"] = @($Servers | Get-Item { @{ name = $_ } }) }'
        Get-PfbNestedReferenceWireNameForParameter -FunctionAst $f -ParameterName 'Servers' | Should -BeNullOrEmpty
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

Describe 'Get-PfbCmdletBodyInsertionTarget (Task 5 -- insertion-point coordinates, decision 12)' {
    BeforeAll {
        function script:Get-PfbTestFunctionAst {
            param([string]$Source)
            $tokens = $null; $errs = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseInput($Source, [ref]$tokens, [ref]$errs)
            return $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | Select-Object -First 1
        }
    }

    It 'returns $null for a function with no param() block at all' {
        $funcAst = Get-PfbTestFunctionAst 'function Test-Fixture { Write-Host "no params" }'
        Get-PfbCmdletBodyInsertionTarget -FunctionAst $funcAst | Should -BeNullOrEmpty
    }

    It 'detects the index-assignment style ($body[''key''] = ...) as the dominant AssignmentStyle' {
        $funcAst = Get-PfbTestFunctionAst @'
function Test-FixtureIndex {
    param([Parameter()] [PSCustomObject]$Array, [Parameter()] [string]$Name)
    $body = @{}
    if ($Name) { $body['name'] = $Name }
    Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'fixtures' -Body $body
}
'@
        $result = Get-PfbCmdletBodyInsertionTarget -FunctionAst $funcAst
        $result.PayloadVariable | Should -Be 'body'
        $result.AssignmentStyle | Should -Be 'index'
        $result.HasAttributes | Should -BeFalse
    }

    It 'detects the hashtable-literal-initializer style as the dominant AssignmentStyle when it has more key/value pairs than index-form assignments' {
        $funcAst = Get-PfbTestFunctionAst @'
function Test-FixtureLiteral {
    param([Parameter()] [PSCustomObject]$Array, [Parameter()] [string]$Name, [Parameter()] [string]$Kind)
    $body = @{ name = $Name; kind = $Kind }
    Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'fixtures' -Body $body
}
'@
        $result = Get-PfbCmdletBodyInsertionTarget -FunctionAst $funcAst
        $result.PayloadVariable | Should -Be 'body'
        $result.AssignmentStyle | Should -Be 'literal'
    }

    It 'reports AssignmentStyle ''attributesOnly'' when -Body is fed directly by the cmdlet''s own -Attributes parameter' {
        $funcAst = Get-PfbTestFunctionAst @'
function Update-FixtureCertificate {
    param([Parameter(Mandatory)] [string]$Name, [Parameter(Mandatory)] [hashtable]$Attributes, [Parameter()] [PSCustomObject]$Array)
    Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'fixtures' -Body $Attributes
}
'@
        $result = Get-PfbCmdletBodyInsertionTarget -FunctionAst $funcAst
        $result.PayloadVariable | Should -Be 'Attributes'
        $result.AssignmentStyle | Should -Be 'attributesOnly'
        $result.HasAttributes | Should -BeTrue
    }

    It 'reports AssignmentStyle ''unknown'' when PayloadVariable resolves but nothing in this function assigns into it' {
        $funcAst = Get-PfbTestFunctionAst @'
function Test-FixtureHelperBuilt {
    param([Parameter()] [PSCustomObject]$Array, [Parameter()] [string]$Name)
    $body = Get-FixtureBodyFromHelper -Name $Name
    Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'fixtures' -Body $body
}
'@
        $result = Get-PfbCmdletBodyInsertionTarget -FunctionAst $funcAst
        $result.PayloadVariable | Should -Be 'body'
        $result.AssignmentStyle | Should -Be 'unknown'
    }

    It 'leaves PayloadVariable/AssignmentStyle $null when two Invoke-PfbApiRequest calls disagree on the -Body variable (never guesses)' {
        $funcAst = Get-PfbTestFunctionAst @'
function Test-FixtureAmbiguousBody {
    param([Parameter()] [PSCustomObject]$Array, [Parameter()] [string]$Name)
    $body = @{}
    $altBody = @{}
    if ($Name) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'fixtures' -Body $body
    } else {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'fixtures' -Body $altBody
    }
}
'@
        $result = Get-PfbCmdletBodyInsertionTarget -FunctionAst $funcAst
        $result.PayloadVariable | Should -BeNullOrEmpty
        $result.AssignmentStyle | Should -BeNullOrEmpty
    }

    It 'computes ParamBlockLine as the line of the LAST declared parameter' {
        $funcAst = Get-PfbTestFunctionAst @'
function Test-FixtureParamLine {
    param(
        [Parameter()] [PSCustomObject]$Array,
        [Parameter()] [string]$Name,
        [Parameter()] [string]$Kind
    )
    $body = @{}
    if ($Name) { $body['name'] = $Name }
    Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'fixtures' -Body $body
}
'@
        $result = Get-PfbCmdletBodyInsertionTarget -FunctionAst $funcAst
        # Line 1 is 'function ...', line 2 'param(', 3 Array, 4 Name, 5 Kind, 6 ')'.
        $result.ParamBlockLine | Should -Be 5
    }

    It 'falls back to the param block''s own opening line when it declares zero parameters' {
        $funcAst = Get-PfbTestFunctionAst @'
function Test-FixtureNoParams {
    param()
    $body = @{}
    Invoke-PfbApiRequest -Method GET -Endpoint 'fixtures' -Body $body
}
'@
        $result = Get-PfbCmdletBodyInsertionTarget -FunctionAst $funcAst
        $result.ParamBlockLine | Should -Be 2
    }

    It 'reports HasAttributes $false when the cmdlet declares no -Attributes parameter at all' {
        $funcAst = Get-PfbTestFunctionAst @'
function Test-FixtureNoAttributes {
    param([Parameter()] [PSCustomObject]$Array, [Parameter()] [string]$Name)
    $body = @{}
    if ($Name) { $body['name'] = $Name }
    Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'fixtures' -Body $body
}
'@
        $result = Get-PfbCmdletBodyInsertionTarget -FunctionAst $funcAst
        $result.HasAttributes | Should -BeFalse
    }
}

Describe 'Get-PfbCmdletParameterInventory emit order is canonical, not filesystem order (issue #85)' {
    BeforeAll {
        # Two fixture trees holding the SAME two cmdlets, but with the cmdlet-to-filename
        # mapping swapped between them. Both trees carry identical FILE names, so
        # Get-ChildItem walks them in the same sequence whatever the filesystem does -- the
        # only thing that differs is which cmdlet each position in that walk yields. An
        # unsorted inventory therefore emits Zulu-then-Alpha for one tree and
        # Alpha-then-Zulu for the other; a canonically-ordered one emits the same sequence
        # for both.
        #
        # This is the platform-INDEPENDENT form of the divergence issue #85 first observed
        # as a 10,218-line phantom diff between a Windows-generated and a Linux-generated
        # Reports/PfbFieldCmdletMap.json. Deliberately not written as "run the builder twice
        # on this machine" -- that is exactly the assertion
        # Tests/Build-PfbApiDriftReport.Tests.ps1 already makes, and enumeration order is
        # stable within one filesystem, so it can never fail. And deliberately not dependent
        # on tools/specs/, so it does not silently skip in a fresh clone or worktree (#63).
        $script:orderDirA = Join-Path $TestDrive 'EmitOrderA/Public'
        $script:orderDirB = Join-Path $TestDrive 'EmitOrderB/Public'
        New-Item -ItemType Directory -Path $script:orderDirA, $script:orderDirB -Force | Out-Null

        # Parameters are declared Zebra-before-Apple so the assertion below also pins
        # within-cmdlet ordering, which declaration order alone would leave reversed.
        $zuluSource = @'
function Get-PfbFixtureOrderZulu {
    [CmdletBinding()]
    param(
        [Parameter()] [PSCustomObject]$Array,
        [Parameter()] [string]$Zebra,
        [Parameter()] [string]$Apple
    )
    $queryParams = @{}
    if ($Zebra) { $queryParams['zebra'] = $Zebra }
    if ($Apple) { $queryParams['apple'] = $Apple }
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'order-zulu' -QueryParams $queryParams
}
'@
        $alphaSource = @'
function Get-PfbFixtureOrderAlpha {
    [CmdletBinding()]
    param(
        [Parameter()] [PSCustomObject]$Array,
        [Parameter()] [string]$Zebra,
        [Parameter()] [string]$Apple
    )
    $queryParams = @{}
    if ($Zebra) { $queryParams['zebra'] = $Zebra }
    if ($Apple) { $queryParams['apple'] = $Apple }
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'order-alpha' -QueryParams $queryParams
}
'@
        Set-Content -Path (Join-Path $script:orderDirA '01-first.ps1') -Value $zuluSource
        Set-Content -Path (Join-Path $script:orderDirA '02-second.ps1') -Value $alphaSource
        Set-Content -Path (Join-Path $script:orderDirB '01-first.ps1') -Value $alphaSource
        Set-Content -Path (Join-Path $script:orderDirB '02-second.ps1') -Value $zuluSource

        $script:orderKeysA = @(Get-PfbCmdletParameterInventory -PublicDirectory $script:orderDirA |
                ForEach-Object { '{0}|{1}' -f $_.Cmdlet, $_.Parameter })
        $script:orderKeysB = @(Get-PfbCmdletParameterInventory -PublicDirectory $script:orderDirB |
                ForEach-Object { '{0}|{1}' -f $_.Cmdlet, $_.Parameter })
    }

    It 'emits the same sequence for two trees differing only in which file defines which cmdlet' {
        $script:orderKeysA | Should -Be $script:orderKeysB
    }

    It 'emits rows ordered by cmdlet name, then parameter name -- never by file walk or declaration order' {
        $script:orderKeysA | Should -Be @(
            'Get-PfbFixtureOrderAlpha|Apple'
            'Get-PfbFixtureOrderAlpha|Zebra'
            'Get-PfbFixtureOrderZulu|Apple'
            'Get-PfbFixtureOrderZulu|Zebra'
        )
    }
}

Describe 'Conditional right-hand side awareness (issue #99)' {
    # New-PfbFileSystemReplicaLink sends a [Nullable[bool]] as
    # `$queryParams['remote_default_exports'] = if ($RemoteDefaultExports) { 'true' } else { 'false' }`
    # -- the $false value must reach the wire, so the assignment is guarded on
    # $PSBoundParameters.ContainsKey rather than on truthiness. The tracer refused that shape
    # twice over: its only constant-value branch was gated on [switch], and an if-EXPRESSION
    # right-hand side matched no branch at all.
    BeforeAll {
        $script:condDir = Join-Path $TestDrive 'Conditional/Public'
        New-Item -ItemType Directory -Path $script:condDir -Force | Out-Null

        Set-Content -Path (Join-Path $script:condDir 'New-PfbFixtureConditional.ps1') -Value @'
function New-PfbFixtureConditional {
    [CmdletBinding()]
    param(
        [Parameter()] [Nullable[bool]]$RemoteDefaultExports,
        [Parameter()] [bool]$PlainBool,
        [Parameter()] [switch]$SwitchFlag,
        [Parameter()] [Nullable[bool]]$Negated,
        [Parameter()] [string]$NotBoolean,
        [Parameter()] [PSCustomObject]$Array
    )

    $queryParams = @{}
    if ($PSBoundParameters.ContainsKey('RemoteDefaultExports')) {
        $queryParams['remote_default_exports'] = if ($RemoteDefaultExports) { 'true' } else { 'false' }
    }
    if ($PSBoundParameters.ContainsKey('PlainBool')) {
        $queryParams['plain_bool'] = if ($PlainBool) { 'true' } else { 'false' }
    }
    $queryParams['switch_flag'] = if ($SwitchFlag) { 'true' } else { 'false' }
    $queryParams['negated'] = if (-not $Negated) { 'false' } else { 'true' }
    $queryParams['not_boolean'] = if ($NotBoolean) { 'true' } else { 'false' }
    Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'conditional' -QueryParams $queryParams
}
'@

        Set-Content -Path (Join-Path $script:condDir 'New-PfbFixtureConditionalLiteral.ps1') -Value @'
function New-PfbFixtureConditionalLiteral {
    [CmdletBinding()]
    param(
        [Parameter()] [Nullable[bool]]$Enabled,
        [Parameter()] [PSCustomObject]$Array
    )

    $queryParams = @{
        'enabled' = if ($Enabled) { 'true' } else { 'false' }
    }
    Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'conditional-literal' -QueryParams $queryParams
}
'@

        $script:condInventory = Get-PfbCmdletParameterInventory -PublicDirectory $script:condDir
    }

    It 'resolves a <Type> parameter assigned a two-branch constant if-expression' -ForEach @(
        @{ Type = '[Nullable[bool]]'; Parameter = 'RemoteDefaultExports'; WireName = 'remote_default_exports' }
        @{ Type = '[bool]';           Parameter = 'PlainBool';            WireName = 'plain_bool' }
        @{ Type = '[switch]';         Parameter = 'SwitchFlag';           WireName = 'switch_flag' }
        @{ Type = '-not, swapped';    Parameter = 'Negated';              WireName = 'negated' }
    ) {
        $rec = $script:condInventory | Where-Object { $_.Cmdlet -eq 'New-PfbFixtureConditional' -and $_.Parameter -eq $Parameter }
        $rec.WireName | Should -Be $WireName
        $rec.Surface | Should -Be 'Typed'
    }

    It 'refuses the same shape for a parameter that is not boolean-like' {
        $rec = $script:condInventory | Where-Object { $_.Cmdlet -eq 'New-PfbFixtureConditional' -and $_.Parameter -eq 'NotBoolean' }
        $rec.WireName | Should -BeNullOrEmpty
        $rec.Surface | Should -Be 'TypedUnresolved'
    }

    It 'resolves the same shape inside a hashtable literal initializer' {
        $rec = $script:condInventory | Where-Object { $_.Cmdlet -eq 'New-PfbFixtureConditionalLiteral' -and $_.Parameter -eq 'Enabled' }
        $rec.WireName | Should -Be 'enabled'
        $rec.Surface | Should -Be 'Typed'
        $rec.Endpoint | Should -Be 'conditional-literal'
        $rec.Method | Should -Be 'POST'
    }

    It 'resolves end-to-end through Get-PfbWireNameForParameter to the wire name AND the target variable' {
        $tokens = $null; $errs = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput(@'
function Test-Fixture {
    param([Nullable[bool]]$RemoteDefaultExports)
    $queryParams = @{}
    if ($PSBoundParameters.ContainsKey('RemoteDefaultExports')) {
        $queryParams['remote_default_exports'] = if ($RemoteDefaultExports) { 'true' } else { 'false' }
    }
}
'@, [ref]$tokens, [ref]$errs)
        $funcAst = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | Select-Object -First 1
        $result = Get-PfbWireNameForParameter -FunctionAst $funcAst -ParameterName 'RemoteDefaultExports' -IsBooleanLikeParameter
        $result.WireName | Should -Be 'remote_default_exports'
        $result.TargetVariable | Should -Be 'queryParams'
    }

    # The guard on the "never guess" contract: every one of these is boolean-like, so only the
    # SHAPE rules keep them refused.
    It 'refuses <Case>' -ForEach @(
        @{ Case = 'a condition naming a DIFFERENT variable'
           Body = '$queryParams["k"] = if ($Other) { "true" } else { "false" }' }
        @{ Case = 'a branch that is not a constant'
           Body = '$queryParams["k"] = if ($Param) { $Other } else { "false" }' }
        @{ Case = 'a missing else clause'
           Body = '$queryParams["k"] = if ($Param) { "true" }' }
        @{ Case = 'an elseif, so Clauses.Count is 2'
           Body = '$queryParams["k"] = if ($Param) { "true" } elseif ($Other) { "maybe" } else { "false" }' }
    ) {
        $tokens = $null; $errs = $null
        $source = 'function Test-Fixture { param([Nullable[bool]]$Param, [Nullable[bool]]$Other) ' + $Body + ' }'
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$errs)
        $funcAst = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | Select-Object -First 1
        Get-PfbWireNameForParameter -FunctionAst $funcAst -ParameterName 'Param' -IsBooleanLikeParameter | Should -BeNullOrEmpty
    }
}

Describe 'Get-PfbCmdletParameterInventory - wire surface' {
    BeforeAll {
        $script:inventoryRoot = Join-Path $TestDrive 'WireSurface/Public'
        New-Item -ItemType Directory -Path $script:inventoryRoot -Force | Out-Null
        Set-Content -Path (Join-Path $script:inventoryRoot 'Get-Thing.ps1') -Value @"
function Get-Thing {
    param([string[]]`$Name, [string]`$Description)
    `$queryParams = @{}
    `$queryParams['names'] = `$Name -join ','
    `$body = @{}
    `$body['description'] = `$Description
    Invoke-PfbApiRequest -Method GET -Endpoint 'things' -QueryParams `$queryParams -Body `$body
}
"@
        $script:wireInventory = Get-PfbCmdletParameterInventory -PublicDirectory $script:inventoryRoot
    }

    It 'classifies a queryParams-targeted parameter as Query' {
        $rec = $script:wireInventory | Where-Object { $_.Parameter -eq 'Name' }
        $rec.TargetVariable | Should -Be 'queryParams'
        $rec.WireSurface    | Should -Be 'Query'
    }

    It 'classifies a body-targeted parameter as Body' {
        $rec = $script:wireInventory | Where-Object { $_.Parameter -eq 'Description' }
        $rec.TargetVariable | Should -Be 'body'
        $rec.WireSurface    | Should -Be 'Body'
    }
}
