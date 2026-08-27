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

    Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'alert-watchers' -Body $body
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

    Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'network-interfaces' -Body $body
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

    # Real Get-PfbUserGroupQuotaPolicy shape (issue #141 Task 2): the SAME process-block
    # accumulators as Get-PfbFixtureHelperAccumulator, but handed to the helper as
    # `$allNames.ToArray()` -- the helper's -Names/-Ids are [string[]]-typed, so a
    # [List[string]] accumulator must be converted at the call site. Resolution must still
    # go parameter -> accumulator -> helper argument; the parameter names (Label/Marker)
    # deliberately share no word with the wire keys (names/ids), so a pass cannot come
    # from guessing the key off the parameter name.
    Set-Content -Path (Join-Path $fixtureDir 'Get-PfbFixtureHelperToArray.ps1') -Value @'
function Get-PfbFixtureHelperToArray {
    [CmdletBinding()]
    param(
        [Parameter()] [PSCustomObject]$Array,
        [Parameter(ValueFromPipeline)] [string[]]$Label,
        [Parameter()] [string[]]$Marker
    )
    begin {
        $allNames = [System.Collections.Generic.List[string]]::new()
        $allIds = [System.Collections.Generic.List[string]]::new()
    }
    process {
        if ($Label)  { foreach ($n in $Label)  { $allNames.Add($n) } }
        if ($Marker) { foreach ($i in $Marker) { $allIds.Add($i) } }
    }
    end {
        $queryParams = @{}
        Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters -Names $allNames.ToArray() -Ids $allIds.ToArray()
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'helper-toarray' -QueryParams $queryParams -AutoPaginate
    }
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
    $script:publicDir = Join-Path $repoRoot 'Public'
    $script:inventory = Get-PfbCmdletParameterInventory -PublicDirectory $fixtureDir

    # --- issue #141 Task 3 test bed ---------------------------------------------------
    # Single parse point for every inline fixture added by Task 3, and the ONLY place that
    # gets to decide a fixture is usable. Get-PfbCmdletParameterInventory discards its own
    # $parseErrors, so a fixture that does not parse is not a test at all -- it is a string
    # the resolver declines to read, and every assertion over it passes for the wrong reason.
    function script:Get-PfbRoleFixtureAst {
        param(
            # One element per source line; joined with a real newline here so a fixture is
            # never silently collapsed onto one line by the output field separator.
            [Parameter(Mandatory)]
            [string[]]$Source
        )
        $text = $Source -join [System.Environment]::NewLine
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$parseErrors)
        if (@($parseErrors).Count -ne 0) {
            throw ("Fixture source does not parse ({0} error(s)): {1}`n{2}" -f @($parseErrors).Count, $parseErrors[0].Message, $text)
        }
        $funcAst = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) |
            Select-Object -First 1
        if (-not $funcAst) { throw "Fixture source defines no function:`n$text" }
        return $funcAst
    }

    # Builds the one-assignment role fixture used across the Task 3 positives. Every name in
    # it is deliberately unrelated to every other (test-bed rule 4): the payload variable is
    # supplied by the caller, the parameter is -Zeta, the wire key is 'alpha' and the
    # endpoint is 'widgets'. No two of those share a word, so a resolution can only have come
    # from reading the request argument.
    function script:New-PfbRoleFixtureSource {
        param(
            [Parameter(Mandatory)]
            [string]$Variable,

            # Verbatim payload argument, e.g. '-QueryParams $q' or '-Body:$payload'.
            [Parameter(Mandatory)]
            [string]$PayloadArgument
        )
        $v = '$' + $Variable
        return @(
            'function Test-Fixture {'
            '    param([string]$Zeta)'
            ('    ' + $v + ' = @{}')
            ('    ' + $v + "['alpha'] = " + '$Zeta')
            ("    Invoke-PfbApiRequest -Method PATCH -Endpoint 'widgets' " + $PayloadArgument)
            '}'
        ) -join [System.Environment]::NewLine
    }
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

Describe 'Add-PfbCommonQueryParams exact $var.ToArray() helper arguments (issue #141 Task 2)' {
    # A [List[string]] accumulator cannot bind to the helper's [string[]]-typed -Names/-Ids
    # directly, so a cmdlet hands it over as $accumulator.ToArray() (real:
    # Get-PfbUserGroupQuotaPolicy). The resolver credits the underlying source variable --
    # never the method call's result -- and only for the exact zero-argument ToArray-on-a-
    # bare-variable shape. Anything else derives its value from something other than one
    # variable alone and stays refused.

    BeforeAll {
        function Get-PfbToArrayHelperAst {
            param([string]$NamesArgument)
            $tokens = $null; $errs = $null
            $source = 'function Test-Fixture { param([string]$Param) $queryParams = @{}; ' +
                'Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters -Names ' +
                $NamesArgument + ' }'
            $ast = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$errs)
            # A fixture that does not parse is not a test -- it is a string the resolver
            # declines to read, and every assertion over it passes for the wrong reason.
            # `-Names [SomeType]::ToArray()` is the live example: in command-argument parsing
            # mode PowerShell emits ExpectedExpression and splits it into a bareword plus a
            # ParenExpressionAst, so the fixture never reaches the guard it appears to test.
            if ($errs.Count -gt 0) {
                throw "Fixture source for argument '$NamesArgument' does not parse: $($errs[0].Message)"
            }
            $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | Select-Object -First 1
        }
    }

    It 'resolves -Label/-Marker through the accumulator path even though the helper receives $allNames.ToArray()' {
        # Inventory-level positive: parameter -> Find-PfbAccumulatorVariable ($allNames) ->
        # Get-PfbWireNameForParameter('allNames') -> helper argument $allNames.ToArray().
        # Neutral parameter names: 'names'/'ids' share no word with 'Label'/'Marker', so the
        # wire key can only have come from the mapping, not from the parameter's name.
        $name = $inventory | Where-Object { $_.Cmdlet -eq 'Get-PfbFixtureHelperToArray' -and $_.Parameter -eq 'Label' }
        $name.WireName | Should -Be 'names'
        $name.Surface | Should -Be 'Typed'
        $name.WireSurface | Should -Be 'Query'
        $name.Endpoint | Should -Be 'helper-toarray'
        $name.Method | Should -Be 'GET'
        $id = $inventory | Where-Object { $_.Cmdlet -eq 'Get-PfbFixtureHelperToArray' -and $_.Parameter -eq 'Marker' }
        $id.WireName | Should -Be 'ids'
        $id.Surface | Should -Be 'Typed'
        $id.WireSurface | Should -Be 'Query'
    }

    It 'resolves a DIRECT helper argument of the exact $var.ToArray() shape to the source variable' {
        # No foreach accumulator involved: $Param itself is the call site's ToArray target.
        $funcAst = Get-PfbToArrayHelperAst '$Param.ToArray()'
        $result = Get-PfbCommonQueryParamHelperWireName -FunctionAst $funcAst -ParameterName 'Param'
        $result.WireName | Should -Be 'names'
        $result.TargetVariable | Should -Be 'queryParams'
    }

    It 'refuses a helper argument of <Shape> -- the value is not a bare variable or exact $var.ToArray() on one' -ForEach @(
        # Deliberately the ARITY guard's own coverage: `.Clone()` and `.ToArray().ToString()`
        # are already refused by the member-name check, and `($left + $right).ToArray()` by the
        # bare-target check -- but `$Param.ToArray($Param)` has member ToArray, a bare-variable
        # target, and differs from the accepted shape ONLY by carrying an argument. If deleting
        # the Test-PfbInvokeHasNoArguments condition leaves the suite green, this negative is
        # not testing what it was written to protect.
        @{ Shape = 'a member call other than ToArray ($var.Clone())';        Argument = '$Param.Clone()' }
        @{ Shape = 'a ToArray() call on a composite target';                    Argument = '($Param + $Param).ToArray()' }
        @{ Shape = 'a ToArray() call carrying an argument';                     Argument = '$Param.ToArray($Param)' }
        @{ Shape = 'a method CHAIN past ToArray ($var.ToArray().ToString())';   Argument = '$Param.ToArray().ToString()' }
        # The STATIC guard's own coverage, and the only shape here that reaches it. This
        # parses as an InvokeMemberExpressionAst whose member is literally ToArray, carries
        # zero arguments, and whose Expression is a bare VariableExpressionAst -- it passes
        # every other guard and is refused ONLY by the Static test. A bare
        # `[SomeType]::ToArray()` would NOT do this job: it does not parse in argument mode.
        @{ Shape = 'a STATIC call on a variable type ($var::ToArray())';        Argument = '$Param::ToArray()' }
    ) {
        $funcAst = Get-PfbToArrayHelperAst $Argument
        Get-PfbCommonQueryParamHelperWireName -FunctionAst $funcAst -ParameterName 'Param' | Should -BeNullOrEmpty
    }

    It 'refuses a ToArray()-wrapped accumulator fed by two different parameters (never guesses ownership)' {
        # The shared-accumulator refusal must hold through the .ToArray() call exactly as it
        # does for a bare $allNames: Find-PfbAccumulatorVariable returns $null for both
        # parameters before the helper argument is ever consulted.
        $tokens = $null; $errs = $null
        $source = @'
function Test-Fixture {
    param([string[]]$First, [string[]]$Second)
    $allNames = [System.Collections.Generic.List[string]]::new()
    $queryParams = @{}
    foreach ($n in $First)  { $allNames.Add($n) }
    foreach ($n in $Second) { $allNames.Add($n) }
    Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters -Names $allNames.ToArray()
}
'@
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$errs)
        $errs.Count | Should -Be 0 -Because 'a fixture that does not parse is inert, and nothing here would go red'
        $funcAst = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | Select-Object -First 1
        Find-PfbAccumulatorVariable -FunctionAst $funcAst -ParameterName 'First' | Should -BeNullOrEmpty
        Find-PfbAccumulatorVariable -FunctionAst $funcAst -ParameterName 'Second' | Should -BeNullOrEmpty
        Get-PfbWireNameForParameter -FunctionAst $funcAst -ParameterName 'First' | Should -BeNullOrEmpty
        Get-PfbWireNameForParameter -FunctionAst $funcAst -ParameterName 'Second' | Should -BeNullOrEmpty
    }

    Context 'Get-PfbHelperArgumentSourceVariable, exercised directly' {
        # A second kill route for each guard, independent of the helper-call and fixture-file
        # paths above. Those reach the guards only through Get-PfbCommonQueryParamHelperWireName's
        # element walk, so a change to the walk -- an outer check that refuses a shape earlier --
        # can silently stop a guard from ever being reached while the suite stays green. That is
        # exactly the defect Task 1 shipped. Asserting on the extracted function removes the
        # dependency: these fail if a guard is deleted no matter what the caller does.
        BeforeAll {
            function Get-PfbHelperArgumentAst {
                param([string]$Expression)
                $tokens = $null; $errs = $null
                $ast = [System.Management.Automation.Language.Parser]::ParseInput(
                    "`$x = $Expression", [ref]$tokens, [ref]$errs)
                if ($errs.Count -gt 0) {
                    throw "Expression '$Expression' does not parse: $($errs[0].Message)"
                }
                $assignment = $ast.FindAll({
                    param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst]
                }, $true) | Select-Object -First 1
                $assignment.Right.Expression
            }
        }

        It 'accepts <Shape> and returns the source variable' -ForEach @(
            @{ Shape = 'a bare variable';                  Expression = '$allNames';           Expected = 'allNames' }
            @{ Shape = 'exact zero-argument ToArray()';    Expression = '$allNames.ToArray()'; Expected = 'allNames' }
        ) {
            Get-PfbHelperArgumentSourceVariable -ArgumentAst (Get-PfbHelperArgumentAst $Expression) |
                Should -Be $Expected
        }

        It 'refuses <Shape>' -ForEach @(
            @{ Shape = 'an argument-bearing call (ARITY guard)';   Expression = '$allNames.ToArray($n)' }
            @{ Shape = 'a static call on a variable (STATIC guard)'; Expression = '$allNames::ToArray()' }
            @{ Shape = 'a composite target (BARE-TARGET guard)';   Expression = '($allNames + $extra).ToArray()' }
            @{ Shape = 'a different member name';                  Expression = '$allNames.Clone()' }
            @{ Shape = 'a chain past ToArray (member name is ToString, not the STATIC guard)'; Expression = '$allNames.ToArray().ToString()' }
            @{ Shape = 'a member-access target';                   Expression = '$obj.Items.ToArray()' }
            # Refused by the member-name guard (member is Empty), NOT by the STATIC guard --
            # measured under mutation. `$allNames::ToArray()` above is the only shape here that
            # reaches Static. Kept as a redundant negative; the label must not overstate it.
            @{ Shape = 'a type-literal call whose member is not ToArray'; Expression = '[System.Array]::Empty()' }
        ) {
            Get-PfbHelperArgumentSourceVariable -ArgumentAst (Get-PfbHelperArgumentAst $Expression) |
                Should -BeNullOrEmpty
        }
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
            'function Test-Fixture { param([string]$Name) $body = @{}; $body["owner"] = @{ name = $Name }; $body["name"] = $Name; Invoke-PfbApiRequest -Method POST -Endpoint ''fixtures'' -Body $body }', [ref]$tokens, [ref]$errs)
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
            'function Test-Fixture { param([string[]]$Servers) $body = @{}; $body["attached_servers"] = @($Servers | ForEach-Object { @{ name = $_ } }); Invoke-PfbApiRequest -Method POST -Endpoint ''fixtures'' -Body $body }', [ref]$tokens, [ref]$errs)
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
            # Every fixture in this block is a single-line function whose payload variable is
            # $body or $queryParams. Since issue #141 Task 3 those names carry no authority on
            # their own: a variable earns a request role only by being passed to
            # Invoke-PfbApiRequest -Body/-QueryParams, so the tail below is what makes these
            # fixtures resolvable at all. It deliberately covers only $body and $queryParams,
            # which is what keeps the $nfsBody negative in this block a real negative.
            $trimmed = $Source.TrimEnd()
            if (-not $trimmed.EndsWith('}')) { throw "Fixture must end with the function's closing brace: $Source" }
            $tail = 'Invoke-PfbApiRequest -Method POST -Endpoint ''fixtures'' -Body $body -QueryParams $queryParams'
            $withRequest = $trimmed.Substring(0, $trimmed.Length - 1) + '; ' + $tail + ' }'

            $tokens = $null; $errs = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseInput($withRequest, [ref]$tokens, [ref]$errs)
            if (@($errs).Count -ne 0) { throw "Fixture source does not parse: $($errs[0].Message)`n$withRequest" }
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
    Invoke-PfbApiRequest -Method POST -Endpoint 'conditional' -QueryParams $queryParams
}
'@, [ref]$tokens, [ref]$errs)
        @($errs).Count | Should -Be 0
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
        # The trailing request call gives $queryParams a genuine Query role, so each case is
        # refused by its SHAPE rule and not merely because the payload variable is inert.
        $source = 'function Test-Fixture { param([Nullable[bool]]$Param, [Nullable[bool]]$Other) ' + $Body +
            '; Invoke-PfbApiRequest -Method POST -Endpoint ''fixtures'' -QueryParams $queryParams }'
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$errs)
        @($errs).Count | Should -Be 0
        $funcAst = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | Select-Object -First 1
        Get-PfbWireNameForParameter -FunctionAst $funcAst -ParameterName 'Param' -IsBooleanLikeParameter | Should -BeNullOrEmpty
    }
}

Describe 'Exact boolean wire-value transforms (issue #141)' {
    BeforeAll {
        function Get-TestBooleanWireFunctionAst {
            param([string]$Source)
            # Since issue #141 Task 3 a payload variable earns its request role from being
            # passed to Invoke-PfbApiRequest, not from being called $body/$queryParams, so
            # the appended tail is what makes these fixtures resolvable at all.
            $trimmed = $Source.TrimEnd()
            if (-not $trimmed.EndsWith('}')) { throw "Fixture must end with the function's closing brace: $Source" }
            $tail = 'Invoke-PfbApiRequest -Method POST -Endpoint ''fixtures'' -Body $body -QueryParams $queryParams'
            $withRequest = $trimmed.Substring(0, $trimmed.Length - 1) + '; ' + $tail + ' }'

            $tokens = $null; $errs = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseInput($withRequest, [ref]$tokens, [ref]$errs)
            if (@($errs).Count -ne 0) { throw "Fixture source does not parse: $($errs[0].Message)`n$withRequest" }
            $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | Select-Object -First 1
        }
    }

    It 'resolves an exact [bool] cast through an index assignment without guessing the wire key from the parameter name' {
        $funcAst = Get-TestBooleanWireFunctionAst 'function Test-Fixture { param([switch]$Param) $body = @{}; $body[''destroyed''] = [bool]$Param }'
        $result = Get-PfbWireNameForParameter -FunctionAst $funcAst -ParameterName 'Param' -IsBooleanLikeParameter
        $result.WireName | Should -Be 'destroyed'
        $result.TargetVariable | Should -Be 'body'
    }

    It 'resolves the exact zero-argument ToString/ToLower chain through an index assignment without guessing the wire key from the parameter name' {
        $funcAst = Get-TestBooleanWireFunctionAst 'function Test-Fixture { param([switch]$Param) $queryParams = @{}; $queryParams[''flagged''] = ([bool]$Param).ToString().ToLower() }'
        $result = Get-PfbWireNameForParameter -FunctionAst $funcAst -ParameterName 'Param' -IsBooleanLikeParameter
        $result.WireName | Should -Be 'flagged'
        $result.TargetVariable | Should -Be 'queryParams'
    }

    It 'resolves the new exact forms through the hashtable-literal value path without guessing the wire key' -ForEach @(
        @{ WireName = 'destroyed'; TargetVariable = 'body';        Value = '[bool]$Param' }
        @{ WireName = 'flagged';   TargetVariable = 'queryParams'; Value = '([bool]$Param).ToString().ToLower()' }
    ) {
        $source = 'function Test-Fixture { param([switch]$Param) $' + $TargetVariable + ' = @{ ''' + $WireName + ''' = ' + $Value + ' } }'
        $funcAst = Get-TestBooleanWireFunctionAst $source
        $result = Get-PfbWireNameForParameter -FunctionAst $funcAst -ParameterName 'Param' -IsBooleanLikeParameter
        $result.WireName | Should -Be $WireName
        $result.TargetVariable | Should -Be $TargetVariable
    }

    It 'accepts the <CastType> spelling as the Boolean cast type' -ForEach @(
        @{ CastType = 'Boolean' }
        @{ CastType = 'System.Boolean' }
    ) {
        $source = 'function Test-Fixture { param([switch]$Param) $body = @{}; $body[''destroyed''] = [' + $CastType + ']$Param }'
        $funcAst = Get-TestBooleanWireFunctionAst $source
        (Get-PfbWireNameForParameter -FunctionAst $funcAst -ParameterName 'Param' -IsBooleanLikeParameter).WireName | Should -Be 'destroyed'
    }

    It 'refuses <Case>' -ForEach @(
        @{ Case = 'a cast rooted at a different variable';                       Value = '[bool]$Other' }
        @{ Case = 'a cast of a composite operand';                               Value = '[bool]($Param -or $Other)' }
        @{ Case = 'a method chain rooted at a different variable';               Value = '([bool]$Other).ToString().ToLower()' }
        @{ Case = 'a ToString call carrying an argument without the full chain';  Value = '([bool]$Param).ToString(''x'')' }
        @{ Case = 'a ToString call carrying an argument in the full chain';        Value = '([bool]$Param).ToString("G").ToLower()' }
        @{ Case = 'a ToLower call carrying an argument';                           Value = '([bool]$Param).ToString().ToLower([System.Globalization.CultureInfo]::InvariantCulture)' }
        @{ Case = 'a method chain ending in a member other than ToLower';          Value = '([bool]$Param).ToString().Trim()' }
        @{ Case = 'a unary expression over member access';                        Value = '(-not $Param.IsPresent)' }
        @{ Case = 'string interpolation that merely mentions the parameter';      Value = '"$Param"' }
    ) {
        $source = 'function Test-Fixture { param([switch]$Param, [switch]$Other) $body = @{}; $body[''k''] = ' + $Value + ' }'
        $funcAst = Get-TestBooleanWireFunctionAst $source
        Get-PfbWireNameForParameter -FunctionAst $funcAst -ParameterName 'Param' -IsBooleanLikeParameter | Should -BeNullOrEmpty
    }

    It 'refuses <Shape> when -IsBooleanLikeParameter is absent for a string parameter' -ForEach @(
        @{ Shape = 'an exact [bool] cast';                         Value = '[bool]$Param' }
        @{ Shape = 'the exact zero-argument ToString/ToLower chain'; Value = '([bool]$Param).ToString().ToLower()' }
    ) {
        $source = 'function Test-Fixture { param([string]$Param) $body = @{}; $body[''k''] = ' + $Value + ' }'
        $funcAst = Get-TestBooleanWireFunctionAst $source
        Get-PfbWireNameForParameter -FunctionAst $funcAst -ParameterName 'Param' | Should -BeNullOrEmpty
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

# =====================================================================================
# issue #141 Task 3 -- argument-proven payload role tracing
#
# The resolver used to decide a variable's request role from its NAME, via a
# `switch ($TargetVariable) { 'body' {...} 'queryParams' {...} }` trust gate. That is an
# inference from a name, which the never-guess contract forbids: it both missed every
# cmdlet using $q / $payload / $destroyQuery and would have mislabelled a variable called
# $body that was actually passed to -QueryParams. The role is now read from the request
# argument itself.
#
# Every fixture below deliberately decouples the payload variable name, the parameter name
# and the wire key from one another, and several actively CONTRADICT the retired gate, so
# no assertion here can pass by reading a name.
# =====================================================================================

Describe 'Task 3 fixture bed' {
    It 'refuses a fixture source that does not parse' {
        # Get-PfbCmdletParameterInventory discards its own $parseErrors, so an unparseable
        # fixture is not a failing test -- it is a string the resolver never reads, and every
        # assertion over it passes vacuously.
        { Get-PfbRoleFixtureAst @('function Test-Fixture {', '    $q = @{', '}') } |
            Should -Throw -ExpectedMessage '*does not parse*'
    }

    It 'refuses a fixture source that defines no function' {
        { Get-PfbRoleFixtureAst @('$q = @{}') } | Should -Throw -ExpectedMessage '*defines no function*'
    }
}

Describe 'Get-PfbRequestRoleForVariable: role is proven by the request argument (issue #141 Task 3, Steps 1-2)' {

    It 'derives <Expected> for $<Variable> passed as "<PayloadArgument>"' -ForEach @(
        # Step 1 -- names that carry no role information at all.
        @{ Variable = 'q'; PayloadArgument = '-QueryParams $q'; Expected = 'Query' }
        @{ Variable = 'payload'; PayloadArgument = '-Body $payload'; Expected = 'Body' }
        @{ Variable = 'destroyQuery'; PayloadArgument = '-QueryParams $destroyQuery'; Expected = 'Query' }
        # Step 1 -- the colon argument form parks the value on CommandParameterAst.Argument
        # instead of the next command element. Reading only the next element misses it.
        @{ Variable = 'payload'; PayloadArgument = '-Body:$payload'; Expected = 'Body' }
        @{ Variable = 'q'; PayloadArgument = '-QueryParams:$q'; Expected = 'Query' }
        # Step 2 -- the name-reversal detector. This class has zero current occurrences in
        # Public/, which is exactly why it needs a permanent test rather than a survey: under
        # the retired name gate both of these resolved to the surface their NAME implied,
        # which is the opposite of the surface they are actually sent on.
        @{ Variable = 'body'; PayloadArgument = '-QueryParams $body'; Expected = 'Query' }
        @{ Variable = 'queryParams'; PayloadArgument = '-Body $queryParams'; Expected = 'Body' }
    ) {
        $funcAst = Get-PfbRoleFixtureAst (New-PfbRoleFixtureSource -Variable $Variable -PayloadArgument $PayloadArgument)
        $role = Get-PfbRequestRoleForVariable -FunctionAst $funcAst -TargetVariable $Variable
        $role | Should -Not -BeNullOrEmpty
        $role.TargetVariable | Should -Be $Variable
        $role.WireSurface | Should -Be $Expected
        $role.Method | Should -Be 'PATCH'
        $role.Endpoint | Should -Be 'widgets'
    }

    It 'derives Body for a parameter handed straight to -Body with no intermediate variable' {
        $funcAst = Get-PfbRoleFixtureAst @(
            'function Test-Fixture {'
            '    param([hashtable]$Tags)'
            '    Invoke-PfbApiRequest -Method POST -Endpoint ''widgets'' -Body $Tags'
            '}'
        )
        $role = Get-PfbRequestRoleForVariable -FunctionAst $funcAst -TargetVariable 'Tags'
        $role.WireSurface | Should -Be 'Body'
        $role.Method | Should -Be 'POST'
        $role.Endpoint | Should -Be 'widgets'
    }

    It 'reads the colon argument form on -Method and -Endpoint too' {
        $funcAst = Get-PfbRoleFixtureAst @(
            'function Test-Fixture {'
            '    param([string]$Zeta)'
            '    $q = @{}'
            '    $q[''alpha''] = $Zeta'
            '    Invoke-PfbApiRequest -Method:''PATCH'' -Endpoint:''widgets'' -QueryParams:$q'
            '}'
        )
        $role = Get-PfbRequestRoleForVariable -FunctionAst $funcAst -TargetVariable 'q'
        $role.WireSurface | Should -Be 'Query'
        $role.Method | Should -Be 'PATCH'
        $role.Endpoint | Should -Be 'widgets'
    }
}

Describe 'Get-PfbRequestRoleForVariable: ambiguity and refusal (issue #141 Task 3, Step 3)' {

    It 'keeps the surface but nulls the operation when the same variable feeds two different <Differs>' -ForEach @(
        @{ Differs = 'endpoints'; SecondCall = '    Invoke-PfbApiRequest -Method PATCH -Endpoint ''gadgets'' -QueryParams $q' }
        @{ Differs = 'methods'; SecondCall = '    Invoke-PfbApiRequest -Method DELETE -Endpoint ''widgets'' -QueryParams $q' }
    ) {
        $funcAst = Get-PfbRoleFixtureAst @(
            'function Test-Fixture {'
            '    param([string]$Zeta)'
            '    $q = @{}'
            '    $q[''alpha''] = $Zeta'
            '    Invoke-PfbApiRequest -Method PATCH -Endpoint ''widgets'' -QueryParams $q'
            $SecondCall
            '}'
        )
        $role = Get-PfbRequestRoleForVariable -FunctionAst $funcAst -TargetVariable 'q'
        $role | Should -Not -BeNullOrEmpty
        $role.WireSurface | Should -Be 'Query'
        $role.Method | Should -BeNullOrEmpty
        $role.Endpoint | Should -BeNullOrEmpty
    }

    It 'collapses two IDENTICAL operations to one resolution rather than calling them ambiguous' {
        $funcAst = Get-PfbRoleFixtureAst @(
            'function Test-Fixture {'
            '    param([string]$Zeta)'
            '    $q = @{}'
            '    $q[''alpha''] = $Zeta'
            '    if ($Zeta) { Invoke-PfbApiRequest -Method PATCH -Endpoint ''widgets'' -QueryParams $q }'
            '    else { Invoke-PfbApiRequest -Method PATCH -Endpoint ''widgets'' -QueryParams $q }'
            '}'
        )
        $role = Get-PfbRequestRoleForVariable -FunctionAst $funcAst -TargetVariable 'q'
        $role.WireSurface | Should -Be 'Query'
        $role.Method | Should -Be 'PATCH'
        $role.Endpoint | Should -Be 'widgets'
    }

    It 'returns $null when one variable is sent on BOTH surfaces, across two calls' {
        $funcAst = Get-PfbRoleFixtureAst @(
            'function Test-Fixture {'
            '    param([string]$Zeta)'
            '    $shared = @{}'
            '    $shared[''alpha''] = $Zeta'
            '    Invoke-PfbApiRequest -Method PATCH -Endpoint ''widgets'' -Body $shared'
            '    Invoke-PfbApiRequest -Method PATCH -Endpoint ''widgets'' -QueryParams $shared'
            '}'
        )
        Get-PfbRequestRoleForVariable -FunctionAst $funcAst -TargetVariable 'shared' | Should -BeNullOrEmpty
    }

    It 'returns $null when one variable is sent on BOTH surfaces of a single call' {
        $funcAst = Get-PfbRoleFixtureAst @(
            'function Test-Fixture {'
            '    param([string]$Zeta)'
            '    $shared = @{}'
            '    $shared[''alpha''] = $Zeta'
            '    Invoke-PfbApiRequest -Method PATCH -Endpoint ''widgets'' -Body $shared -QueryParams $shared'
            '}'
        )
        Get-PfbRequestRoleForVariable -FunctionAst $funcAst -TargetVariable 'shared' | Should -BeNullOrEmpty
    }

    It 'returns $null for a variable with zero matching calls: <Case>' -ForEach @(
        @{ Case = 'the request sends a different variable'
            Call = '    Invoke-PfbApiRequest -Method GET -Endpoint ''widgets'' -QueryParams $other'
        }
        @{ Case = 'the variable is bound to a parameter that is not a payload'
            Call = '    Invoke-PfbApiRequest -Method GET -Endpoint ''widgets'' -Headers $q'
        }
        @{ Case = 'the payload goes to some other command entirely'
            Call = '    Send-FixtureElsewhere -Method GET -Endpoint ''widgets'' -QueryParams $q'
        }
    ) {
        $funcAst = Get-PfbRoleFixtureAst @(
            'function Test-Fixture {'
            '    param([string]$Zeta)'
            '    $q = @{}'
            '    $q[''alpha''] = $Zeta'
            '    $other = @{}'
            $Call
            '}'
        )
        Get-PfbRequestRoleForVariable -FunctionAst $funcAst -TargetVariable 'q' | Should -BeNullOrEmpty
    }

    It 'returns $null when the payload argument is not the bare variable: <Case>' -ForEach @(
        # Each of these routes through the variable actually under test, so an over-matching
        # guard -- one that credits any -Body argument, or any argument merely MENTIONING the
        # variable -- resolves it and the test goes red.
        @{ Case = 'a hashtable literal'; Argument = '@{}'; Variable = 'payload' }
        @{ Case = 'a member access on it'; Argument = '$wrapper.Inner'; Variable = 'wrapper' }
        @{ Case = 'an expression containing it'; Argument = '($payload + @{})'; Variable = 'payload' }
        @{ Case = 'an index into it'; Argument = '$payload[''alpha'']'; Variable = 'payload' }
    ) {
        $v = '$' + $Variable
        $funcAst = Get-PfbRoleFixtureAst @(
            'function Test-Fixture {'
            '    param([string]$Zeta)'
            ('    ' + $v + ' = @{}')
            ('    ' + $v + '[''alpha''] = $Zeta')
            ('    Invoke-PfbApiRequest -Method POST -Endpoint ''widgets'' -Body ' + $Argument)
            '}'
        )
        Get-PfbRequestRoleForVariable -FunctionAst $funcAst -TargetVariable $Variable | Should -BeNullOrEmpty
    }

    It 'keeps the surface but nulls the operation when one matching call has a nonliteral <Nonliteral>' -ForEach @(
        @{ Nonliteral = '-Method'
            FirstCall = '    Invoke-PfbApiRequest -Method $Verb -Endpoint ''widgets'' -QueryParams $q'
        }
        @{ Nonliteral = '-Endpoint'
            FirstCall = '    Invoke-PfbApiRequest -Method PATCH -Endpoint $Route -QueryParams $q'
        }
    ) {
        # The literal sibling call below is the trap: the retired implementation skipped any
        # call it could not fully read, so the one call it COULD read won outright and the
        # unread landing vanished from the report. An unreadable landing is still a landing.
        $funcAst = Get-PfbRoleFixtureAst @(
            'function Test-Fixture {'
            '    param([string]$Zeta, [string]$Verb, [string]$Route)'
            '    $q = @{}'
            '    $q[''alpha''] = $Zeta'
            $FirstCall
            '    Invoke-PfbApiRequest -Method GET -Endpoint ''gizmos'' -QueryParams $q'
            '}'
        )
        $role = Get-PfbRequestRoleForVariable -FunctionAst $funcAst -TargetVariable 'q'
        $role | Should -Not -BeNullOrEmpty
        $role.WireSurface | Should -Be 'Query'
        $role.Method | Should -BeNullOrEmpty
        $role.Endpoint | Should -BeNullOrEmpty
    }

    It 'nulls the operation for a LONE call whose <Nonliteral> is nonliteral' -ForEach @(
        @{ Nonliteral = '-Method'; Call = '    Invoke-PfbApiRequest -Method $Verb -Endpoint ''widgets'' -QueryParams $q' }
        @{ Nonliteral = '-Endpoint'; Call = '    Invoke-PfbApiRequest -Method PATCH -Endpoint $Route -QueryParams $q' }
    ) {
        # Separate from the sibling-call case above, and not redundant with it: with only one
        # call there is no second operation to disagree with, so this is the only shape that
        # fails if the reader takes a nonliteral argument's TEXT for its value.
        $funcAst = Get-PfbRoleFixtureAst @(
            'function Test-Fixture {'
            '    param([string]$Zeta, [string]$Verb, [string]$Route)'
            '    $q = @{}'
            '    $q[''alpha''] = $Zeta'
            $Call
            '}'
        )
        $role = Get-PfbRequestRoleForVariable -FunctionAst $funcAst -TargetVariable 'q'
        $role.WireSurface | Should -Be 'Query'
        $role.Method | Should -BeNullOrEmpty
        $role.Endpoint | Should -BeNullOrEmpty
    }

    It 'nulls the operation when a matching call omits -Method or -Endpoint altogether' {
        $funcAst = Get-PfbRoleFixtureAst @(
            'function Test-Fixture {'
            '    param([string]$Zeta)'
            '    $q = @{}'
            '    $q[''alpha''] = $Zeta'
            '    Invoke-PfbApiRequest -Endpoint ''widgets'' -QueryParams $q'
            '    Invoke-PfbApiRequest -Method GET -Endpoint ''widgets'' -QueryParams $q'
            '}'
        )
        $role = Get-PfbRequestRoleForVariable -FunctionAst $funcAst -TargetVariable 'q'
        $role.WireSurface | Should -Be 'Query'
        $role.Method | Should -BeNullOrEmpty
        $role.Endpoint | Should -BeNullOrEmpty
    }

    It 'returns $null for a trailing payload switch with no argument at all' {
        # Test-bed rule 5: a zero-argument invocation exposes Arguments as $null and
        # @($null).Count is 1, so the arity guard has to test the null case before wrapping.
        # Here the analogous trap is a -Body with nothing after it, at the end of the call.
        $funcAst = Get-PfbRoleFixtureAst @(
            'function Test-Fixture {'
            '    param([string]$Zeta)'
            '    $q = @{}'
            '    $q[''alpha''] = $Zeta'
            '    Invoke-PfbApiRequest -Method GET -Endpoint ''widgets'' -QueryParams'
            '}'
        )
        Get-PfbRequestRoleForVariable -FunctionAst $funcAst -TargetVariable 'q' | Should -BeNullOrEmpty
    }
}

Describe 'Get-PfbWireNameForParameter: multi-landing abstention (issue #141 Task 3, Step 4)' {

    BeforeAll {
        # Mirrors Remove-PfbFileSystem -DeleteLinkOnEradication, the one live shape where a
        # single parameter writes the same key into two different payload variables that reach
        # two different operations. Names are decoupled: the parameter is -Purge, the key is
        # 'alpha_beta', the endpoint is 'widgets'.
        #
        # $destroyQuery reaches exactly one operation (PATCH widgets). $queryParams reaches two
        # (PATCH widgets and DELETE widgets) and is therefore itself operation-ambiguous. So
        # the two candidate tuples are
        #     (alpha_beta, Query, PATCH, widgets)   via $destroyQuery
        #     (alpha_beta, Query, <null>, <null>)   via $queryParams
        # and only WireName and WireSurface are common to both.
        $script:destroyBranch = @(
            '        $destroyQuery = @{} + $queryParams'
            '        if ($Purge) { $destroyQuery[''alpha_beta''] = ''true'' }'
            '        $disableBody = @{ nfs = @{ enabled = $false } }'
            '        Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint ''widgets'' -Body $disableBody -QueryParams $queryParams'
            '        $body = @{ destroyed = $true }'
            '        Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint ''widgets'' -Body $body -QueryParams $destroyQuery'
        )
        $script:eradicateBranch = @(
            '        if ($Purge) { $queryParams[''alpha_beta''] = ''true'' }'
            '        Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint ''widgets'' -QueryParams $queryParams'
        )

        function script:New-PfbMultiLandingFixture {
            param([Parameter(Mandatory)][ValidateSet('DestroyFirst', 'EradicateFirst')][string]$Order)
            $first = if ($Order -eq 'DestroyFirst') { $script:destroyBranch } else { $script:eradicateBranch }
            $second = if ($Order -eq 'DestroyFirst') { $script:eradicateBranch } else { $script:destroyBranch }
            $condition = if ($Order -eq 'DestroyFirst') { '    if (-not $Purge) {' } else { '    if ($Purge) {' }
            return @(
                'function Remove-FixtureThing {'
                '    [CmdletBinding()]'
                '    param([string]$Zeta, [switch]$Purge, [PSCustomObject]$Array)'
                '    $queryParams = @{}'
                '    if ($Zeta) { $queryParams[''names''] = $Zeta }'
                $condition
                $first
                '    }'
                '    else {'
                $second
                '    }'
                '}'
            )
        }
    }

    It 'preserves only the facts common to every landing, with the branches in <Order> order' -ForEach @(
        @{ Order = 'DestroyFirst' }
        @{ Order = 'EradicateFirst' }
    ) {
        $funcAst = Get-PfbRoleFixtureAst (New-PfbMultiLandingFixture -Order $Order)
        $wire = Get-PfbWireNameForParameter -FunctionAst $funcAst -ParameterName 'Purge' -IsBooleanLikeParameter
        $wire | Should -Not -BeNullOrEmpty
        $wire.WireName | Should -Be 'alpha_beta'
        $wire.WireSurface | Should -Be 'Query'
        $wire.Method | Should -BeNullOrEmpty
        $wire.Endpoint | Should -BeNullOrEmpty
    }

    It 'gives the identical answer whichever branch comes first in the source' {
        # Source order is the specific failure mode here. Retiring the name gate makes
        # $destroyQuery the earlier AST match, so a first-match resolver would confidently
        # report PATCH/widgets and hide the DELETE landing entirely.
        $first = Get-PfbWireNameForParameter -FunctionAst (Get-PfbRoleFixtureAst (New-PfbMultiLandingFixture -Order 'DestroyFirst')) -ParameterName 'Purge' -IsBooleanLikeParameter
        $second = Get-PfbWireNameForParameter -FunctionAst (Get-PfbRoleFixtureAst (New-PfbMultiLandingFixture -Order 'EradicateFirst')) -ParameterName 'Purge' -IsBooleanLikeParameter
        foreach ($component in 'WireName', 'WireSurface', 'Method', 'Endpoint', 'TargetVariable') {
            $first.$component | Should -Be $second.$component -Because "component $component must not depend on source order"
        }
    }

    It 'does not let a weaker idiom answer after a stronger one has abstained' {
        # $q is keyed twice under different names, so the index tier abstains outright. The
        # hashtable literal in the same function offers a third name. Falling through to it
        # would be first-match arbitration wearing a different hat: the strongest evidence
        # was ambiguous, and a weaker idiom does not get to break the tie.
        $funcAst = Get-PfbRoleFixtureAst @(
            'function Test-Fixture {'
            '    param([string]$Zeta)'
            '    $q = @{ ''gamma'' = $Zeta }'
            '    $q[''alpha''] = $Zeta'
            '    $q[''beta''] = $Zeta'
            '    Invoke-PfbApiRequest -Method PATCH -Endpoint ''widgets'' -QueryParams $q'
            '}'
        )
        # Control: the weaker idiom really would answer 'gamma' if it were consulted.
        (Get-PfbHashtableLiteralWireNameForParameter -FunctionAst $funcAst -ParameterName 'Zeta').WireName | Should -Be 'gamma'
        Get-PfbWireNameForParameter -FunctionAst $funcAst -ParameterName 'Zeta' | Should -BeNullOrEmpty
    }

    It 'nulls the METHOD too when the landings agree on it but disagree on the endpoint' {
        # Half an operation is not an operation. The two landings below share their method,
        # so a component-wise merge that forgot to pair method with endpoint would emit
        # PATCH against no endpoint at all -- a fact no consumer can use and no call makes.
        $funcAst = Get-PfbRoleFixtureAst @(
            'function Test-Fixture {'
            '    param([string]$Zeta)'
            '    $q = @{}'
            '    $r = @{}'
            '    $q[''alpha''] = $Zeta'
            '    $r[''alpha''] = $Zeta'
            '    Invoke-PfbApiRequest -Method PATCH -Endpoint ''widgets'' -QueryParams $q'
            '    Invoke-PfbApiRequest -Method PATCH -Endpoint ''gadgets'' -QueryParams $r'
            '}'
        )
        $wire = Get-PfbWireNameForParameter -FunctionAst $funcAst -ParameterName 'Zeta'
        $wire.WireName | Should -Be 'alpha'
        $wire.WireSurface | Should -Be 'Query'
        $wire.Method | Should -BeNullOrEmpty
        $wire.Endpoint | Should -BeNullOrEmpty
    }

    It 'collapses repeated occurrences of the SAME tuple to one complete resolution' {
        $funcAst = Get-PfbRoleFixtureAst @(
            'function Test-Fixture {'
            '    param([string]$Zeta)'
            '    $q = @{}'
            '    if ($Zeta) { $q[''alpha''] = $Zeta }'
            '    else { $q[''alpha''] = $Zeta }'
            '    Invoke-PfbApiRequest -Method PATCH -Endpoint ''widgets'' -QueryParams $q'
            '}'
        )
        $wire = Get-PfbWireNameForParameter -FunctionAst $funcAst -ParameterName 'Zeta'
        $wire.WireName | Should -Be 'alpha'
        $wire.WireSurface | Should -Be 'Query'
        $wire.Method | Should -Be 'PATCH'
        $wire.Endpoint | Should -Be 'widgets'
    }

    It 'collapses the same tuple reached through two DIFFERENT variables to one complete resolution' {
        # Two payload variables, identical key, identical surface, identical operation. The
        # tuple is what is deduplicated, so this is one landing, not an ambiguity -- but the
        # variable itself is not common to both, so TargetVariable is not claimed.
        $funcAst = Get-PfbRoleFixtureAst @(
            'function Test-Fixture {'
            '    param([string]$Zeta)'
            '    $q = @{}'
            '    $r = @{}'
            '    if ($Zeta) { $q[''alpha''] = $Zeta }'
            '    if ($Zeta) { $r[''alpha''] = $Zeta }'
            '    Invoke-PfbApiRequest -Method PATCH -Endpoint ''widgets'' -QueryParams $q'
            '    Invoke-PfbApiRequest -Method PATCH -Endpoint ''widgets'' -QueryParams $r'
            '}'
        )
        $wire = Get-PfbWireNameForParameter -FunctionAst $funcAst -ParameterName 'Zeta'
        $wire.WireName | Should -Be 'alpha'
        $wire.WireSurface | Should -Be 'Query'
        $wire.Method | Should -Be 'PATCH'
        $wire.Endpoint | Should -Be 'widgets'
        $wire.TargetVariable | Should -BeNullOrEmpty
    }

    It 'nulls the surface when one parameter lands on both Body and Query through different variables' {
        $funcAst = Get-PfbRoleFixtureAst @(
            'function Test-Fixture {'
            '    param([string]$Zeta)'
            '    $q = @{}'
            '    $p = @{}'
            '    if ($Zeta) { $q[''alpha''] = $Zeta }'
            '    if ($Zeta) { $p[''alpha''] = $Zeta }'
            '    Invoke-PfbApiRequest -Method PATCH -Endpoint ''widgets'' -QueryParams $q -Body $p'
            '}'
        )
        $wire = Get-PfbWireNameForParameter -FunctionAst $funcAst -ParameterName 'Zeta'
        $wire.WireName | Should -Be 'alpha'
        $wire.WireSurface | Should -Be 'Unresolved'
        $wire.Method | Should -Be 'PATCH'
        $wire.Endpoint | Should -Be 'widgets'
    }

    It 'refuses the whole resolution when the candidates do not even agree on the wire name' {
        # Nothing nameable is proven, so there is no wire name to report. Returning a record
        # with a null WireName would also suppress the accumulator retry in the inventory.
        $funcAst = Get-PfbRoleFixtureAst @(
            'function Test-Fixture {'
            '    param([string]$Zeta)'
            '    $q = @{}'
            '    $q[''alpha''] = $Zeta'
            '    $q[''beta''] = $Zeta'
            '    Invoke-PfbApiRequest -Method PATCH -Endpoint ''widgets'' -QueryParams $q'
            '}'
        )
        Get-PfbWireNameForParameter -FunctionAst $funcAst -ParameterName 'Zeta' | Should -BeNullOrEmpty
    }

    It 'skips a landing whose payload variable has no proven role at all' {
        # $nfsBody is keyed but never sent, so crediting it would name a field that does not
        # exist at the top level of any request this cmdlet makes.
        $funcAst = Get-PfbRoleFixtureAst @(
            'function Test-Fixture {'
            '    param([string]$Zeta)'
            '    $nfsBody = @{}'
            '    $nfsBody[''alpha''] = $Zeta'
            '    $q = @{}'
            '    $q[''beta''] = $Zeta'
            '    Invoke-PfbApiRequest -Method PATCH -Endpoint ''widgets'' -QueryParams $q'
            '}'
        )
        $wire = Get-PfbWireNameForParameter -FunctionAst $funcAst -ParameterName 'Zeta'
        $wire.WireName | Should -Be 'beta'
        $wire.WireSurface | Should -Be 'Query'
    }
}

Describe 'Get-PfbEndpointForVariable delegates to the role trace (issue #141 Task 3)' {
    It 'resolves an arbitrarily named payload variable, which the retired name switch could not' {
        $funcAst = Get-PfbRoleFixtureAst (New-PfbRoleFixtureSource -Variable 'q' -PayloadArgument '-QueryParams $q')
        $result = Get-PfbEndpointForVariable -FunctionAst $funcAst -TargetVariable 'q'
        $result.Method | Should -Be 'PATCH'
        $result.Endpoint | Should -Be 'widgets'
    }

    It 'returns $null when the surface is proven but the operation is not' {
        $funcAst = Get-PfbRoleFixtureAst @(
            'function Test-Fixture {'
            '    param([string]$Zeta)'
            '    $q = @{}'
            '    $q[''alpha''] = $Zeta'
            '    Invoke-PfbApiRequest -Method PATCH -Endpoint ''widgets'' -QueryParams $q'
            '    Invoke-PfbApiRequest -Method PATCH -Endpoint ''gadgets'' -QueryParams $q'
            '}'
        )
        Get-PfbEndpointForVariable -FunctionAst $funcAst -TargetVariable 'q' | Should -BeNullOrEmpty
    }
}

Describe 'Real-tree characterization of the argument-proven role (issue #141 Task 3, Step 7)' {
    # Every input set below is derived at RUN TIME from the real Public/ tree. Nothing here
    # pins a row count: a count would either go stale on the next cmdlet added or, worse,
    # pass while the rows underneath it changed.

    BeforeAll {
        $script:realFunctions = @{}
        foreach ($file in @(Get-ChildItem -Path $script:publicDir -Filter '*.ps1' -Recurse -File)) {
            $tokens = $null; $errs = $null
            $fileAst = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errs)
            @($errs).Count | Should -Be 0 -Because "$($file.FullName) must parse for its functions to be analysable at all"
            foreach ($fn in $fileAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
                $script:realFunctions[$fn.Name] = $fn
            }
        }

        $script:realInventory = @(Get-PfbCmdletParameterInventory -PublicDirectory $script:publicDir)
        $script:realTyped = @($script:realInventory | Where-Object { $_.Surface -eq 'Typed' })

        # Distinct variable names that receive a literal string-keyed index assignment of the
        # given wire key inside one function -- used to prove that a Typed row with NO target
        # variable is a genuine multi-landing abstention rather than a lost fact.
        function script:Get-PfbTestWireKeyVariable {
            param($FunctionAst, [string]$WireName)
            $found = [System.Collections.Generic.List[string]]::new()
            foreach ($assignment in $FunctionAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)) {
                $index = $assignment.Left -as [System.Management.Automation.Language.IndexExpressionAst]
                if (-not $index) { continue }
                if ($index.Index -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) { continue }
                if ($index.Index.Value -ne $WireName) { continue }
                $target = $index.Target -as [System.Management.Automation.Language.VariableExpressionAst]
                if (-not $target) { continue }
                if (-not $found.Contains($target.VariablePath.UserPath)) { $found.Add($target.VariablePath.UserPath) }
            }
            return $found
        }
    }

    It 'gives every Typed row target variable a role whose surface and operation match the row' {
        $checked = 0
        $offenders = [System.Collections.Generic.List[string]]::new()

        foreach ($record in $script:realTyped) {
            if (-not $record.TargetVariable) { continue }
            $checked++
            $key = '{0}|{1}|{2}|{3}' -f $record.Cmdlet, $record.Parameter, $record.WireName, $record.TargetVariable

            $funcAst = $script:realFunctions[$record.Cmdlet]
            if (-not $funcAst) { $offenders.Add("MISSINGFUNC $key"); continue }

            $role = Get-PfbRequestRoleForVariable -FunctionAst $funcAst -TargetVariable $record.TargetVariable
            if (-not $role) { $offenders.Add("NOROLE $key"); continue }

            if ($role.WireSurface -ne $record.WireSurface) {
                $offenders.Add(('SURFACE {0} role={1} row={2}' -f $key, $role.WireSurface, $record.WireSurface))
            }
            if ($role.Method -ne $record.Method -or $role.Endpoint -ne $record.Endpoint) {
                $offenders.Add(('OPERATION {0} role={1}|{2} row={3}|{4}' -f $key, $role.Method, $role.Endpoint, $record.Method, $record.Endpoint))
            }
        }

        $checked | Should -BeGreaterThan 0 -Because 'an empty input set would make this assertion vacuous'
        $offenders -join "`n" | Should -BeNullOrEmpty
    }

    It 'leaves a Typed row without a target variable only where two or more payload variables carry that wire key' {
        # The abstention path: when a parameter lands on more than one payload variable the
        # resolver keeps only the facts every candidate agrees on, so TargetVariable drops
        # out. That must never be how an ordinary single-landing row looks.
        $offenders = [System.Collections.Generic.List[string]]::new()

        foreach ($record in $script:realTyped) {
            if ($record.TargetVariable) { continue }
            $funcAst = $script:realFunctions[$record.Cmdlet]
            $variables = @(script:Get-PfbTestWireKeyVariable -FunctionAst $funcAst -WireName $record.WireName)
            if ($variables.Count -lt 2) {
                $offenders.Add(('{0}|{1}|{2} carriers={3}' -f $record.Cmdlet, $record.Parameter, $record.WireName, ($variables -join ',')))
            }
        }

        $offenders -join "`n" | Should -BeNullOrEmpty
    }

    It 'finds Remove-PfbFileSystem to be the only cmdlet passing more than one distinct variable to a single request surface' {
        # This is a characterization of the tree as it stands, not a rule the resolver may
        # rely on: the arbitration is general, and nothing in tools/lib names this cmdlet.
        $surfaceParameter = @{ Body = 'Body'; Query = 'QueryParams' }
        $multi = [System.Collections.Generic.List[string]]::new()

        foreach ($name in $script:realFunctions.Keys) {
            $funcAst = $script:realFunctions[$name]
            foreach ($surface in $surfaceParameter.Keys) {
                $parameterName = $surfaceParameter[$surface]
                $variables = [System.Collections.Generic.List[string]]::new()

                foreach ($command in $funcAst.FindAll({
                            param($n)
                            $n -is [System.Management.Automation.Language.CommandAst] -and
                            $n.GetCommandName() -eq 'Invoke-PfbApiRequest'
                        }, $true)) {
                    $elements = @($command.CommandElements)
                    for ($i = 0; $i -lt $elements.Count; $i++) {
                        $element = $elements[$i] -as [System.Management.Automation.Language.CommandParameterAst]
                        if (-not $element -or $element.ParameterName -ne $parameterName) { continue }
                        $argument = $element.Argument
                        if (-not $argument -and ($i + 1) -lt $elements.Count -and
                            $elements[$i + 1] -isnot [System.Management.Automation.Language.CommandParameterAst]) {
                            $argument = $elements[$i + 1]
                        }
                        $variable = $argument -as [System.Management.Automation.Language.VariableExpressionAst]
                        if ($variable -and -not $variables.Contains($variable.VariablePath.UserPath)) {
                            $variables.Add($variable.VariablePath.UserPath)
                        }
                    }
                }

                if ($variables.Count -gt 1) {
                    $multi.Add(('{0} {1}: {2}' -f $name, $surface, (($variables | Sort-Object) -join ',')))
                }
            }
        }

        @($multi | ForEach-Object { ($_ -split ' ')[0] } | Select-Object -Unique) | Should -Be @('Remove-PfbFileSystem')
    }

    It 'keeps Remove-PfbFileSystem -DeleteLinkOnEradication on its shared query key and refuses to name an operation' {
        # The live hazard the abstention exists for: the same wire key is written into
        # $destroyQuery (which reaches a PATCH) and into $queryParams (which reaches a
        # DELETE). Reporting either operation would be a source-order accident.
        $record = $script:realInventory |
            Where-Object { $_.Cmdlet -eq 'Remove-PfbFileSystem' -and $_.Parameter -eq 'DeleteLinkOnEradication' }

        $record | Should -Not -BeNullOrEmpty
        $record.WireName | Should -Be 'delete_link_on_eradication'
        $record.WireSurface | Should -Be 'Query'
        $record.Method | Should -BeNullOrEmpty
        $record.Endpoint | Should -BeNullOrEmpty
    }
}
