#Requires -Version 5.1
<#
.SYNOPSIS
    Analysis layer for the issue #90 pipeline-selector audit: reflection inventory,
    producer resolution, candidate predicate, probe construction, outcome classification.
.DESCRIPTION
    Pure functions only. Nothing here imports the shipped module's HTTP path or invokes a
    cmdlet -- that is tools/lib/PfbSelectorProbeHarness.ps1's job, deliberately kept in its
    own file so the function-table mutation it performs stays small and auditable.
#>

function Get-PfbPipelineBoundParameter {
    <#
    .SYNOPSIS
        Every parameter across -Module that declares any pipeline binding.
    .DESCRIPTION
        Reflection, not AST, because reflection is what the engine itself binds on -- and
        because this module declares parameters in the bare attribute form
        [Parameter(ParameterSetName = 'ByName', ValueFromPipeline,
        ValueFromPipelineByPropertyName)], for which a regex expecting `= $true` matches
        zero of the 544 exported functions.
    .OUTPUTS
        [PSCustomObject]@{ Cmdlet; Verb; Parameter; ParameterType; Aliases;
        ValueFromPipeline; ValueFromPipelineByPropertyName; ParameterSets }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.PSModuleInfo]$Module
    )

    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($command in (Get-Command -Module $Module.Name -CommandType Function)) {
        foreach ($parameter in $command.Parameters.Values) {
            $parameterAttributes = @($parameter.Attributes |
                    Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] })

            $fromPipeline = [bool]@($parameterAttributes | Where-Object { $_.ValueFromPipeline }).Count
            $fromProperty = [bool]@($parameterAttributes | Where-Object { $_.ValueFromPipelineByPropertyName }).Count
            if (-not ($fromPipeline -or $fromProperty)) { continue }

            $results.Add([PSCustomObject]@{
                    Cmdlet                          = $command.Name
                    Verb                            = ($command.Name -split '-')[0]
                    Parameter                       = $parameter.Name
                    ParameterType                   = $parameter.ParameterType.Name
                    Aliases                         = @($parameter.Aliases)
                    ValueFromPipeline               = $fromPipeline
                    ValueFromPipelineByPropertyName = $fromProperty
                    ParameterSets                   = @($parameterAttributes |
                            ForEach-Object { $_.ParameterSetName } | Sort-Object -Unique)
                })
        }
    }

    # Sorted at emit, invariant culture -- the same determinism rule the rest of tools/lib
    # follows (issue #85), so a Linux runner and a Windows workstation agree byte for byte.
    return @($results | Sort-Object -Property Cmdlet, Parameter -Culture '')
}

function Get-PfbSelectorProducerIndex {
    <#
    .SYNOPSIS
        Indexes every GET endpoint in the response-shape map by its first path segment.
    .OUTPUTS
        [hashtable] family -> string[] of 'GET /path' keys, each list sorted.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $ResponseShapeMap
    )

    $index = @{}
    foreach ($key in $ResponseShapeMap.endpoints.PSObject.Properties.Name) {
        if ($key -notlike 'GET *') { continue }
        $path = ($key -split ' ', 2)[1].TrimStart('/')
        $family = ($path -split '/')[0]
        if (-not $index.ContainsKey($family)) {
            $index[$family] = [System.Collections.Generic.List[string]]::new()
        }
        $index[$family].Add($key)
    }

    $sorted = @{}
    foreach ($family in $index.Keys) { $sorted[$family] = @($index[$family] | Sort-Object -Culture '') }
    return $sorted
}

function Get-PfbCmdletEndpointLiteral {
    <#
    .SYNOPSIS
        Maps each function under -PublicDirectory to the -Endpoint literals it passes to
        Invoke-PfbApiRequest.
    .DESCRIPTION
        Every cmdlet in this repo passes -Endpoint as a literal single-quoted string; this
        deliberately recognises nothing else, matching Get-PfbEndpointForVariable's
        "never guess" discipline.
    .OUTPUTS
        [hashtable] cmdlet -> string[] of endpoint literals.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PublicDirectory
    )

    $map = @{}
    foreach ($file in (Get-ChildItem -Path $PublicDirectory -Filter '*.ps1' -Recurse -File)) {
        $text = Get-Content -Path $file.FullName -Raw
        $endpoints = @([regex]::Matches($text, "-Endpoint\s+'([^']+)'") |
                ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique -Culture '')
        foreach ($name in ([regex]::Matches($text, '(?m)^function\s+([\w-]+)') |
                ForEach-Object { $_.Groups[1].Value })) {
            $map[$name] = $endpoints
        }
    }
    return $map
}

function Get-PfbHelpExampleChain {
    <#
    .SYNOPSIS
        Every 'Producer-Pfb... | Consumer-Pfb...' chain written literally in comment-based
        help under -PublicDirectory.
    .DESCRIPTION
        A chain the module advertises in its own help is a chain the module owes, whether or
        not the two cmdlets share a resource family -- Get-PfbFileSystem |
        New-PfbFileSystemSnapshot is exactly such a case, and family resolution alone misses
        it. This is the audit's second, independent producer source.
    .OUTPUTS
        [PSCustomObject]@{ File; Producer; Consumer; Line }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PublicDirectory
    )

    $chains = [System.Collections.Generic.List[object]]::new()
    foreach ($file in (Get-ChildItem -Path $PublicDirectory -Filter '*.ps1' -Recurse -File)) {
        foreach ($line in (Get-Content -Path $file.FullName)) {
            $match = [regex]::Match($line, '\b(\w+-Pfb\w+)\b[^|]*\|\s*(\w+-Pfb\w+)\b')
            if (-not $match.Success) { continue }
            $chains.Add([PSCustomObject]@{
                    File     = $file.Name
                    Producer = $match.Groups[1].Value
                    Consumer = $match.Groups[2].Value
                    Line     = $line.Trim()
                })
        }
    }
    return @($chains | Sort-Object -Property File, Producer, Consumer -Culture '')
}

function Get-PfbSelectorProducerSet {
    <#
    .SYNOPSIS
        The GET endpoints whose items can plausibly be piped into -Cmdlet.
    .DESCRIPTION
        Family members share the consumer's first path segment. Primary is the GET on the
        consumer's own base path -- the endpoint a user would obviously pipe from. Both are
        reported: "fails every producer in family" and "fails its primary producer" are
        different signals (measured at 50 and 67 pairs) and neither is collapsed into the
        other.
    .OUTPUTS
        [PSCustomObject]@{ Producers; Primary; FromExample }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Cmdlet,
        [Parameter(Mandatory)][hashtable]$EndpointLiteral,
        [Parameter(Mandatory)][hashtable]$ProducerIndex,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$ExampleChain
    )

    $own = @($EndpointLiteral[$Cmdlet])
    $families = @($own | ForEach-Object { ($_.TrimStart('/') -split '/')[0] } | Sort-Object -Unique -Culture '')

    $producers = [System.Collections.Generic.List[string]]::new()
    foreach ($family in $families) {
        if ($ProducerIndex.ContainsKey($family)) { $producers.AddRange([string[]]$ProducerIndex[$family]) }
    }

    $primary = @($own | ForEach-Object { "GET /$($_.TrimStart('/'))" } | Where-Object { $_ -in $producers })

    # A help example names a producer CMDLET; translate it to that cmdlet's own GET endpoint.
    $fromExample = [System.Collections.Generic.List[string]]::new()
    foreach ($chain in @($ExampleChain | Where-Object { $_.Consumer -eq $Cmdlet })) {
        foreach ($endpoint in @($EndpointLiteral[$chain.Producer])) {
            $key = "GET /$($endpoint.TrimStart('/'))"
            if ($ProducerIndex.Values | ForEach-Object { $_ } | Where-Object { $_ -eq $key }) {
                $fromExample.Add($key)
                if ($key -notin $producers) { $producers.Add($key) }
            }
        }
    }

    return [PSCustomObject]@{
        Producers   = @($producers | Sort-Object -Unique -Culture '')
        Primary     = @($primary | Sort-Object -Unique -Culture '')
        FromExample = @($fromExample | Sort-Object -Unique -Culture '')
    }
}

function Get-PfbSelectorCandidate {
    <#
    .SYNOPSIS
        Applies the candidate predicate to every (cmdlet, parameter, producer) triple.
    .DESCRIPTION
        A triple is a candidate when the parameter is pipeline-bound, IS A SELECTOR (its wire
        key targets queryParams, not the request body), is scalar-shaped, and neither its name
        nor any alias matches a field the producer actually returns.

        The selector-hood gate is load-bearing. Measured across the module the type filter
        alone takes 303 pipeline-bound pairs to 302 -- it discriminates essentially nothing,
        because nearly every pipeline-bound parameter here is already string-shaped. Without
        the gate the predicate admits request-body properties and the candidate rate inflates
        into the vacuous range that made #89's 37-cmdlet list worthless.

        This function DECIDES NOTHING about defects. It selects what the harness puts on
        trial.
    .OUTPUTS
        [PSCustomObject]@{ Cmdlet; Verb; Parameter; Aliases; ValueFromPipeline; Producer;
        WireName; WireSurface; MatchedField; MatchedVersion; IsCandidate; Gate }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$PipelineParameter,
        [Parameter(Mandatory)][object[]]$Inventory,
        [Parameter(Mandatory)][hashtable]$ProducerSet,
        [Parameter(Mandatory)]$ResponseShapeMap
    )

    $inventoryIndex = @{}
    foreach ($record in $Inventory) { $inventoryIndex["$($record.Cmdlet)/$($record.Parameter)"] = $record }

    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($parameter in $PipelineParameter) {
        $set = $ProducerSet[$parameter.Cmdlet]
        if (-not $set -or -not $set.Producers) { continue }

        $inventoryRecord = $inventoryIndex["$($parameter.Cmdlet)/$($parameter.Parameter)"]
        $wireName = if ($inventoryRecord) { $inventoryRecord.WireName } else { $null }
        $wireSurface = if ($inventoryRecord) { $inventoryRecord.WireSurface } else { 'Unresolved' }

        $names = @($parameter.Parameter) + @($parameter.Aliases)

        foreach ($producer in $set.Producers) {
            $itemProperties = @($ResponseShapeMap.endpoints.$producer.responseItemProperties.PSObject.Properties)
            # -in on strings is case-insensitive, which is the comparison PowerShell itself
            # uses for property-name binding.
            $match = @($itemProperties | Where-Object { $_.Name -in $names }) | Select-Object -First 1

            $gate =
            if ($wireSurface -eq 'Body') { 'NotSelector' }
            elseif ($wireSurface -eq 'Unresolved') { 'SelectorUnresolved' }
            elseif ($parameter.ParameterType -notin 'String', 'String[]') { 'NotScalar' }
            elseif ($match) { 'Matched' }
            else { 'Candidate' }

            $results.Add([PSCustomObject]@{
                    Cmdlet            = $parameter.Cmdlet
                    Verb              = $parameter.Verb
                    Parameter         = $parameter.Parameter
                    Aliases           = $parameter.Aliases
                    ValueFromPipeline = $parameter.ValueFromPipeline
                    Producer          = $producer
                    WireName          = $wireName
                    WireSurface       = $wireSurface
                    MatchedField      = if ($match) { $match.Name } else { $null }
                    MatchedVersion    = if ($match) { $match.Value } else { $null }
                    IsCandidate       = ($gate -eq 'Candidate')
                    Gate              = $gate
                })
        }
    }

    return @($results | Sort-Object -Property Cmdlet, Parameter, Producer -Culture '')
}

function Get-PfbResponseItemType {
    <#
    .SYNOPSIS
        Declared type of each items[] element property for one endpoint in one spec.
    .DESCRIPTION
        Reuses the existing PfbSpecTools walkers rather than introducing a second one, per the
        toolchain's standing one-walker decision. MaxDepth is left at
        Get-PfbSchemaPropertyDetails' own default; this reads the ITEM element schema, not the
        deeply-nested allOf chains that forced the depth-32 rule in Get-PfbSpecResponseShapes.

        Returns an EMPTY hashtable rather than throwing when the endpoint or its items[] schema
        is absent. The caller degrades to all-string probes and MUST state that caveat in the
        report -- never a silent downgrade.

        Requires tools/lib/PfbSpecTools.ps1 to be dot-sourced by the caller.
    .OUTPUTS
        [hashtable] property name -> declared type string ('string', 'object', 'array', ...)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SpecPath,
        [Parameter(Mandatory)][string]$Endpoint
    )

    # ConvertFrom-Json only gained -Depth in PowerShell 6.2; under Windows PowerShell 5.1 it
    # fails with "A parameter cannot be found that matches parameter name 'Depth'". Measured:
    # 5.1 parses the 2.04 MB fb2.28.json correctly without it. Same guard as
    # Get-PfbDriftAnnotationFile in tools/lib/PfbApiDriftTools.ps1.
    $json = Get-Content -Path $SpecPath -Raw
    $spec = if ($PSVersionTable.PSVersion.Major -ge 6) { $json | ConvertFrom-Json -Depth 64 } else { $json | ConvertFrom-Json }

    $method, $path = ($Endpoint -split ' ', 2)
    $normalized = ConvertTo-PfbNormalizedPath -Path $path

    $pathNode = $spec.paths.PSObject.Properties |
        Where-Object { (ConvertTo-PfbNormalizedPath -Path $_.Name) -eq $normalized } |
        Select-Object -First 1
    if (-not $pathNode) { return @{} }

    $operation = $pathNode.Value.($method.ToLowerInvariant())
    $responseSchema = Get-PfbResponseSchema -Operation $operation -Spec $spec
    if (-not $responseSchema) { return @{} }

    # Get-PfbSchemaPropertyDetails returns { Name; ReadOnly; Deprecated; Type; Format; Required;
    # OwnerSchema } -- it does NOT surface the raw schema node, so it cannot reach items[]'s
    # element schema. Get-PfbSchemaPropertyWalkAccumulators does, via PropertyNodesByName.
    # Its help calls it internal; using it here is still correct, because the alternative is a
    # second allOf/$ref walker and the toolchain has a standing one-walker decision.
    $walk = Get-PfbSchemaPropertyWalkAccumulators -Schema (Resolve-PfbRef -Node $responseSchema -Spec $spec) -Spec $spec
    if (-not $walk.PropertyNodesByName.ContainsKey('items')) { return @{} }

    $itemsNode = @($walk.PropertyNodesByName['items'])[0]
    if (-not $itemsNode -or -not $itemsNode.items) { return @{} }

    $itemSchema = Resolve-PfbRef -Node $itemsNode.items -Spec $spec
    if (-not $itemSchema) { return @{} }

    # Read the raw property NODES, not Get-PfbSchemaPropertyDetails' records. That function
    # deliberately refuses to follow a property's own $ref (its PIN rule, which exists so a
    # referenced schema's readOnly flag cannot leak onto the referring property), so an
    # object-valued field declared as `remote: { $ref: '#/components/schemas/...' }` reports
    # no Type at all. Defaulting that to 'string' would build exactly the all-string probe
    # this function exists to avoid: a string `remote` binds cleanly by property name and
    # hides the stringification. Resolving one level FOR TYPE ONLY is safe -- no readOnly,
    # deprecated or required semantics are read here -- and reuses the same walker.
    $itemWalk = Get-PfbSchemaPropertyWalkAccumulators -Schema $itemSchema -Spec $spec

    $types = @{}
    foreach ($name in $itemWalk.PropertyNodesByName.Keys) {
        $node = @($itemWalk.PropertyNodesByName[$name])[0]
        $type = $null
        if ($node) {
            if ($node.type) { $type = $node.type }
            elseif ($node.'$ref') {
                $resolved = Resolve-PfbRef -Node $node -Spec $spec
                if ($resolved -and $resolved.type) { $type = $resolved.type }
                elseif ($resolved -and ($resolved.properties -or $resolved.allOf)) { $type = 'object' }
            }
            elseif ($node.properties -or $node.allOf) { $type = 'object' }
            elseif ($node.items) { $type = 'array' }
        }
        $types[$name] = if ($type) { $type } else { 'string' }
    }
    return $types
}

function New-PfbSelectorProbeObject {
    <#
    .SYNOPSIS
        Builds the object that gets piped into a cmdlet under probe.
    .DESCRIPTION
        Property NAMES are exactly the producer's responseItemProperties -- that is what a real
        piped item carries, because Invoke-PfbApiRequest unwraps the items envelope itself
        (Private/Invoke-PfbApiRequest.ps1:342) and emits the item objects.

        Each scalar property gets a distinct sentinel derived from its own name, so an emitted
        wire value identifies WHICH property bound. Object- and array-typed fields are
        materialised as objects and arrays: an all-string probe would bind cleanly to a field
        like `remote` that is really an object and hide the stringification.
    .OUTPUTS
        [PSCustomObject]
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$ItemProperty,
        [Parameter(Mandatory)][hashtable]$ItemType
    )

    $ordered = [ordered]@{}
    foreach ($name in ($ItemProperty | Sort-Object -Culture '')) {
        $type = if ($ItemType.ContainsKey($name)) { $ItemType[$name] } else { 'string' }
        $ordered[$name] = switch ($type) {
            'object' { [PSCustomObject]@{ id = "PROBE-$name-id"; name = "PROBE-$name-name" } }
            'array' { , @("PROBE-$name-0") }
            default { "PROBE-$name" }
        }
    }
    return [PSCustomObject]$ordered
}

function Get-PfbSelectorOutcome {
    <#
    .SYNOPSIS
        Classifies what a probe actually put on the wire.
    .DESCRIPTION
        Findings are Coerced and WrongScalar ONLY.

        Guarded is #64's fix working, not a defect. NoSelector is a reported observation, not a
        finding: if any selector is pipeline-bound then a non-matching object falls through to
        pass 3 and coerces, so NoSelector can only occur where nothing is pipeline-bound -- in
        which case the cmdlet never claimed to accept a chain and PowerShell simply runs it once
        per piped item unfiltered.

        Bound-vs-WrongScalar is decided by WHICH PROPERTY the value came from, never by which
        wire key it landed on. A sentinel sourced from an unrelated property arriving on the
        expected key is precisely the WrongScalar defect, so "the key matched" can never
        license a Bound verdict. -Alias exists because property-name binding is legitimately
        satisfied by an alias: Get-PfbArrayConnectionPath's -RemoteName carries the alias
        Name, so a piped `name` property binds it correctly even though the names differ.
    .PARAMETER Alias
        The parameter's declared aliases. A sentinel sourced from one of these is Bound.
    .OUTPUTS
        [PSCustomObject]@{ Outcome; Evidence; BoundWireKey; BoundValue }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$ProbeResult,
        [Parameter(Mandatory)][string]$Parameter,
        [Parameter(Mandatory)][AllowNull()][AllowEmptyString()][string]$WireName,
        [Parameter(Mandatory)][PSCustomObject]$ProbeObject,
        [AllowEmptyCollection()][string[]]$Alias = @()
    )

    if ($ProbeResult.Error) {
        # -like would treat a backtick in the message as an escape character; use .Contains().
        $outcome = if ($ProbeResult.Error.Contains('stringified object')) { 'Guarded' } else { 'BindError' }
        return [PSCustomObject]@{
            Outcome = $outcome; Evidence = $ProbeResult.Error; BoundWireKey = $null; BoundValue = $null
        }
    }

    if (-not $ProbeResult.Calls) {
        return [PSCustomObject]@{
            Outcome = 'NoSelector'; Evidence = 'no request was constructed'; BoundWireKey = $null; BoundValue = $null
        }
    }

    $sentinels = @{}
    foreach ($property in $ProbeObject.PSObject.Properties) { $sentinels["PROBE-$($property.Name)"] = $property.Name }

    foreach ($call in $ProbeResult.Calls) {
        if (-not $call.QueryParams) { continue }
        foreach ($key in @($call.QueryParams.Keys)) {
            $value = [string]$call.QueryParams[$key]
            if ([string]::IsNullOrEmpty($value)) { continue }

            # A stringified PSCustomObject renders as @{a=1; b=2}.
            if ($value.Contains('@{')) {
                return [PSCustomObject]@{
                    Outcome = 'Coerced'; Evidence = $value; BoundWireKey = $key; BoundValue = $value
                }
            }

            foreach ($piece in ($value -split ',')) {
                if (-not $sentinels.ContainsKey($piece)) { continue }
                $sourceProperty = $sentinels[$piece]
                $expected = ($sourceProperty -eq $Parameter) -or ($sourceProperty -in $Alias)
                return [PSCustomObject]@{
                    Outcome      = if ($expected) { 'Bound' } else { 'WrongScalar' }
                    Evidence     = "$key=$value (from property '$sourceProperty')"
                    BoundWireKey = $key
                    BoundValue   = $value
                }
            }
        }
    }

    return [PSCustomObject]@{
        Outcome = 'NoSelector'; Evidence = 'request carried no selector key'; BoundWireKey = $null; BoundValue = $null
    }
}
