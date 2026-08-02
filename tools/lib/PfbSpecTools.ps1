<#
.SYNOPSIS
    Shared helpers for fetching and diffing FlashBlade OpenAPI specs across REST
    versions. Dot-sourced by tools/Update-PfbApiSpecs.ps1, tools/Build-PfbCapabilityMap.ps1,
    and their Pester tests.

.DESCRIPTION
    Each FlashBlade REST version's ReDoc reference page at
    https://code.purestorage.com/swagger/redoc/fb<version>-api-reference.html embeds the
    full OpenAPI 3.0.1 document inline as a JavaScript object literal:

        <script>
          const __redoc_state = {"menu":{...},"spec":{"data":{<openapi doc>}},...};
          var container = document.getElementById('redoc');
          Redoc.hydrate(__redoc_state, container);
        </script>

    There is no standalone .json/.yaml URL — the page's "Download" button serializes this
    in-memory object to a client-side blob: URL, which cannot be fetched directly. These
    helpers extract the embedded object server-side instead.

    Confirmed (2025-07-08, specs fb2.10 and fb2.27):
      - The object is a single valid JSON value (ConvertFrom-Json handles it directly).
      - Paths for versioned resource endpoints are prefixed with the REST version itself,
        e.g. "/api/2.27/arrays" vs "/api/2.10/arrays" — must be normalized before
        comparing the same logical endpoint across versions. A handful of auth/meta
        endpoints (/api/login, /api/api_version, /api/logout, /api/login-banner,
        /oauth2/1.0/token) are NOT version-prefixed and are left as-is.
      - Path items include a vendor extension key "x-pure-authorization-resource"
        alongside real HTTP-method keys — must filter to actual HTTP verbs.
      - Parameters and request bodies are almost always $ref'd into
        components.parameters / components.schemas rather than inlined.
      - The spec contains NO structural JSON Schema "enum" anywhere (verified: zero
        occurrences across all 925 schemas / 224 parameters in fb2.27, and again in
        fb2.10). Allowed values for fields like Bucket.versioning are documented only in
        free-text `description` prose ("Valid values are `none`, `enabled`, ..."). This
        means per-enum-value "introduced in version X" tracking is NOT derivable from
        structured data, and is intentionally out of scope for the generated capability
        map — only endpoint, parameter, and request-body top-level property existence are
        tracked.
#>

# Deliberately NOT Set-StrictMode: these functions walk deeply heterogeneous
# PSCustomObjects deserialized from JSON where a given node legitimately may or may not
# have a given property (e.g. not every operation has .parameters or .requestBody).
# Under StrictMode -Version Latest, referencing a missing property throws instead of
# returning $null, which breaks the `if ($op.parameters)`-style presence checks used
# throughout. Every access here is deliberately null-tolerant.

$script:PfbHttpMethods = @('get', 'put', 'post', 'delete', 'options', 'head', 'patch', 'trace')

function ConvertFrom-PfbRedocHtml {
    <#
    .SYNOPSIS
        Extracts the embedded OpenAPI document from a FlashBlade ReDoc reference page.
    .PARAMETER Html
        The full HTML content of a fb<version>-api-reference.html page.
    .OUTPUTS
        The OpenAPI document (PSCustomObject), i.e. __redoc_state.spec.data.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Html
    )

    $marker = 'const __redoc_state = '
    $markerIdx = $Html.IndexOf($marker)
    if ($markerIdx -lt 0) {
        throw "Could not find '__redoc_state' assignment in the ReDoc page. The page format may have changed."
    }

    $braceStart = $Html.IndexOf('{', $markerIdx)
    if ($braceStart -lt 0) {
        throw "Found '__redoc_state' marker but no opening brace followed it."
    }

    # Balanced-brace scan respecting quoted strings and escape sequences, since the
    # object is minified JSON embedded directly in a <script> block (no surrounding
    # JS syntax to lean on other than the trailing ';').
    $depth = 0
    $inString = $false
    $escaped = $false
    $endIdx = -1
    for ($i = $braceStart; $i -lt $Html.Length; $i++) {
        $ch = $Html[$i]
        if ($inString) {
            if ($escaped) { $escaped = $false }
            elseif ($ch -eq '\') { $escaped = $true }
            elseif ($ch -eq '"') { $inString = $false }
            continue
        }
        else {
            if ($ch -eq '"') { $inString = $true; continue }
            if ($ch -eq '{') { $depth++ }
            elseif ($ch -eq '}') {
                $depth--
                if ($depth -eq 0) { $endIdx = $i; break }
            }
        }
    }

    if ($endIdx -lt 0) {
        throw "Found the start of '__redoc_state' but never found its matching closing brace."
    }

    $jsonText = $Html.Substring($braceStart, $endIdx - $braceStart + 1)

    $state = $null
    try {
        $state = $jsonText | ConvertFrom-Json -Depth 64 -ErrorAction Stop
    }
    catch {
        throw "Extracted '__redoc_state' text was not valid JSON: $($_.Exception.Message)"
    }

    if (-not $state.spec -or -not $state.spec.data) {
        throw "Extracted '__redoc_state' object did not contain the expected .spec.data path."
    }

    return $state.spec.data
}

function ConvertTo-PfbNormalizedPath {
    <#
    .SYNOPSIS
        Strips the embedded "/api/<version>/" prefix from a FlashBlade REST path so the
        same logical endpoint can be compared across spec versions.
    .EXAMPLE
        ConvertTo-PfbNormalizedPath '/api/2.27/arrays'   # -> '/arrays'
        ConvertTo-PfbNormalizedPath '/api/login'          # -> '/api/login' (unversioned, unchanged)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if ($Path -match '^/api/\d+\.\d+/(.*)$') {
        return "/$($Matches[1])"
    }
    return $Path
}

function Resolve-PfbRef {
    <#
    .SYNOPSIS
        Resolves a local JSON-Schema "$ref" pointer (e.g. "#/components/parameters/Foo")
        against the root spec document, following chained refs up to -MaxDepth.
    .DESCRIPTION
        Returns the input node unchanged if it has no "$ref" property. External refs
        (anything not starting with '#/') are not supported and returned unchanged.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $Node,

        [Parameter(Mandatory)]
        $Spec,

        [int]$MaxDepth = 8
    )

    $current = $Node
    $depth = 0
    while ($null -ne $current -and
        ($current.PSObject.Properties.Name -contains '$ref') -and
        $depth -lt $MaxDepth) {

        $refPath = $current.'$ref'
        if ($refPath -notlike '#/*') {
            # External ref — not supported, return as-is rather than guess.
            break
        }

        $segments = $refPath.TrimStart('#').Trim('/') -split '/'
        $target = $Spec
        foreach ($seg in $segments) {
            $segUnescaped = $seg -replace '~1', '/' -replace '~0', '~'
            $target = $target.$segUnescaped
        }
        $current = $target
        $depth++
    }

    return $current
}

function Add-PfbSchemaPropertyNodes {
    <#
    .SYNOPSIS
        Internal recursive helper for Get-PfbSchemaPropertyWalkAccumulators. Not intended to
        be called directly. (Uses the "Add" verb, not "Get", because it returns nothing --
        it mutates its three accumulator arguments in place.)
    .DESCRIPTION
        Resolves $ref/allOf chains at the *schema* level (exactly like the old
        Get-PfbSchemaPropertyNames did) and accumulates, per property name, the list of
        raw (NOT further $ref-resolved) property schema nodes seen for it, plus the union
        of every visited schema node's own "required" array. Mutates the three accumulator
        arguments in place; all are reference types (Dictionary/HashSet) so no [ref] is
        needed. $PropertyNodesByName's key ENUMERATION ORDER is first-seen/traversal order
        (insertion order on a Dictionary[TKey,TValue] with no removals) -- callers that care
        about ordering (Get-PfbSchemaPropertyNames does; Get-PfbSchemaPropertyDetails
        deliberately re-sorts instead) rely on that.

        Owner tracking (feeds Get-PfbSchemaPropertyDetails's OwnerSchema field): as the
        walk descends, -OwnerName carries "the nearest named component ($ref'd from
        #/components/schemas/<Name>) enclosing the node currently being visited",
        inherited unmodified across anonymous/inline allOf branches. Each call re-derives
        its OWN local owner from $Node's OWN raw "$ref" (the ref this specific recursive
        call was reached through) -- NOT from $resolved, and NOT by following anything
        inside the resolved node's properties (that would revisit the PIN below at the
        schema level instead of the property level, but the principle is the same: owner
        comes from the chain being walked INTO, never from dereferencing further once
        there). If $Node has no own "$ref", the inherited -OwnerName passes through
        unchanged -- this is exactly "an anonymous inline branch is not an owner; its
        properties belong to the nearest enclosing NAMED ancestor". Every property added
        to $PropertyNodesByName at this call site is paired 1:1 (same list index) with the
        local owner in $PropertyOwnersByName, a $null entry meaning "no named component
        enclosed this declaration" (e.g. the operation's entire body schema is written
        fully inline with no $ref anywhere in its chain). Because a node's own direct
        "properties" are recorded before recursing into its "allOf" branches, and allOf
        branches are visited in array order, the FIRST entry appended for a given property
        name is always the OUTERMOST (closest-to-the-operation) declaration -- this is the
        tie-break Get-PfbSchemaPropertyDetails uses for the rare case where more than one
        named component in the chain declares the same property name.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        $Node,

        [Parameter(Mandatory)]
        $Spec,

        [int]$MaxDepth,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[object]]]$PropertyNodesByName,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.HashSet[string]]$RequiredNames,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[object]]]$PropertyOwnersByName,

        # Deliberately UNTYPED (not [string]) -- PowerShell's [string] type converter
        # coerces a $null argument to '' on parameter binding even under [AllowNull()],
        # which would silently destroy the null-vs-"" distinction this walk depends on
        # (a bare `[AllowNull()][string]$OwnerName = $null` parameter is NEVER actually
        # $null inside the function body; it is always at least ''). Leaving this
        # untyped preserves a real $null all the way through the recursion.
        [AllowNull()]
        $OwnerName = $null
    )

    if ($null -eq $Node -or $MaxDepth -le 0) { return }

    # The owner for THIS call's own directly-declared properties (and, unless overridden
    # again deeper down, everything reached through its "allOf" branches): if $Node
    # itself is a $ref to a named component (#/components/schemas/<Name>), that name
    # wins; otherwise the owner inherited from the caller passes through unchanged.
    # Deliberately inspects $Node (the raw, pre-resolution argument), never $resolved --
    # see the .DESCRIPTION above and the PIN in Get-PfbSchemaPropertyDetails's help.
    $ownerForThis = $OwnerName
    if ($Node.PSObject.Properties.Name -contains '$ref' -and $Node.'$ref' -match '^#/components/schemas/(.+)$') {
        $ownerForThis = $Matches[1]
    }

    $resolved = Resolve-PfbRef -Node $Node -Spec $Spec
    if ($null -eq $resolved) { return }

    if ($resolved.PSObject.Properties.Name -contains 'required' -and $resolved.required) {
        foreach ($requiredName in $resolved.required) { [void]$RequiredNames.Add($requiredName) }
    }

    if ($resolved.PSObject.Properties.Name -contains 'properties' -and $resolved.properties) {
        foreach ($propName in $resolved.properties.PSObject.Properties.Name) {
            if (-not $PropertyNodesByName.ContainsKey($propName)) {
                $PropertyNodesByName[$propName] = [System.Collections.Generic.List[object]]::new()
                $PropertyOwnersByName[$propName] = [System.Collections.Generic.List[object]]::new()
            }
            # Deliberately store the RAW property node (no Resolve-PfbRef here) -- see
            # the PIN in Get-PfbSchemaPropertyDetails's help for why.
            $PropertyNodesByName[$propName].Add($resolved.properties.$propName)
            $PropertyOwnersByName[$propName].Add($ownerForThis)
        }
    }

    if ($resolved.PSObject.Properties.Name -contains 'allOf' -and $resolved.allOf) {
        foreach ($branch in $resolved.allOf) {
            Add-PfbSchemaPropertyNodes -Node $branch -Spec $Spec -MaxDepth ($MaxDepth - 1) `
                -PropertyNodesByName $PropertyNodesByName -RequiredNames $RequiredNames `
                -PropertyOwnersByName $PropertyOwnersByName -OwnerName $ownerForThis
        }
    }
}

function Get-PfbSchemaPropertyWalkAccumulators {
    <#
    .SYNOPSIS
        Internal: runs Add-PfbSchemaPropertyNodes once over $Schema and returns its three
        accumulators. Not intended to be called directly.
    .DESCRIPTION
        Shared setup for both Get-PfbSchemaPropertyDetails (reports property DETAILS, sorted
        by Name for a stable, deterministic OUTPUT ORDER) and Get-PfbSchemaPropertyNames
        (reports bare NAMES, in first-seen/traversal order -- see that function's help for
        why the two deliberately differ). One schema walker (Add-PfbSchemaPropertyNodes), one
        setup path -- this function exists so that shared setup isn't duplicated between the
        two callers.
    .OUTPUTS
        [PSCustomObject]@{
            PropertyNodesByName  = Dictionary[string, List[object]]  # traversal order
            RequiredNames        = HashSet[string]
            PropertyOwnersByName = Dictionary[string, List[object]]  # parallel to
                                                                      # PropertyNodesByName;
                                                                      # each entry is a
                                                                      # nullable owner-name
                                                                      # string, same index
                                                                      # per occurrence.
        }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $Schema,

        [Parameter(Mandatory)]
        $Spec,

        [int]$MaxDepth = 8
    )

    # Keyed by property name -- an API field name. Deliberately a typed Dictionary (not a
    # plain Hashtable): a field literally named "keys"/"count"/"values" would otherwise
    # shadow real member access on a Hashtable (a live bug elsewhere in this codebase).
    $propertyNodesByName = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[object]]]::new()
    $requiredNames = [System.Collections.Generic.HashSet[string]]::new()
    $propertyOwnersByName = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[object]]]::new()

    if ($null -ne $Schema -and $MaxDepth -gt 0) {
        Add-PfbSchemaPropertyNodes -Node $Schema -Spec $Spec -MaxDepth $MaxDepth `
            -PropertyNodesByName $propertyNodesByName -RequiredNames $requiredNames `
            -PropertyOwnersByName $propertyOwnersByName
    }

    return [PSCustomObject]@{
        PropertyNodesByName  = $propertyNodesByName
        RequiredNames        = $requiredNames
        PropertyOwnersByName = $propertyOwnersByName
    }
}

function Get-PfbSchemaPropertyDetails {
    <#
    .SYNOPSIS
        Returns per-top-level-property schema details (ReadOnly, Deprecated, Type, Format,
        Required, OwnerSchema) for a (possibly $ref'd / allOf'd) request-body schema.
    .DESCRIPTION
        Walks the same $ref/allOf resolution Get-PfbSchemaPropertyNames always has (the
        common "<Resource>Patch: allOf [BaseResource, {extra properties}]" pattern in these
        specs), but keeps each property's own schema node instead of discarding it down to
        a bare name. This is now the single source of truth for that walk --
        Get-PfbSchemaPropertyNames is a thin wrapper over it (one walker, not two, since
        nothing else in the repo needs a second one).

        PIN -- do NOT follow a property's own "$ref" (or dive into an "allOf" nested
        *inside* the property node) to look for ReadOnly/Deprecated/Type/Format: only the
        property node's own directly-declared keys are read. Example:
        `direction: { $ref: '#/components/schemas/_direction' }` on
        `_replicaLinkBuiltIn` -- `_direction` itself is `readOnly: true`, but `direction`'s
        own node has no sibling `readOnly` key. Resolving into it would flip `direction` to
        read-only and move it out of the actionable-gap list; measured against fb2.27 that
        changes the baseline split from 226 read-only / 402 addable / 33 enum-ready to
        227 / 401 / 32 -- the only field on the whole surface where it matters. This is the
        same "top-level readOnly only, no recursive nested-schema analysis" rule applied to
        one more level: it already governs at the schema level (no recursing into a
        property's *referenced* schema body), this just states it applies to the property
        node's own attributes too, not merely its `properties` collection.

        Merge rule across "allOf" branches of the *schema itself* (not the property): if a
        property with the same name is declared by more than one branch, ReadOnly and
        Deprecated are OR'd (any branch marking it true wins) and Required is the union of
        every visited node's own `required: [...]` array. Type/Format use the first
        non-null value encountered in traversal order. Verified: 0 real name collisions
        across allOf branches in all of fb2.27, so this only matters for a future spec.

        OwnerSchema: the name of the nearest enclosing NAMED component -- a schema reached
        via "#/components/schemas/<Name>" -- whose own "properties" block directly
        declares this property. An anonymous/inline allOf branch is never itself an
        owner: a property declared there is attributed to the nearest named ancestor
        enclosing that branch (tracked via Add-PfbSchemaPropertyNodes's -OwnerName
        inheritance). If no named component encloses the declaration anywhere in the
        chain (the operation's entire body schema is written fully inline with no $ref
        at all), OwnerSchema is explicitly $null -- never ''. The two are NOT
        interchangeable: $null means "no named owner exists", '' would be indistinguishable
        from a bug that failed to populate the field, so this function never emits ''.
        Multi-owner rule: if more than one named component in the chain directly declares
        the same property name (2 occurrences measured across all of fb2.27: `POST
        /array-connections`' `encrypted` and `throttle` properties, each with candidate
        owners `ArrayConnection` and `ArrayConnectionPost` -- see the real-spec
        verification in this repo's task notes; the rule is close to academic today but is
        a real, reachable case for a future spec), the OUTERMOST one wins,
        i.e. the declaration closest to the operation's own body schema. Because a node's
        own direct properties are recorded before its allOf branches are recursed into,
        and siblings are visited in array order, "outermost" is simply "first-seen" in
        Add-PfbSchemaPropertyNodes's traversal order -- consistent with how Type/Format
        already resolve ties in this same function.
    .OUTPUTS
        [PSCustomObject]@{ Name; ReadOnly; Deprecated; Type; Format; Required; OwnerSchema }
        per top-level property, sorted by Name for deterministic OUTPUT ordering (this is
        distinct from Get-PfbSchemaPropertyNames, which intentionally preserves traversal
        order instead -- see that function's help).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $Schema,

        [Parameter(Mandatory)]
        $Spec,

        [int]$MaxDepth = 8
    )

    $walk = Get-PfbSchemaPropertyWalkAccumulators -Schema $Schema -Spec $Spec -MaxDepth $MaxDepth
    $propertyNodesByName = $walk.PropertyNodesByName
    $requiredNames = $walk.RequiredNames
    $propertyOwnersByName = $walk.PropertyOwnersByName

    $details = [System.Collections.Generic.List[object]]::new()
    foreach ($name in $propertyNodesByName.get_Keys()) {
        $nodes = $propertyNodesByName[$name]
        $readOnly = $false
        $deprecated = $false
        $type = $null
        $format = $null
        foreach ($node in $nodes) {
            if ($null -eq $node) { continue }
            # $node.PSObject.Properties.Name -contains 'readOnly' only finds a REAL property
            # literally named 'readOnly' when $node is a PSCustomObject -- exactly what
            # ConvertFrom-Json always produces for a real spec. On a plain Hashtable/@{}
            # (easy to reach for in an ad hoc test fixture), PSObject.Properties.Name instead
            # exposes the DICTIONARY's own members (Keys, Values, Count, ...) and will never
            # find a key named 'readOnly', no matter what the hashtable actually contains.
            # Every fixture for this function must use [PSCustomObject], never @{}, for
            # exactly this reason.
            if ($node.PSObject.Properties.Name -contains 'readOnly' -and $node.readOnly) { $readOnly = $true }
            if ($node.PSObject.Properties.Name -contains 'deprecated' -and $node.deprecated) { $deprecated = $true }
            if ($null -eq $type -and $node.PSObject.Properties.Name -contains 'type') { $type = $node.type }
            if ($null -eq $format -and $node.PSObject.Properties.Name -contains 'format') { $format = $node.format }
        }

        # Outermost-wins: the first entry recorded for this property name is always the
        # shallowest (closest to the operation's own body schema) -- see the ordering
        # guarantee documented on Add-PfbSchemaPropertyNodes. $null here is a legitimate
        # value (no named component enclosed the declaration), never coerced to ''.
        # NOTE: deliberately `$null -ne $owners`, NOT the bare-truthy `$owners`/`if ($owners)`
        # -- a single-element collection whose only element is itself $null (exactly the
        # "fully inline, no owner" case) evaluates as FALSE under PowerShell's
        # single-item-array boolean coercion, which would take this down the wrong branch
        # for the right-looking-by-coincidence reason.
        $owners = $propertyOwnersByName[$name]
        $ownerSchema = if ($null -ne $owners -and $owners.Count -gt 0) { $owners[0] } else { $null }

        $details.Add([PSCustomObject]@{
            Name        = $name
            ReadOnly    = $readOnly
            Deprecated  = $deprecated
            Type        = $type
            Format      = $format
            Required    = $requiredNames.Contains($name)
            OwnerSchema = $ownerSchema
        })
    }

    return @($details | Sort-Object Name)
}

function Get-PfbSchemaPropertyNames {
    <#
    .SYNOPSIS
        Returns the set of top-level property names for a (possibly $ref'd / allOf'd)
        request-body schema.
    .DESCRIPTION
        Shares its walk with Get-PfbSchemaPropertyDetails via
        Get-PfbSchemaPropertyWalkAccumulators (decision: one schema walker, not two -- this
        function's only callers are Get-PfbSpecCapabilities, in this same file, and its own
        Pester tests; nothing else in the repo needs a second, parallel allOf/$ref walker
        that would drift from the first). Public contract and existing tests are unchanged:
        still returns bare, de-duplicated property name strings.

        Deliberately returns names in TRAVERSAL order (== Dictionary insertion order), NOT
        sorted like Get-PfbSchemaPropertyDetails's output is. Controller ruling: this
        function feeds tools/Build-PfbCapabilityMap.ps1's BodyProperties, which inserts into
        an [ordered]@{} in exactly this order, and 124 of 632 endpoints in the committed
        Data/PfbCapabilityMap.json already have non-alphabetical bodyProperties -- sorting
        here would churn ~1100 keys in a tracked file for zero behavioural benefit, burying
        a later additive change in reordering noise. This is NOT a determinism regression:
        the randomization hazard this codebase guards against is Hashtable/@{} ENUMERATION
        order (a per-process randomized hash seed), not a Dictionary[TKey,TValue]'s
        insertion-order enumeration, which is stable here (no removals ever occur). Do not
        "fix" this back to Sort-Object.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $Schema,

        [Parameter(Mandatory)]
        $Spec,

        [int]$MaxDepth = 8
    )

    $walk = Get-PfbSchemaPropertyWalkAccumulators -Schema $Schema -Spec $Spec -MaxDepth $MaxDepth
    return @($walk.PropertyNodesByName.get_Keys())
}

function Get-PfbSpecCapabilities {
    <#
    .SYNOPSIS
        Flattens a single FlashBlade OpenAPI document into a list of capability records:
        one per (HTTP method, normalized path), each with its parameter names and
        request-body top-level property names/details.
    .DESCRIPTION
        Additive outputs alongside the original Parameters/BodyProperties (unchanged in
        name, type, and contents):
          - BodyPropertyDetails: the full per-property detail records (Name, ReadOnly,
            Deprecated, Type, Format, Required, OwnerSchema) from
            Get-PfbSchemaPropertyDetails.
          - ReadOnlyBodyProperties / DeprecatedBodyProperties: string[] convenience
            projections of the above, sorted for determinism.
          - ParameterComponents: a { paramName: componentName } map
            (System.Collections.Generic.Dictionary[string,string]) recovered from each
            query/path/header parameter's own "$ref" (e.g.
            "#/components/parameters/Context_names_get" -> "Context_names_get"), i.e. the
            resolved parameter's component identity, not anything on the resolved object
            itself. Covers the SAME parameter set as Parameters above (all `in:` locations,
            not filtered to query) so the two stay zippable per endpoint. A parameter
            declared inline with no "$ref" contributes no entry -- the key is omitted
            entirely (never emitted as $null/'' , which would be indistinguishable from a
            bug downstream). If the same parameter name resolves to more than one distinct
            component on a single operation (not expected -- 0 occurrences across all of
            fb2.27), a warning is emitted and the alphabetically-first component name wins,
            deterministically.
    .OUTPUTS
        [PSCustomObject]@{
            Method; Path; Parameters = string[]; BodyProperties = string[];
            BodyPropertyDetails = object[]; ReadOnlyBodyProperties = string[];
            DeprecatedBodyProperties = string[];
            ParameterComponents = System.Collections.Generic.Dictionary[string,string]
        }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Spec
    )

    $results = [System.Collections.Generic.List[object]]::new()

    if (-not $Spec.paths) { return $results }

    foreach ($rawPath in $Spec.paths.PSObject.Properties.Name) {
        $pathItem = $Spec.paths.$rawPath
        $normalizedPath = ConvertTo-PfbNormalizedPath -Path $rawPath

        foreach ($methodName in $pathItem.PSObject.Properties.Name) {
            if ($script:PfbHttpMethods -notcontains $methodName) { continue }
            $op = $pathItem.$methodName

            $paramNames = [System.Collections.Generic.List[string]]::new()
            # name -> candidate component names (collected raw; resolved to one winner
            # after the loop so a same-name collision can be detected and reported
            # rather than silently overwritten by iteration order).
            $paramComponentCandidates = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[string]]]::new()
            if ($op.parameters) {
                foreach ($p in $op.parameters) {
                    $resolved = Resolve-PfbRef -Node $p -Spec $Spec
                    if ($resolved -and $resolved.PSObject.Properties.Name -contains 'name' -and $resolved.name) {
                        $paramNames.Add($resolved.name)

                        # Component identity comes from the $ref STRING on the unresolved
                        # node $p (e.g. '#/components/parameters/Context_names_get' ->
                        # 'Context_names_get') -- never from anything on $resolved.
                        if ($p.PSObject.Properties.Name -contains '$ref' -and $p.'$ref') {
                            $componentName = ($p.'$ref' -split '/')[-1]
                            if (-not $paramComponentCandidates.ContainsKey($resolved.name)) {
                                $paramComponentCandidates[$resolved.name] = [System.Collections.Generic.List[string]]::new()
                            }
                            $paramComponentCandidates[$resolved.name].Add($componentName)
                        }
                    }
                }
            }

            $paramComponents = [System.Collections.Generic.Dictionary[string, string]]::new()
            # Populate in sorted-key order explicitly. Dictionary[TKey,TValue] enumeration
            # happens to preserve insertion order in practice (relied on elsewhere in this
            # file -- see Get-PfbSchemaPropertyNames), but that is a .NET implementation
            # detail, not a contract, and this map gets serialized into a tracked JSON file
            # downstream -- make the ordering explicit rather than incidental.
            foreach ($paramName in ($paramComponentCandidates.get_Keys() | Sort-Object)) {
                $candidates = @($paramComponentCandidates[$paramName] | Select-Object -Unique)
                if ($candidates.Count -gt 1) {
                    $sortedCandidates = @($candidates | Sort-Object)
                    Write-Warning ("Get-PfbSpecCapabilities: parameter '{0}' on {1} {2} resolves to multiple different components ({3}) -- this should not occur; deterministically keeping '{4}' (alphabetically first)." -f `
                            $paramName, $methodName.ToUpper(), $normalizedPath, ($sortedCandidates -join ', '), $sortedCandidates[0])
                    $paramComponents[$paramName] = $sortedCandidates[0]
                }
                else {
                    $paramComponents[$paramName] = $candidates[0]
                }
            }

            $bodyPropNames = @()
            $bodyPropertyDetails = @()
            if ($op.requestBody -and $op.requestBody.content) {
                $mediaTypes = $op.requestBody.content.PSObject.Properties.Name
                $mediaKey = if ($mediaTypes -contains 'application/json') { 'application/json' } else { $mediaTypes | Select-Object -First 1 }
                if ($mediaKey) {
                    $mediaSchema = $op.requestBody.content.$mediaKey.schema
                    $bodyPropNames = Get-PfbSchemaPropertyNames -Schema $mediaSchema -Spec $Spec
                    $bodyPropertyDetails = @(Get-PfbSchemaPropertyDetails -Schema $mediaSchema -Spec $Spec)
                }
            }

            $readOnlyBodyProperties = @($bodyPropertyDetails | Where-Object ReadOnly | ForEach-Object Name | Sort-Object)
            $deprecatedBodyProperties = @($bodyPropertyDetails | Where-Object Deprecated | ForEach-Object Name | Sort-Object)

            $results.Add([PSCustomObject]@{
                Method                   = $methodName.ToUpper()
                Path                     = $normalizedPath
                Parameters               = ($paramNames | Select-Object -Unique)
                BodyProperties           = $bodyPropNames
                BodyPropertyDetails      = $bodyPropertyDetails
                ReadOnlyBodyProperties   = $readOnlyBodyProperties
                DeprecatedBodyProperties = $deprecatedBodyProperties
                ParameterComponents      = $paramComponents
            })
        }
    }

    return $results
}

function Get-PfbResponseSchema {
    <#
    .SYNOPSIS
        Returns the schema node of an operation's first 2xx response that carries a JSON
        media type, or $null if it has none.
    .DESCRIPTION
        Response codes are examined in ascending string order ('200' before '204'), so a
        200 wins over a 201/204 when an operation declares several. 'application/json' is
        preferred; if absent, the first declared media type is used, matching the request-side
        behaviour in Get-PfbSpecCapabilities.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $Operation,

        [Parameter(Mandatory)]
        $Spec
    )

    if ($null -eq $Operation -or -not $Operation.responses) { return $null }

    $codes = @($Operation.responses.PSObject.Properties.Name |
            Where-Object { $_ -match '^2\d\d$' } | Sort-Object)

    foreach ($code in $codes) {
        $response = Resolve-PfbRef -Node $Operation.responses.$code -Spec $Spec
        if ($null -eq $response -or -not $response.content) { continue }

        $mediaTypes = $response.content.PSObject.Properties.Name
        $mediaKey = if ($mediaTypes -contains 'application/json') {
            'application/json'
        }
        else {
            $mediaTypes | Select-Object -First 1
        }
        if (-not $mediaKey) { continue }

        if ($response.content.$mediaKey.schema) { return $response.content.$mediaKey.schema }
    }

    return $null
}

function Get-PfbSpecResponseShapes {
    <#
    .SYNOPSIS
        Flattens a FlashBlade OpenAPI document into one response-shape record per
        (HTTP method, normalized path): the 2xx envelope's top-level property names, and the
        property names of the items[] array's element schema one level deep.
    .DESCRIPTION
        Granularity is deliberately TWO levels and no more -- the envelope, and items[]
        element properties. Depth 3 was measured and rejected: of 13 depth-3 disappearances
        across all 29 cached specs, 11 are children of a parent already caught at level 1
        (duplicates needing rollup suppression) and the other 2 are a confirmed spec-authoring
        false positive (items[].local_snapshot.resource_type, dropped from the inline schema
        text at fb2.11, not from the API). It costs 2.2x the artifact for zero true findings.
        See docs/superpowers/specs/2026-08-01-response-shape-drift-design.md.

        MaxDepth defaults to 32, NOT to the 8 used elsewhere in this file. This is
        load-bearing, not incidental: several fb2.12-2.16 schemas nest allOf more deeply
        than 8, and reading them truncated makes real fields look absent -- which an
        accumulator across versions then records as a REMOVAL. Measured: 184 false removals
        at depth 8 versus a true total of 11 at depth 32. Do not "simplify" this to match
        the other defaults in this file.

        Reuses Get-PfbSchemaPropertyWalkAccumulators (and therefore
        Add-PfbSchemaPropertyNodes) rather than introducing a second allOf/$ref walker --
        one walker, per the toolchain's standing decision.
    .OUTPUTS
        [PSCustomObject]@{ Method; Path; EnvelopeProperties = string[]; ItemProperties = string[] }
        Both collections are sorted for deterministic output.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Spec,

        [int]$MaxDepth = 32
    )

    $results = [System.Collections.Generic.List[object]]::new()
    if (-not $Spec.paths) { return $results }

    foreach ($rawPath in $Spec.paths.PSObject.Properties.Name) {
        $pathItem = $Spec.paths.$rawPath
        $normalizedPath = ConvertTo-PfbNormalizedPath -Path $rawPath

        foreach ($methodName in $pathItem.PSObject.Properties.Name) {
            if ($script:PfbHttpMethods -notcontains $methodName) { continue }

            $schema = Get-PfbResponseSchema -Operation $pathItem.$methodName -Spec $Spec
            if ($null -eq $schema) { continue }

            $envelopeProperties = @(Get-PfbSchemaPropertyNames -Schema $schema -Spec $Spec -MaxDepth $MaxDepth)

            # Reach items[]'s element schema through the SAME walk, so an envelope that
            # declares items behind an allOf/$ref chain is handled identically to an inline one.
            $itemProperties = @()
            $walk = Get-PfbSchemaPropertyWalkAccumulators -Schema $schema -Spec $Spec -MaxDepth $MaxDepth
            if ($walk.PropertyNodesByName.ContainsKey('items')) {
                $itemsResolved = Resolve-PfbRef -Node $walk.PropertyNodesByName['items'][0] -Spec $Spec
                if ($null -ne $itemsResolved -and $itemsResolved.type -eq 'array' -and $itemsResolved.items) {
                    $itemProperties = @(Get-PfbSchemaPropertyNames -Schema $itemsResolved.items -Spec $Spec -MaxDepth $MaxDepth)
                }
            }

            $results.Add([PSCustomObject]@{
                    Method             = $methodName.ToUpper()
                    Path               = $normalizedPath
                    EnvelopeProperties = @($envelopeProperties | Sort-Object)
                    ItemProperties     = @($itemProperties | Sort-Object)
                })
        }
    }

    return $results
}

function Get-PfbSwaggerIndexVersions {
    <#
    .SYNOPSIS
        Parses the FlashBlade swagger index page for the list of published REST versions.
    .PARAMETER IndexHtml
        The HTML content of https://code.purestorage.com/swagger/.
    .OUTPUTS
        Version strings sorted ascending, e.g. '2.0', '2.1', ..., '2.27'.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$IndexHtml
    )

    $matches = [regex]::Matches($IndexHtml, 'redoc/fb(\d+\.\d+)-api-reference\.html')
    $versions = $matches | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique

    return $versions | ForEach-Object {
        $parts = $_ -split '\.'
        [PSCustomObject]@{
            Version = $_
            Major   = [int]$parts[0]
            Minor   = [int]$parts[1]
        }
    } | Sort-Object Major, Minor | Select-Object -ExpandProperty Version
}
