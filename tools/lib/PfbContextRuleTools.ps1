#Requires -Version 5.1

<#
    PfbContextRuleTools -- the spec-vs-module-assumption check for the Fusion
    `context_names` verb rule.

    Every other drift category asks "does the module cover what the API offers?". This one
    asks a different question: "is an assumption we baked into the code still true?" The
    module hardcodes a cardinality rule (GET fans out; POST/PATCH/PUT/DELETE are size-1)
    that the OpenAPI spec expresses only through which component a parameter `$ref`s --
    `Context_names_get` (multi-value) versus `Context_names` (size-1). Those two components
    have identical schemas and there is no `maxItems`, so the component NAME is the only
    mechanical signal that the assumption could ever be checked against.

    THE LOAD-BEARING DESIGN POINT: the rule is read from ONE declared place --
    Private/Test-PfbContextMultiValueCapable.ps1, dot-sourced below and actually EXECUTED.
    It is never re-derived here. A check that re-implements the rule it is checking
    verifies nothing; it would agree with itself forever while the module drifted.

    The rule is ground truth (live-tested plus upstream confirmation) and the spec is the
    side that has been observed wrong. This file therefore REPORTS disagreement and
    deliberately does not prejudge which side is at fault -- a future disagreement may well
    be a real API change (a genuine multi-context mutation endpoint) rather than another
    spec defect. A human decides, each time.
#>

$script:PfbContextParameterName = 'context_names'
$script:PfbContextMultiValueComponent = 'Context_names_get'
$script:PfbAllowErrorsParameterName = 'allow_errors'

# Execute the module's own rule rather than copying it. Failing loudly here is correct:
# silently falling back to a local copy of the rule is the one outcome that would make
# this whole check meaningless.
$script:PfbContextRuleRepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:PfbContextRulePredicatePath = Join-Path $script:PfbContextRuleRepoRoot 'Private/Test-PfbContextMultiValueCapable.ps1'
if (-not (Test-Path $script:PfbContextRulePredicatePath)) {
    throw ("PfbContextRuleTools: cannot locate the module's declared context-cardinality " +
        "rule at '$script:PfbContextRulePredicatePath'. This check must execute the " +
        'module rule, never re-implement it -- refusing to load rather than silently ' +
        'verifying a private copy of the rule against itself.')
}
. $script:PfbContextRulePredicatePath

function Get-PfbContextParameterFact {
    <#
    .SYNOPSIS
        Normalizes every endpoint carrying a `context_names` parameter into one comparable
        record, from either the committed capability map or a single spec version's
        Get-PfbSpecCapabilities output.
    .DESCRIPTION
        Two sources, deliberately both supported, because they answer different questions
        and can legitimately disagree:

          -CapabilityMap      Data/PfbCapabilityMap.json (parsed). Its component data is
                              LAST-SEEN-WINS across the versions it was generated from --
                              i.e. it describes the NEWEST version's wire shape, not a
                              union. See Build-PfbCapabilityMap.ps1's
                              parameterComponentDefaults/parameterComponentOverrides
                              resolution contract.
          -SpecCapabilities   Get-PfbSpecCapabilities output for ONE fb<version>.json.
                              Use this to ask the question of a specific REST version.

        These two inputs drift when specs are refreshed without rebuilding the map, so
        every figure derived from them should be stated together with which input and
        which version it came from.

        Component resolution for -CapabilityMap follows the documented three-step
        contract: (1) the endpoint's parameterComponentOverrides value for the parameter
        if the KEY is present -- which may be JSON null, meaning "this endpoint's
        parameter has no component"; otherwise (2) the top-level
        parameterComponentDefaults value; otherwise (3) no known component. Key-present-
        but-null and key-absent are distinguished, never conflated.
    .OUTPUTS
        [PSCustomObject][] sorted by Endpoint, one per endpoint declaring `context_names`:
            Endpoint            "<METHOD> /<path>"
            Method              HTTP method, upper-case
            Path                normalized path
            ContextComponent    resolved component name, or $null when the endpoint
                                declares the parameter inline with no "$ref"
            SpecSaysMultiValue  [bool] or $null when ContextComponent is $null
            RuleSaysMultiValue  [bool] -- the MODULE's verdict, from
                                Test-PfbContextMultiValueCapable
            DeclaresAllowErrors [bool]
    #>
    [CmdletBinding(DefaultParameterSetName = 'CapabilityMap')]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'CapabilityMap')]
        $CapabilityMap,

        [Parameter(Mandatory, ParameterSetName = 'SpecCapabilities')]
        [AllowEmptyCollection()]
        [object[]]$SpecCapabilities
    )

    $facts = [System.Collections.Generic.List[object]]::new()

    if ($PSCmdlet.ParameterSetName -eq 'CapabilityMap') {
        if (-not $CapabilityMap -or -not $CapabilityMap.endpoints) { return @() }
        $defaults = $CapabilityMap.parameterComponentDefaults

        foreach ($endpointKey in $CapabilityMap.endpoints.PSObject.Properties.Name) {
            $entry = $CapabilityMap.endpoints.$endpointKey
            if (-not $entry.parameters) { continue }
            $paramNames = $entry.parameters.PSObject.Properties.Name
            if ($paramNames -notcontains $script:PfbContextParameterName) { continue }

            $component = $null
            $overrides = $entry.parameterComponentOverrides
            if ($overrides -and ($overrides.PSObject.Properties.Name -contains $script:PfbContextParameterName)) {
                # Key present -- authoritative, even when its value is null.
                $component = $overrides.$($script:PfbContextParameterName)
            }
            elseif ($defaults -and ($defaults.PSObject.Properties.Name -contains $script:PfbContextParameterName)) {
                $component = $defaults.$($script:PfbContextParameterName)
            }

            # Endpoint keys are "<METHOD> /<path>"; split once on the first space only, so
            # a path can never be truncated.
            $splitIndex = $endpointKey.IndexOf(' ')
            if ($splitIndex -lt 1) { continue }
            $method = $endpointKey.Substring(0, $splitIndex)
            $path = $endpointKey.Substring($splitIndex + 1)

            $facts.Add((New-PfbContextParameterFactRecord -Method $method -Path $path `
                        -Component $component `
                        -DeclaresAllowErrors ($paramNames -contains $script:PfbAllowErrorsParameterName)))
        }
    }
    else {
        foreach ($capability in $SpecCapabilities) {
            if (-not $capability) { continue }
            $components = $capability.ParameterComponents
            $parameters = @($capability.Parameters)
            if ($parameters -notcontains $script:PfbContextParameterName) { continue }

            $component = $null
            if ($components -and $components.ContainsKey($script:PfbContextParameterName)) {
                $component = $components[$script:PfbContextParameterName]
            }

            $facts.Add((New-PfbContextParameterFactRecord -Method $capability.Method -Path $capability.Path `
                        -Component $component `
                        -DeclaresAllowErrors ($parameters -contains $script:PfbAllowErrorsParameterName)))
        }
    }

    # Hashtable/PSObject property order is not guaranteed and this feeds a tracked report.
    return @($facts | Sort-Object -Property Endpoint)
}

function New-PfbContextParameterFactRecord {
    <#
    .SYNOPSIS
        Internal helper for Get-PfbContextParameterFact: builds one fact record and, in
        doing so, is the single point at which the MODULE's rule is executed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Method,
        [Parameter(Mandatory)] [string]$Path,
        [AllowNull()] [string]$Component,
        [Parameter(Mandatory)] [bool]$DeclaresAllowErrors
    )

    $upperMethod = $Method.ToUpperInvariant()

    # An empty-string component is treated as absent: the generator documents that a
    # parameter with no "$ref" contributes NO key rather than an empty value, so an empty
    # string here means malformed input, not "a component named ''".
    $hasComponent = -not [string]::IsNullOrWhiteSpace($Component)

    return [PSCustomObject]@{
        Endpoint            = "$upperMethod $Path"
        Method              = $upperMethod
        Path                = $Path
        ContextComponent    = if ($hasComponent) { $Component } else { $null }
        SpecSaysMultiValue  = if ($hasComponent) { $Component -eq $script:PfbContextMultiValueComponent } else { $null }
        RuleSaysMultiValue  = [bool](Test-PfbContextMultiValueCapable -Method $upperMethod)
        DeclaresAllowErrors = $DeclaresAllowErrors
    }
}

function Get-PfbContextVerbRuleDisagreement {
    <#
    .SYNOPSIS
        The check: every endpoint where the MODULE's cardinality rule and the SPEC's
        component identity disagree.
    .DESCRIPTION
        Deliberately reports rather than adjudicates. A disagreement is NOT automatically a
        spec bug -- the case this check exists to catch is a genuine future multi-context
        mutation endpoint, where the module would be the wrong side. The wording of the
        emitted records is neutral for that reason.

        Endpoints whose `context_names` has no resolvable component are NOT comparable and
        are excluded here rather than being silently scored as size-1; retrieve them from
        Get-PfbContextUnresolvedComponent so they stay visible.
    .PARAMETER Fact
        Get-PfbContextParameterFact output.
    .OUTPUTS
        [PSCustomObject][] sorted by Endpoint:
            Endpoint, Method, ContextComponent, RuleSaysMultiValue, SpecSaysMultiValue,
            DeclaresAllowErrors, Summary
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Fact
    )

    $disagreements = foreach ($f in $Fact) {
        if ($null -eq $f.SpecSaysMultiValue) { continue }
        if ($f.SpecSaysMultiValue -eq $f.RuleSaysMultiValue) { continue }

        $ruleWord = if ($f.RuleSaysMultiValue) { 'multi-value' } else { 'size-1' }
        $specWord = if ($f.SpecSaysMultiValue) { 'multi-value' } else { 'size-1' }

        [PSCustomObject]@{
            Endpoint            = $f.Endpoint
            Method              = $f.Method
            ContextComponent    = $f.ContextComponent
            RuleSaysMultiValue  = $f.RuleSaysMultiValue
            SpecSaysMultiValue  = $f.SpecSaysMultiValue
            DeclaresAllowErrors = $f.DeclaresAllowErrors
            Summary             = ("module rule says $ruleWord for $($f.Method); spec " +
                "references '$($f.ContextComponent)' ($specWord)")
        }
    }

    return @($disagreements | Sort-Object -Property Endpoint)
}

function Get-PfbContextAllowErrorsAnomaly {
    <#
    .SYNOPSIS
        A SEPARATE anomaly from the cardinality disagreement: endpoints whose
        `allow_errors` declaration does not line up with their context cardinality.
    .DESCRIPTION
        Kept apart from Get-PfbContextVerbRuleDisagreement on purpose -- they are different
        anomalies and conflating them muddies both. `allow_errors` is corroborating
        evidence about cardinality, not a cardinality signal in its own right.

        MultiValueWithoutAllowErrors is scoped to endpoints where the rule and the spec
        AGREE the endpoint is multi-value. That scoping is the whole point of the
        separation: an endpoint that is already reported as a cardinality disagreement must
        not also appear here, or the same defect would be double-counted as two anomalies.
        (Against fb2.27 this is exactly what keeps DELETE /management-access-policies in
        the disagreement list only, leaving the four genuine GET anomalies here.)

        SingleValueWithAllowErrors is the mirror image -- agreed size-1 endpoints that
        nonetheless declare `allow_errors`. Named rather than left to be discovered later.
    .PARAMETER Fact
        Get-PfbContextParameterFact output.
    .OUTPUTS
        [PSCustomObject] with two sorted [PSCustomObject[]] properties:
        MultiValueWithoutAllowErrors, SingleValueWithAllowErrors.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Fact
    )

    $agreed = @($Fact | Where-Object { $null -ne $_.SpecSaysMultiValue -and $_.SpecSaysMultiValue -eq $_.RuleSaysMultiValue })

    $project = {
        param($record)
        [PSCustomObject]@{
            Endpoint            = $record.Endpoint
            Method              = $record.Method
            ContextComponent    = $record.ContextComponent
            DeclaresAllowErrors = $record.DeclaresAllowErrors
        }
    }

    $multiWithout = @($agreed | Where-Object { $_.SpecSaysMultiValue -and -not $_.DeclaresAllowErrors } |
            ForEach-Object { & $project $_ } | Sort-Object -Property Endpoint)
    $singleWith = @($agreed | Where-Object { -not $_.SpecSaysMultiValue -and $_.DeclaresAllowErrors } |
            ForEach-Object { & $project $_ } | Sort-Object -Property Endpoint)

    return [PSCustomObject]@{
        MultiValueWithoutAllowErrors = $multiWithout
        SingleValueWithAllowErrors   = $singleWith
    }
}

function Get-PfbContextUnresolvedComponent {
    <#
    .SYNOPSIS
        Endpoints declaring `context_names` with no resolvable component -- neither
        checkable nor safe to score as size-1.
    .DESCRIPTION
        Expected to be empty (0 occurrences across fb2.0-fb2.28). Surfaced anyway because
        the failure mode it guards against is silent: were a future spec to declare
        `context_names` inline with no "$ref", treating it as size-1 by default would hide
        a genuine multi-value endpoint behind a hardcoded throw.
    .PARAMETER Fact
        Get-PfbContextParameterFact output.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Fact
    )

    return @($Fact | Where-Object { $null -eq $_.SpecSaysMultiValue } |
            ForEach-Object {
                [PSCustomObject]@{
                    Endpoint            = $_.Endpoint
                    Method              = $_.Method
                    DeclaresAllowErrors = $_.DeclaresAllowErrors
                }
            } | Sort-Object -Property Endpoint)
}
