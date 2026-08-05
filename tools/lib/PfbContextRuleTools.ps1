#Requires -Version 5.1

<#
    PfbContextRuleTools -- the spec-vs-module-assumption check for the Fusion
    `context_names` cardinality rule.

    Every other drift category asks "does the module cover what the API offers?". This one
    asks a different question: "is an assumption baked into the module still true?"

    THE LOAD-BEARING DESIGN POINT: the rule is read from ONE declared place --
    Private/Test-PfbContextMultiValueCapable.ps1, dot-sourced below and actually EXECUTED.
    It is never re-derived here. A check that re-implements the rule it is checking
    verifies nothing; it would agree with itself forever while the module drifted.

    WHY THIS IS A CROSS-SIGNAL CHECK RATHER THAN RULE-VS-COMPONENT. The first version of
    this file compared the module's rule against one spec signal, the component name. That
    shape is structurally blind to the failure that actually exists: four fleet-scoped GETs
    reference the multi-value component AND are size-1 on the wire, so rule and component
    AGREE and both are wrong in the same direction. Two-signal comparison cannot see that.
    This file therefore compares every available signal and reports any endpoint whose
    signals do not all agree -- including the case where the rule and the component agree
    but the remaining signals dissent.

    The signals, and what each is worth (measured against fb2.27; see section 8 of
    docs/design/fusion-context-injection.md):

      component `Context_names_get`  139 endpoints  wrong for 5
      declares `allow_errors`        135 endpoints  correct on every case with evidence
      declares an HTTP 207 response  124 endpoints  correct but stricter; excludes 11
                                                    endpoints of unknown status
      carries an `errors` envelope   139 endpoints  UNRELIABLE -- applied by an
                                                    allOf-composed `_errorContextResponse`
                                                    authoring convention to 15 endpoints
                                                    that declare no 207, including all four
                                                    defective ones. Deliberately NOT
                                                    implemented here, and must never be
                                                    used as a signal.

    HTTP 207 is available from the specs under tools/ but NOT from the capability map,
    which records the request surface only. It is therefore a corroborating signal for this
    maintainer check and never a runtime gate -- which is why it is optional throughout: an
    unknown 207 is carried as $null and excluded from comparison, never silently scored as
    "does not declare".

    This file REPORTS and deliberately does not adjudicate. A disagreement is not
    automatically a spec defect -- the case worth catching is a genuine future
    multi-context endpoint, where the module would be the wrong side. A human decides which
    signal is wrong, each time.
#>

$script:PfbContextMultiValueComponent = 'Context_names_get'

# Execute the module's own rule and its own resolution contract rather than copying them.
# Failing loudly here is correct: silently falling back to a local copy is the one outcome
# that would make this whole check meaningless.
$script:PfbContextRuleRepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:PfbContextRuleRequiredPath = @(
    'Private/PfbContextConstants.ps1'
    'Private/Test-PfbContextMultiValueCapable.ps1'
    'Private/Resolve-PfbParameterComponent.ps1'
)
foreach ($relativePath in $script:PfbContextRuleRequiredPath) {
    $absolutePath = Join-Path $script:PfbContextRuleRepoRoot $relativePath
    if (-not (Test-Path $absolutePath)) {
        throw ("PfbContextRuleTools: cannot locate the module's declared context rule/" +
            "resolution contract at '$absolutePath'. This check must execute the module's " +
            'own code, never re-implement it -- refusing to load rather than silently ' +
            'verifying a private copy against itself.')
    }
    . $absolutePath
}

function Get-PfbContextHttp207Endpoint {
    <#
    .SYNOPSIS
        Endpoint keys ("<METHOD> /<path>") in one spec document that declare an HTTP 207
        (Multi-Status) response.
    .DESCRIPTION
        The 207 signal is the reason this lives here rather than in the capability map: the
        map holds no response data at all. Feed the result to Get-PfbContextParameterFact's
        -Http207Endpoint so map-sourced facts can still carry the signal.

        Only the PRESENCE of the '207' key on the operation's `responses` object matters, so
        no $ref resolution is needed or attempted -- a 207 whose value is a $ref to a
        response component is still a declared 207. Path normalization goes through the
        shared ConvertTo-PfbNormalizedPath so keys match Get-PfbSpecCapabilities exactly.
    .OUTPUTS
        [string[]] sorted endpoint keys. Empty array when the spec declares none.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        $Spec
    )

    if (-not $Spec.paths) { return @() }

    $found = [System.Collections.Generic.List[string]]::new()
    foreach ($rawPath in $Spec.paths.PSObject.Properties.Name) {
        $pathItem = $Spec.paths.$rawPath
        $normalizedPath = ConvertTo-PfbNormalizedPath -Path $rawPath
        foreach ($methodName in $pathItem.PSObject.Properties.Name) {
            if ($script:PfbHttpMethods -notcontains $methodName) { continue }
            $op = $pathItem.$methodName
            if (-not $op.responses) { continue }
            if ($op.responses.PSObject.Properties.Name -contains '207') {
                $found.Add("$($methodName.ToUpper()) $normalizedPath")
            }
        }
    }

    return @($found | Sort-Object -Unique)
}

function Get-PfbContextParameterFact {
    <#
    .SYNOPSIS
        Normalizes every endpoint carrying a `context_names` parameter into one comparable
        signal record, from either the committed capability map or a single spec version's
        Get-PfbSpecCapabilities output.
    .DESCRIPTION
        Two sources, deliberately both supported, because they answer different questions
        and can legitimately disagree:

          -CapabilityMap      Data/PfbCapabilityMap.json (parsed). Its component data is
                              LAST-SEEN-WINS across the versions it was generated from --
                              it describes the NEWEST version's wire shape, not a union.
                              See Build-PfbCapabilityMap.ps1's
                              parameterComponentDefaults/parameterComponentOverrides
                              resolution contract.
          -SpecCapabilities   Get-PfbSpecCapabilities output for ONE fb<version>.json.
                              Use this to ask the question of a specific REST version.

        Dual input matters more since rev 3: the four defective endpoints' signals will all
        change when the upstream fix lands, and being able to ask a specific version is how
        that gets confirmed rather than assumed. These two inputs also drift when specs are
        refreshed without rebuilding the map, so every figure derived from them should be
        stated together with which input and which version it came from.

        Component resolution for -CapabilityMap follows the documented three-step contract:
        (1) the endpoint's parameterComponentOverrides value for the parameter if the KEY is
        present -- which may be JSON null, meaning "this endpoint's parameter has no
        component"; otherwise (2) the top-level parameterComponentDefaults value; otherwise
        (3) no known component. Key-present-but-null and key-absent are distinguished, never
        conflated.
    .PARAMETER Http207Endpoint
        Optional endpoint keys declaring an HTTP 207, from Get-PfbContextHttp207Endpoint.
        When omitted, DeclaresHttp207 is $null on every record -- meaning UNKNOWN, not
        "does not declare". Downstream comparison excludes unknown signals rather than
        scoring them, so omitting this narrows what the check can see without ever making
        it report something false.
    .OUTPUTS
        [PSCustomObject][] sorted by Endpoint, one per endpoint declaring `context_names`:
            Endpoint                "<METHOD> /<path>"
            Method                  HTTP method, upper-case
            Path                    normalized path
            ContextComponent        resolved component name, or $null when the endpoint
                                    declares the parameter inline with no "$ref"
            ComponentSaysMultiValue [bool], or $null when ContextComponent is $null
            DeclaresAllowErrors     [bool]
            DeclaresHttp207         [bool], or $null when not supplied (UNKNOWN)
            RuleSaysMultiValue      [bool] -- the MODULE's verdict, from
                                    Test-PfbContextMultiValueCapable
    #>
    [CmdletBinding(DefaultParameterSetName = 'CapabilityMap')]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'CapabilityMap')]
        $CapabilityMap,

        [Parameter(Mandatory, ParameterSetName = 'SpecCapabilities')]
        [AllowEmptyCollection()]
        [object[]]$SpecCapabilities,

        [AllowNull()]
        [string[]]$Http207Endpoint
    )

    # $null (parameter omitted) must stay distinguishable from an empty set (a spec that
    # genuinely declares no 207 anywhere) -- the first means "unknown", the second "none".
    #
    # Assigned by a plain if-statement, NOT `$set207 = if (...) { $hashSet }`: a HashSet
    # emitted as the value of a scriptblock gets ENUMERATED, which turns an empty set into
    # $null (silently reclassifying "none" as "unknown") and a populated one into a plain
    # array that has lost the OrdinalIgnoreCase comparer.
    $has207Data = $PSBoundParameters.ContainsKey('Http207Endpoint') -and $null -ne $Http207Endpoint
    $set207 = $null
    if ($has207Data) {
        $set207 = [System.Collections.Generic.HashSet[string]]::new([string[]]@($Http207Endpoint), [System.StringComparer]::OrdinalIgnoreCase)
    }

    $facts = [System.Collections.Generic.List[object]]::new()

    if ($PSCmdlet.ParameterSetName -eq 'CapabilityMap') {
        if (-not $CapabilityMap -or -not $CapabilityMap.endpoints) { return @() }
        $defaults = $CapabilityMap.parameterComponentDefaults

        foreach ($endpointKey in $CapabilityMap.endpoints.PSObject.Properties.Name) {
            $entry = $CapabilityMap.endpoints.$endpointKey
            if (-not $entry.parameters) { continue }
            $paramNames = $entry.parameters.PSObject.Properties.Name
            if ($paramNames -notcontains $script:PfbContextParameterName) { continue }

            $component = Resolve-PfbParameterComponent -EndpointEntry $entry `
                -ParameterName $script:PfbContextParameterName `
                -ParameterComponentDefaults $defaults

            # Endpoint keys are "<METHOD> /<path>"; split once on the first space only, so
            # a path can never be truncated.
            $splitIndex = $endpointKey.IndexOf(' ')
            if ($splitIndex -lt 1) { continue }
            $method = $endpointKey.Substring(0, $splitIndex)
            $path = $endpointKey.Substring($splitIndex + 1)

            $facts.Add((New-PfbContextParameterFactRecord -Method $method -Path $path `
                        -Component $component `
                        -DeclaresAllowErrors ($paramNames -contains $script:PfbAllowErrorsParameterName) `
                        -Set207 $set207))
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
                        -DeclaresAllowErrors ($parameters -contains $script:PfbAllowErrorsParameterName) `
                        -Set207 $set207))
        }
    }

    # Hashtable/PSObject property order is not guaranteed and this feeds a tracked report.
    return @($facts | Sort-Object -Property Endpoint)
}

function New-PfbContextParameterFactRecord {
    <#
    .SYNOPSIS
        Internal helper for Get-PfbContextParameterFact: builds one signal record and, in
        doing so, is the single point at which the MODULE's rule is executed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Method,
        [Parameter(Mandatory)] [string]$Path,
        [AllowNull()] [string]$Component,
        [Parameter(Mandatory)] [bool]$DeclaresAllowErrors,
        [AllowNull()] $Set207
    )

    $upperMethod = $Method.ToUpperInvariant()
    $endpoint = "$upperMethod $Path"

    # An empty-string component is treated as absent: the generator documents that a
    # parameter with no "$ref" contributes NO key rather than an empty value, so an empty
    # string here means malformed input, not "a component named ''".
    $hasComponent = -not [string]::IsNullOrWhiteSpace($Component)

    return [PSCustomObject]@{
        Endpoint                = $endpoint
        Method                  = $upperMethod
        Path                    = $Path
        ContextComponent        = if ($hasComponent) { $Component } else { $null }
        ComponentSaysMultiValue = if ($hasComponent) { $Component -eq $script:PfbContextMultiValueComponent } else { $null }
        DeclaresAllowErrors     = $DeclaresAllowErrors
        DeclaresHttp207         = if ($null -ne $Set207) { $Set207.Contains($endpoint) } else { $null }
        RuleSaysMultiValue      = [bool](Test-PfbContextMultiValueCapable -Method $upperMethod `
                -ContextComponent $Component -DeclaresAllowErrors $DeclaresAllowErrors)
    }
}

function Get-PfbContextSignalDisagreement {
    <#
    .SYNOPSIS
        The check: every endpoint whose cardinality signals do not all agree.
    .DESCRIPTION
        Replaces the earlier rule-vs-component comparison, which was structurally unable to
        see the defect that actually exists (rule and component agreeing while the wire
        disagrees with both).

        Compared signals, per endpoint: the component identity, whether `allow_errors` is
        declared, and -- when known -- whether an HTTP 207 is declared. Unanimity means no
        finding. An UNKNOWN 207 is excluded from the comparison rather than scored as
        "does not declare", so supplying less data can narrow what the check sees but can
        never make it report something false.

        The module's own verdict (RuleSaysMultiValue) is carried on every finding for
        transparency, but is not itself a compared signal: it is derived from two of them,
        so including it would double-weight the component and `allow_errors` rather than
        adding independent evidence.

        Endpoints whose `context_names` has no resolvable component are not comparable and
        are excluded here rather than silently scored as size-1; retrieve them from
        Get-PfbContextUnresolvedComponent so they stay visible.

        Findings are classified by Shape so the report can group them. The shapes are
        exhaustive over the non-unanimous combinations:

          component-says-multi-value-but-no-allow-errors
              The four fleet-scoped GETs today, and DELETE /management-access-policies in
              2.26/2.27. Strong evidence of a spec defect: the component claims fan-out
              while the endpoint offers no partial-failure story.
          size-1-component-but-declares-allow-errors
              The named mirror case, PATCH /directory-services/test.
          rule-says-capable-but-declares-no-207
              Rule and component and `allow_errors` all agree the endpoint fans out, but it
              declares no 207. 11 endpoints at fb2.27 -- status genuinely unknown, which is
              precisely why 207 is not used as a runtime gate.
          size-1-but-declares-207
              Declares a partial-failure response while nothing else says it fans out.
    .PARAMETER Fact
        Get-PfbContextParameterFact output.
    .OUTPUTS
        [PSCustomObject][] sorted by Endpoint:
            Endpoint, Method, ContextComponent, Shape, RuleSaysMultiValue,
            ComponentSaysMultiValue, DeclaresAllowErrors, DeclaresHttp207,
            MultiValueSignals, SizeOneSignals, Summary
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Fact
    )

    $findings = foreach ($f in $Fact) {
        if ($null -eq $f.ComponentSaysMultiValue) { continue }

        $signals = [ordered]@{
            component    = [bool]$f.ComponentSaysMultiValue
            allow_errors = [bool]$f.DeclaresAllowErrors
        }
        if ($null -ne $f.DeclaresHttp207) { $signals['http207'] = [bool]$f.DeclaresHttp207 }

        $multiSignals = @($signals.Keys | Where-Object { $signals[$_] } | Sort-Object)
        $sizeOneSignals = @($signals.Keys | Where-Object { -not $signals[$_] } | Sort-Object)
        if ($multiSignals.Count -eq 0 -or $sizeOneSignals.Count -eq 0) { continue }  # unanimous

        $component = $signals['component']
        $allowErrors = $signals['allow_errors']
        $shape = if ($component -and -not $allowErrors) { 'component-says-multi-value-but-no-allow-errors' }
        elseif (-not $component -and $allowErrors) { 'size-1-component-but-declares-allow-errors' }
        elseif ($component -and $allowErrors) { 'rule-says-capable-but-declares-no-207' }
        else { 'size-1-but-declares-207' }

        [PSCustomObject]@{
            Endpoint                = $f.Endpoint
            Method                  = $f.Method
            ContextComponent        = $f.ContextComponent
            Shape                   = $shape
            RuleSaysMultiValue      = $f.RuleSaysMultiValue
            ComponentSaysMultiValue = $f.ComponentSaysMultiValue
            DeclaresAllowErrors     = $f.DeclaresAllowErrors
            DeclaresHttp207         = $f.DeclaresHttp207
            MultiValueSignals       = $multiSignals
            SizeOneSignals          = $sizeOneSignals
            Summary                 = ("signals split -- multi-value: $($multiSignals -join ', '); " +
                "size-1: $($sizeOneSignals -join ', '); module rule says " +
                $(if ($f.RuleSaysMultiValue) { 'multi-value' } else { 'size-1' }))
        }
    }

    return @($findings | Sort-Object -Property Endpoint)
}

function Get-PfbContextSizeOneWithAllowErrors {
    <#
    .SYNOPSIS
        The named mirror case: endpoints whose component says size-1 yet which declare
        `allow_errors`.
    .DESCRIPTION
        A NAMED SUBSET of Get-PfbContextSignalDisagreement's findings (Shape
        'size-1-component-but-declares-allow-errors'), never an additional category --
        reporting it separately as well would double-count one defect as two findings.
        Surfaced under its own name only because it is a known, characterized case worth
        pointing at directly: `PATCH /directory-services/test`, the one size-1 endpoint
        declaring `allow_errors`, which rev 3's Appendix A records as NOT live-verified
        (it is a mutating verb and was not probed).

        Its counterpart -- agreed multi-value endpoints lacking `allow_errors` -- is
        deliberately NOT surfaced here any more. Under rev 3's rule that is a cardinality
        finding, not a co-occurrence curiosity, and it belongs in the disagreement list.
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

    return @($Fact |
            Where-Object { $false -eq $_.ComponentSaysMultiValue -and $_.DeclaresAllowErrors } |
            ForEach-Object {
                [PSCustomObject]@{
                    Endpoint         = $_.Endpoint
                    Method           = $_.Method
                    ContextComponent = $_.ContextComponent
                    DeclaresHttp207  = $_.DeclaresHttp207
                }
            } | Sort-Object -Property Endpoint)
}

function Get-PfbContextUnresolvedComponent {
    <#
    .SYNOPSIS
        Endpoints declaring `context_names` with no resolvable component -- neither
        checkable nor safe to score as size-1.
    .DESCRIPTION
        Expected to be empty: verified 0 occurrences across every spec where the parameter
        exists at all, which is fb2.17-fb2.28 (`context_names` does not exist before 2.17,
        so the wider fb2.0-2.28 range this comment previously claimed was not wrong so much
        as vacuous over its first seventeen versions).

        Surfaced anyway because the failure mode it guards against is silent: were a future
        spec to declare `context_names` inline with no "$ref", treating it as size-1 by
        default would hide a genuine multi-value endpoint behind a hardcoded throw.
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

    return @($Fact | Where-Object { $null -eq $_.ComponentSaysMultiValue } |
            ForEach-Object {
                [PSCustomObject]@{
                    Endpoint            = $_.Endpoint
                    Method              = $_.Method
                    DeclaresAllowErrors = $_.DeclaresAllowErrors
                }
            } | Sort-Object -Property Endpoint)
}
