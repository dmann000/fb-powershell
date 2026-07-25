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

function Get-PfbSchemaDetailsWalk {
    <#
    .SYNOPSIS
        Internal recursive helper for Get-PfbSchemaPropertyDetails. Not intended to be
        called directly.
    .DESCRIPTION
        Resolves $ref/allOf chains at the *schema* level (exactly like the old
        Get-PfbSchemaPropertyNames did) and accumulates, per property name, the list of
        raw (NOT further $ref-resolved) property schema nodes seen for it, plus the union
        of every visited schema node's own "required" array. Mutates the two accumulator
        arguments in place; both are reference types (Dictionary/HashSet) so no [ref] is
        needed.
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
        [System.Collections.Generic.HashSet[string]]$RequiredNames
    )

    if ($null -eq $Node -or $MaxDepth -le 0) { return }

    $resolved = Resolve-PfbRef -Node $Node -Spec $Spec
    if ($null -eq $resolved) { return }

    if ($resolved.PSObject.Properties.Name -contains 'required' -and $resolved.required) {
        foreach ($requiredName in $resolved.required) { [void]$RequiredNames.Add($requiredName) }
    }

    if ($resolved.PSObject.Properties.Name -contains 'properties' -and $resolved.properties) {
        foreach ($propName in $resolved.properties.PSObject.Properties.Name) {
            if (-not $PropertyNodesByName.ContainsKey($propName)) {
                $PropertyNodesByName[$propName] = [System.Collections.Generic.List[object]]::new()
            }
            # Deliberately store the RAW property node (no Resolve-PfbRef here) -- see
            # the PIN in Get-PfbSchemaPropertyDetails's help for why.
            $PropertyNodesByName[$propName].Add($resolved.properties.$propName)
        }
    }

    if ($resolved.PSObject.Properties.Name -contains 'allOf' -and $resolved.allOf) {
        foreach ($branch in $resolved.allOf) {
            Get-PfbSchemaDetailsWalk -Node $branch -Spec $Spec -MaxDepth ($MaxDepth - 1) `
                -PropertyNodesByName $PropertyNodesByName -RequiredNames $RequiredNames
        }
    }
}

function Get-PfbSchemaPropertyDetails {
    <#
    .SYNOPSIS
        Returns per-top-level-property schema details (ReadOnly, Deprecated, Type, Format,
        Required) for a (possibly $ref'd / allOf'd) request-body schema.
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
    .OUTPUTS
        [PSCustomObject]@{ Name; ReadOnly; Deprecated; Type; Format; Required } per
        top-level property, sorted by Name for deterministic ordering (hashtable/dictionary
        enumeration order is not guaranteed stable across processes).
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

    if ($null -eq $Schema -or $MaxDepth -le 0) { return @() }

    # Keyed by property name -- an API field name. Deliberately a typed Dictionary (not a
    # plain Hashtable): a field literally named "keys"/"count"/"values" would otherwise
    # shadow real member access on a Hashtable (a live bug elsewhere in this codebase).
    $propertyNodesByName = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[object]]]::new()
    $requiredNames = [System.Collections.Generic.HashSet[string]]::new()

    Get-PfbSchemaDetailsWalk -Node $Schema -Spec $Spec -MaxDepth $MaxDepth `
        -PropertyNodesByName $propertyNodesByName -RequiredNames $requiredNames

    $details = [System.Collections.Generic.List[object]]::new()
    foreach ($name in $propertyNodesByName.get_Keys()) {
        $nodes = $propertyNodesByName[$name]
        $readOnly = $false
        $deprecated = $false
        $type = $null
        $format = $null
        foreach ($node in $nodes) {
            if ($null -eq $node) { continue }
            if ($node.PSObject.Properties.Name -contains 'readOnly' -and $node.readOnly) { $readOnly = $true }
            if ($node.PSObject.Properties.Name -contains 'deprecated' -and $node.deprecated) { $deprecated = $true }
            if ($null -eq $type -and $node.PSObject.Properties.Name -contains 'type') { $type = $node.type }
            if ($null -eq $format -and $node.PSObject.Properties.Name -contains 'format') { $format = $node.format }
        }

        $details.Add([PSCustomObject]@{
            Name       = $name
            ReadOnly   = $readOnly
            Deprecated = $deprecated
            Type       = $type
            Format     = $format
            Required   = $requiredNames.Contains($name)
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
        Thin wrapper over Get-PfbSchemaPropertyDetails (decision: one schema walker, not
        two -- this function's only callers are Get-PfbSpecCapabilities, in this same
        file, and its own Pester tests; nothing else in the repo needs a second, parallel
        allOf/$ref walker that would drift from the first). Public contract and existing
        tests are unchanged: still returns bare, de-duplicated property name strings.
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

    return @(Get-PfbSchemaPropertyDetails -Schema $Schema -Spec $Spec -MaxDepth $MaxDepth |
            Select-Object -ExpandProperty Name | Select-Object -Unique)
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
            Deprecated, Type, Format, Required) from Get-PfbSchemaPropertyDetails.
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
            foreach ($paramName in $paramComponentCandidates.get_Keys()) {
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
