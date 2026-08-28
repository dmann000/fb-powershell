<#
.SYNOPSIS
    Shared helpers for extracting prose-documented value enumerations (e.g.
    Bucket.versioning's "Valid values are `none`, `enabled`, and `suspended`.") from
    FlashBlade OpenAPI specs. Dot-sourced by tools/Build-PfbValueEnumMap.ps1 and its
    Pester tests, parallel to tools/lib/PfbSpecTools.ps1.

.DESCRIPTION
    As tools/lib/PfbSpecTools.ps1's header documents, the FlashBlade OpenAPI spec has
    NO structural JSON Schema "enum" anywhere. Allowed values for fields like
    Bucket.versioning are documented only in free-text `description` prose. This file
    parses that prose instead.

    Two correctness rules discovered while building this against the real cached specs
    (fb2.27.json), each with its own regression test -- do not regress either:

    1. MANY schemas (e.g. Bucket, NfsExportPolicyRuleBase) are `allOf` compositions with
       no direct `.properties` of their own -- the real property and its `description`
       live behind `allOf` branches and $ref's. Reading `.description` directly off such
       a schema's own property node returns nothing; the walker below resolves $ref and
       recurses into `allOf`, exactly like Get-PfbSchemaPropertyNames in PfbSpecTools.ps1.

    2. Value extraction must be scoped to the matched "Valid/Possible values (are|include)
       ... ." TRIGGER SENTENCE only, not the whole description. Several descriptions
       repeat the enum's own backtick-quoted values again in explanatory prose *after*
       the trigger sentence (e.g. `_presetWorkloadExportConfigurationNfsRule.access`
       explains each value in a following paragraph) - extracting from the whole
       description would over-collect from that trailing prose, not just the enum
       itself. It happens not to change the *value set* for that particular field (the
       trailing prose repeats the same values), but it is not safe to rely on that in
       general, so the sentence must be isolated first.

    Two trigger phrasings were confirmed live against fb2.27.json: "Valid values
    are/include ..." (dominant, ~376 hits) and "Possible values are/include ..." (a
    real, non-one-off variant, ~25 hits, e.g. AlertWatcher(Post).minimum_notification_severity).
    Both are treated identically once the trigger sentence is isolated.

    Correctness rule carried over from the design doc, confirmed live: key every record
    by (SchemaName, PropertyName) or (ParameterComponentName), never by bare property
    name alone. NfsExportPolicyRuleBase.access ('root-squash'/'all-squash'/'no-squash')
    and the presets-only _presetWorkloadExportConfigurationNfsRule.access
    ('root-squash'/'all-squash'/'no-root-squash') are two distinct schemas that happen
    to share a property name with non-identical value spellings - collapsing by bare
    name would silently merge them into one incoherent value list.

    3. A THIRD source exists beyond components.schemas and components.parameters: a
       parameter defined INLINE, directly under spec.paths.<path>.<method>.parameters,
       never registered in the shared components.parameters dictionary at all. Confirmed
       live: GET /arrays/space's `type` query parameter (valid values `array`,
       `file-system`, `object-store`) was inline, with a full "Valid values..."
       description, from REST 2.0 through 2.16 - only becoming a
       $ref: '#/components/parameters/Type' at 2.17 (same description, word for word;
       a pure documentation refactor, not an API change). Also confirmed live: spec
       path keys carry the version prefix (e.g. "/api/2.27/arrays/space", not
       "/arrays/space") - that prefix MUST be stripped before keying, or the same
       logical endpoint would get a different Key per spec version and the
       introduced-in-version diffing in Build-PfbValueEnumMap.ps1 would never see it as
       the same field twice. Keyed by "<METHOD> <path>#<paramName>" (Kind =
       'inline-parameter') - never just the bare parameter name, for the same
       never-collapse-by-bare-name reason as above: two different operations can each
       inline-define a same-named parameter with different value sets. $ref entries
       under spec.paths.<path>.<method>.parameters are deliberately NOT reprocessed by
       this pass - they're already covered by the components.parameters pass over the
       referenced dictionary; reprocessing them here would double-count.
#>

# Deliberately NOT Set-StrictMode -- same reasoning as PfbSpecTools.ps1: these functions
# walk heterogeneous PSCustomObjects from JSON where a given node legitimately may or
# may not have a given property (not every schema has .properties or .allOf).

# Trigger sentence: "Valid values are `a`, `b`." or "Possible values include ...".
# Captures the sentence itself so downstream parsing only ever looks inside it.
$script:PfbValueEnumTriggerPattern = '(?:Valid|Possible) values (?:are|include)[^.]*\.'

function Get-PfbValueEnumTriggerSentence {
    <#
    .SYNOPSIS
        Returns the "Valid/Possible values ... ." sentence from a description, or $null
        if the description does not contain one.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Description
    )

    if (-not $Description) { return $null }

    $m = [regex]::Match($Description, $script:PfbValueEnumTriggerPattern)
    if (-not $m.Success) { return $null }

    return $m.Value
}

function ConvertFrom-PfbValueEnumProse {
    <#
    .SYNOPSIS
        Parses a single trigger sentence (see Get-PfbValueEnumTriggerSentence) into its
        enumerated values, if it is actually an enumeration.
    .DESCRIPTION
        Tries, in order: backtick-quoted values (the dominant pattern), then
        double-quoted values, then bare comma-separated tokens -- only for a trigger
        sentence that didn't already parse via an earlier pattern. Sentences that match
        the trigger phrase but are not really an enumeration (e.g. a numeric range, or
        free-text prose that happens to contain the trigger words) are explicitly
        classified as unparsed rather than force-parsed, per this repo's "never silently
        over-claim coverage" convention (see Assert-PfbApiCapability / PfbSpecTools.ps1).
    .OUTPUTS
        [PSCustomObject]@{ Values = string[]; Parsed = bool; TriggerText = string }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TriggerSentence
    )

    # Backtick-quoted: `none`, `enabled`, and `suspended`.
    # Guarded by a parity check: a real, confirmed spec bug (policy_type's `smb-client`,
    # present in every cached version REST 2.14-2.27) has a missing opening backtick, which
    # makes [regex]::Matches silently re-synchronize on the next backtick and return
    # corrupted values (a dropped real value plus garbage comma/whitespace "values") while
    # still reporting success. An odd backtick count can never validly pair, so treat it as
    # unparsed rather than trust a match set built from misaligned pairs -- no real value in
    # this spec has ever contained a literal backtick, so this is a safe structural signal,
    # not a guess.
    $backtickCount = ([regex]::Matches($TriggerSentence, '`')).Count
    if ($backtickCount % 2 -eq 0) {
        $backtickMatches = [regex]::Matches($TriggerSentence, '`([^`]+)`')
        if ($backtickMatches.Count -gt 0) {
            $values = $backtickMatches | ForEach-Object { $_.Groups[1].Value }
            return [PSCustomObject]@{ Values = @($values); Parsed = $true; TriggerText = $TriggerSentence }
        }
    }

    # Double-quoted: "policy", "sacl". Same parity guard as the backtick pattern above.
    $quoteCount = ([regex]::Matches($TriggerSentence, '"')).Count
    if ($quoteCount % 2 -eq 0) {
        $quoteMatches = [regex]::Matches($TriggerSentence, '"([^"]+)"')
        if ($quoteMatches.Count -gt 0) {
            $values = $quoteMatches | ForEach-Object { $_.Groups[1].Value }
            return [PSCustomObject]@{ Values = @($values); Parsed = $true; TriggerText = $TriggerSentence }
        }
    }

    # Bare comma-separated tokens after "are"/"include", e.g.:
    #   "Valid values include QSFP, QSFP+, QSFP28, QSFP56, QSFP-DD, RJ-45, and -."
    # Deliberately conservative: only fires when the sentence has no quote characters or
    # backticks at all (so it can't misfire on the malformed-quote case, e.g. "include
    # 'success' or failure'." -- a real, confirmed-malformed example in the source spec that
    # is left unparsed rather than force-parsed -- nor on a malformed *backtick* case, e.g.
    # policy_type's missing-backtick `smb-client` bug: without this exclusion, a sentence
    # that fails the backtick-parity guard above would fall through here and this
    # whitespace-only rejection check would wrongly accept tokens that still contain their
    # stray backtick characters, since a backtick isn't whitespace) and the tail actually
    # looks like a short comma/space-separated token list (no long runs of lowercase prose
    # words).
    if ($TriggerSentence -notmatch '[''"``]') {
        # [\s\S] (not '.') so the lazy capture can span an embedded newline -- real spec
        # prose wraps mid-sentence (e.g. "...`all-squash`, and\n`no-root-squash`.") and
        # '.' does not match '\n' by default, which would otherwise force the match to
        # anchor past the embedded newline onto a later, spurious "are"/"include".
        $tail = [regex]::Match($TriggerSentence, '(?:are|include)\s+([\s\S]+?)\.\s*$')
        if ($tail.Success) {
            $rawTokens = $tail.Groups[1].Value -replace '\band\b', ',' -split ','
            $tokens = $rawTokens | ForEach-Object { $_.Trim() } | Where-Object { $_ }
            # Reject if any token contains whitespace (a real value token here, e.g.
            # "QSFP28" or "-", never does) -- that indicates free-text prose rather than
            # a token list, e.g. "controllers and blades from hardware list".
            $looksLikeTokenList = $tokens.Count -gt 0 -and -not ($tokens | Where-Object { $_ -match '\s' })
            if ($looksLikeTokenList) {
                return [PSCustomObject]@{ Values = @($tokens); Parsed = $true; TriggerText = $TriggerSentence }
            }
        }
    }

    return [PSCustomObject]@{ Values = @(); Parsed = $false; TriggerText = $TriggerSentence }
}

function Get-PfbSchemaPropertyDescriptions {
    <#
    .SYNOPSIS
        Returns resolved { propertyName -> description } pairs for a (possibly $ref'd /
        allOf'd) schema -- the description-carrying counterpart to
        Get-PfbSchemaPropertyNames in PfbSpecTools.ps1.
    .DESCRIPTION
        Resolves $ref chains and merges across "allOf" branches, same pattern as
        Get-PfbSchemaPropertyNames. Also descends into array `items` schemas so a
        property typed as an array-of-enum-strings is still captured. Does not attempt
        oneOf/anyOf (not used for FlashBlade schemas as of the versions surveyed).
        A property whose first-seen branch supplies a description wins; later branches
        supplying the same property name do not overwrite it (first-branch-wins, same
        precedence as Get-PfbSchemaPropertyNames's de-dup).
    .OUTPUTS
        Hashtable of propertyName -> description string (only properties with a
        non-empty resolved description are included).
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

    # [ordered], not a plain Hashtable: this dictionary's .Keys enumeration order flows
    # straight through to Reports/PfbValueEnumMap.json's entry order (via
    # Get-PfbSpecValueEnums's "foreach ($propName in $descriptions.Keys)" pass) -- a
    # plain Hashtable's enumeration order depends on .NET's per-process-randomized
    # string hash codes, so without [ordered] the report's entry order silently
    # reshuffles run-to-run on identical input.
    $result = [ordered]@{}
    if ($null -eq $Schema -or $MaxDepth -le 0) { return $result }

    $resolved = Resolve-PfbRef -Node $Schema -Spec $Spec
    if ($null -eq $resolved) { return $result }

    if ($resolved.PSObject.Properties.Name -contains 'properties' -and $resolved.properties) {
        foreach ($propName in $resolved.properties.PSObject.Properties.Name) {
            $propSchema = Resolve-PfbRef -Node $resolved.properties.$propName -Spec $Spec
            if (-not $propSchema) { continue }

            $desc = $null
            if ($propSchema.PSObject.Properties.Name -contains 'description' -and $propSchema.description) {
                $desc = $propSchema.description
            }
            elseif ($propSchema.PSObject.Properties.Name -contains 'items' -and $propSchema.items) {
                $itemSchema = Resolve-PfbRef -Node $propSchema.items -Spec $Spec
                if ($itemSchema -and $itemSchema.PSObject.Properties.Name -contains 'description' -and $itemSchema.description) {
                    $desc = $itemSchema.description
                }
            }

            if ($desc -and -not $result.Contains($propName)) {
                $result[$propName] = $desc
            }
        }
    }

    if ($resolved.PSObject.Properties.Name -contains 'allOf' -and $resolved.allOf) {
        foreach ($branch in $resolved.allOf) {
            $branchResult = Get-PfbSchemaPropertyDescriptions -Schema $branch -Spec $Spec -MaxDepth ($MaxDepth - 1)
            foreach ($k in $branchResult.Keys) {
                if (-not $result.Contains($k)) { $result[$k] = $branchResult[$k] }
            }
        }
    }

    return $result
}

function Get-PfbSpecValueEnums {
    <#
    .SYNOPSIS
        Extracts every prose-documented value enumeration from a single FlashBlade
        OpenAPI spec, across components.schemas properties, components.parameters, and
        inline (non-$ref) parameters defined directly on a spec.paths operation.
    .DESCRIPTION
        Never collapses by bare property/parameter name -- each record's Key is
        "<SchemaName>.<PropertyName>" for schema properties (Kind = 'schema'), the
        parameter's own component name (Kind = 'parameter'), or
        "<METHOD> <path>#<paramName>" for a parameter defined inline on a path operation
        rather than via a components.parameters $ref (Kind = 'inline-parameter'). Two
        schemas sharing a property name with different value sets (e.g. the squash-mode
        case) always produce two separate records; likewise two operations that each
        inline-define a same-named parameter with a different value set.

        Every description that matches the trigger phrase produces a record, whether or
        not it successfully parsed into values -- callers must check .Parsed rather than
        assume every returned record has a usable value list. This is deliberate: it is
        the mechanism by which "unparsed" prose is surfaced rather than silently dropped.
    .OUTPUTS
        [PSCustomObject]@{ Key; Kind; Name; Values; Parsed; TriggerText }

        Key is the collision-safe identity ("SchemaName.PropertyName", the parameter's
        own components.parameters dictionary key, or "<METHOD> <path>#<paramName>" for an
        inline-parameter record) -- always unique, always what downstream diffing/storage
        should key on. Name is the field's own short name as it actually appears on the
        wire (the schema property name, or the parameter's "name" field, e.g.
        "protocol") -- the more useful match target for reconciling against a cmdlet's
        hand-written parameter, since a query parameter's components.parameters
        dictionary key does not have to equal its wire "name". For inline-parameter
        records, Key already ends in "#<Name>", so Name is always redundant with the
        tail of Key by construction -- kept as its own field anyway, for the same
        uniform-shape reason 'schema'/'parameter' records carry it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Spec
    )

    $results = [System.Collections.Generic.List[object]]::new()

    if ($Spec.components -and $Spec.components.schemas) {
        foreach ($schemaName in $Spec.components.schemas.PSObject.Properties.Name) {
            $descriptions = Get-PfbSchemaPropertyDescriptions -Schema $Spec.components.schemas.$schemaName -Spec $Spec

            foreach ($propName in $descriptions.Keys) {
                $trigger = Get-PfbValueEnumTriggerSentence -Description $descriptions[$propName]
                if (-not $trigger) { continue }

                $parsed = ConvertFrom-PfbValueEnumProse -TriggerSentence $trigger
                $results.Add([PSCustomObject]@{
                    Key         = "$schemaName.$propName"
                    Kind        = 'schema'
                    Name        = $propName
                    Values      = $parsed.Values
                    Parsed      = $parsed.Parsed
                    TriggerText = $parsed.TriggerText
                })
            }
        }
    }

    if ($Spec.components -and $Spec.components.parameters) {
        foreach ($paramName in $Spec.components.parameters.PSObject.Properties.Name) {
            $paramNode = $Spec.components.parameters.$paramName
            if ($paramNode.PSObject.Properties.Name -notcontains 'description') { continue }

            $trigger = Get-PfbValueEnumTriggerSentence -Description $paramNode.description
            if (-not $trigger) { continue }

            $wireName = if ($paramNode.PSObject.Properties.Name -contains 'name' -and $paramNode.name) { $paramNode.name } else { $paramName }

            $parsed = ConvertFrom-PfbValueEnumProse -TriggerSentence $trigger
            $results.Add([PSCustomObject]@{
                Key         = $paramName
                Kind        = 'parameter'
                Name        = $wireName
                Values      = $parsed.Values
                Parsed      = $parsed.Parsed
                TriggerText = $parsed.TriggerText
            })
        }
    }

    if ($Spec.paths) {
        foreach ($pathKey in $Spec.paths.PSObject.Properties.Name) {
            $pathItem = $Spec.paths.$pathKey
            # Strip the version prefix every real path carries (e.g.
            # "/api/2.27/arrays/space") down to the version-stable form
            # ("arrays/space") that also matches the literal -Endpoint string every
            # cmdlet passes to Invoke-PfbApiRequest (see PfbCmdletParamTools.ps1) -- the
            # same normalized path MUST produce the same Key across every spec version
            # or the introduced-in-version diffing in Build-PfbValueEnumMap.ps1 would
            # never recognize the field as the same one release to release. A handful
            # of paths (e.g. /oauth2/1.0/token) carry no /api/<version>/ prefix at all;
            # for those, only the leading slash is stripped.
            $normalizedPath = ($pathKey -replace '^/api/\d+\.\d+/', '') -replace '^/', ''

            foreach ($methodKey in $pathItem.PSObject.Properties.Name) {
                if ($methodKey -notin @('get', 'put', 'post', 'delete', 'options', 'head', 'patch', 'trace')) { continue }

                $operation = $pathItem.$methodKey
                if (-not $operation -or $operation.PSObject.Properties.Name -notcontains 'parameters' -or -not $operation.parameters) { continue }

                foreach ($paramNode in $operation.parameters) {
                    # A bare $ref pointer, e.g. { "$ref": "#/components/parameters/Type" }
                    # -- already covered by the components.parameters pass above.
                    # Reprocessing it here would double-count the same definition under
                    # two different Keys and inflate entryCount without adding real
                    # coverage.
                    if ($paramNode.PSObject.Properties.Name -contains '$ref') { continue }

                    if ($paramNode.PSObject.Properties.Name -notcontains 'description' -or -not $paramNode.description) { continue }
                    if ($paramNode.PSObject.Properties.Name -notcontains 'name' -or -not $paramNode.name) { continue }
                    if ($paramNode.PSObject.Properties.Name -notcontains 'in') { continue }

                    $trigger = Get-PfbValueEnumTriggerSentence -Description $paramNode.description
                    if (-not $trigger) { continue }

                    $methodUpper = $methodKey.ToUpperInvariant()
                    $wireName = $paramNode.name
                    $key = "$methodUpper $normalizedPath#$wireName"

                    $parsed = ConvertFrom-PfbValueEnumProse -TriggerSentence $trigger
                    $results.Add([PSCustomObject]@{
                        Key         = $key
                        Kind        = 'inline-parameter'
                        Name        = $wireName
                        Values      = $parsed.Values
                        Parsed      = $parsed.Parsed
                        TriggerText = $parsed.TriggerText
                    })
                }
            }
        }
    }

    return $results
}

function Get-PfbResourceHint {
    <#
    .SYNOPSIS
        Strips the leading "<Verb>-Pfb" prefix to derive a resource-name hint, e.g.
        "New-PfbNetworkInterface" -> "NetworkInterface". Matches any verb generically --
        the "-Pfb" module prefix is the reliable marker, not the specific verb.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string]$CmdletName)
    if ($CmdletName -match '^[A-Za-z]+-Pfb(.+)$') {
        return $Matches[1]
    }
    return $CmdletName
}

function Get-PfbValueEnumHistory {
    <#
    .SYNOPSIS
        Re-derives the full per-version value-enum history Resolve-PfbFieldValueEnum
        needs (MinVersion, CurrentValues, DistinctValueSets -- i.e. was this field's
        value set ever unstable since first seen) by re-scanning every cached spec
        version directly.
    .DESCRIPTION
        Deliberately NOT sourced from a Reports/PfbValueEnumMap.json-shaped summary --
        that manifest only retains each entry's newest value list and earliest-seen
        version, not per-version stability, which this history structure requires.
        Shared by tools/Build-PfbFieldCmdletMap.ps1 (category 4: new ValidateSet
        candidates) and tools/lib/PfbApiDriftTools.ps1's Get-PfbValidateSetDrift
        (category 3: drift on ValidateSets that already exist) so both use identical
        resolution data derived the same way.
    .OUTPUTS
        [PSCustomObject]@{ History; ProcessedVersions; OldestVersion }. History is an
        [ordered] dictionary keyed by (schema/parameter/inline-parameter) Key (see
        Get-PfbSpecValueEnums), each value [ordered]@{ Name; Kind; MinVersion;
        CurrentValues; DistinctValueSets }, where DistinctValueSets is a
        HashSet[string] of every distinct sorted-and-joined value set ever observed.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string]$SpecsDirectory)

    $specFiles = Get-ChildItem -Path $SpecsDirectory -Filter 'fb*.json' -ErrorAction SilentlyContinue
    if (-not $specFiles) {
        throw "No cached specs found in '$SpecsDirectory'. Run Update-PfbApiSpecs.ps1 first."
    }
    $specFiles = $specFiles | ForEach-Object {
        if ($_.BaseName -match '^fb(\d+)\.(\d+)$') {
            [PSCustomObject]@{ File = $_; Major = [int]$Matches[1]; Minor = [int]$Matches[2] }
        }
    } | Where-Object { $_ } | Sort-Object Major, Minor

    $history = [ordered]@{}
    $processedVersions = [System.Collections.Generic.List[string]]::new()
    $oldestVersion = "$($specFiles[0].Major).$($specFiles[0].Minor)"

    foreach ($entry in $specFiles) {
        $version = "$($entry.Major).$($entry.Minor)"
        $spec = Get-Content -Path $entry.File.FullName -Raw | ConvertFrom-Json -Depth 64
        $valueEnums = Get-PfbSpecValueEnums -Spec $spec

        foreach ($rec in $valueEnums) {
            if (-not $rec.Parsed) { continue }
            $sortedValues = ($rec.Values | Sort-Object) -join ','

            if (-not $history.Contains($rec.Key)) {
                $history[$rec.Key] = [ordered]@{
                    Name              = $rec.Name
                    Kind              = $rec.Kind
                    MinVersion        = $version
                    CurrentValues     = $rec.Values
                    DistinctValueSets = [System.Collections.Generic.HashSet[string]]::new()
                }
            }
            $history[$rec.Key].CurrentValues = $rec.Values
            [void]$history[$rec.Key].DistinctValueSets.Add($sortedValues)
        }

        $processedVersions.Add($version)
    }

    return [PSCustomObject]@{
        History           = $history
        ProcessedVersions = $processedVersions
        OldestVersion     = $oldestVersion
    }
}

function Resolve-PfbFieldValueEnum {
    <#
    .SYNOPSIS
        Resolves one candidate field's wire name against a Get-PfbValueEnumHistory
        History using the three-kind resolution rule: schema-kind (resource-hint
        heuristic), parameter-kind (shared-dictionary cross-source agreement), and
        inline-parameter (exact endpoint identity, highest priority -- settles ambiguity
        the other two kinds cannot, e.g. Get-PfbArraySpace -Type's 'Type' vs
        'Type_for_performance' collision). Never guesses: ambiguous cases return
        'collision', never a forced pick.
    .OUTPUTS
        [PSCustomObject]@{ Status; MatchedKey; SpecValues; Stable; Recommendation }.
        Status is one of 'no-spec-enum-found', 'collision', 'not-found-in-resource',
        'matched'. MatchedKey/SpecValues/Stable/Recommendation are all $null unless
        Status -eq 'matched', in which case Recommendation is 'ValidateSet' (stable
        since the oldest processed version) or 'ArgumentCompleter' (introduced later, or
        its value set has changed at some point in the observed history).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$WireName,
        [Parameter(Mandatory)] [string]$ResourceHint,
        [string]$Endpoint,
        [string]$Method,
        [Parameter(Mandatory)] $History,
        [Parameter(Mandatory)] [string]$OldestVersion
    )

    $allMatches = @($History.Keys | Where-Object { $History[$_].Name -eq $WireName })
    $schemaMatches = @($allMatches | Where-Object { $History[$_].Kind -eq 'schema' })
    $paramMatches  = @($allMatches | Where-Object { $History[$_].Kind -eq 'parameter' })
    $hintedSchema  = @($schemaMatches | Where-Object { $_ -like "$ResourceHint*" })

    $inlineKey = if ($Endpoint -and $Method) { "$($Method.ToUpperInvariant()) $Endpoint#$WireName" } else { $null }
    $inlineMatches = @()
    if ($inlineKey -and $History.Contains($inlineKey) -and $History[$inlineKey].Kind -eq 'inline-parameter') {
        $inlineMatches = @($inlineKey)
    }

    if ($allMatches.Count -eq 0) {
        return [PSCustomObject]@{ Status = 'no-spec-enum-found'; MatchedKey = $null; SpecValues = $null; Stable = $null; Recommendation = $null }
    }

    $paramValueSets = @($paramMatches | ForEach-Object { ($History[$_].CurrentValues | Sort-Object) -join ',' } | Select-Object -Unique)
    $paramAmbiguous = ($paramMatches.Count -gt 0) -and (@($paramValueSets).Count -gt 1)
    $paramCandidates = if ($paramMatches.Count -eq 0 -or $paramAmbiguous) { @() } else { @($paramMatches[0]) }

    $resolved = @($inlineMatches + $hintedSchema + $paramCandidates)
    $resolvedValueSets = @($resolved | ForEach-Object { ($History[$_].CurrentValues | Sort-Object) -join ',' } | Select-Object -Unique)

    $forceCollisionFromParamAmbiguity = ($inlineMatches.Count -eq 0) -and $paramAmbiguous

    if ($forceCollisionFromParamAmbiguity -or @($resolvedValueSets).Count -gt 1) {
        return [PSCustomObject]@{ Status = 'collision'; MatchedKey = $null; SpecValues = $null; Stable = $null; Recommendation = $null }
    }
    if ($resolved.Count -eq 0) {
        return [PSCustomObject]@{ Status = 'not-found-in-resource'; MatchedKey = $null; SpecValues = $null; Stable = $null; Recommendation = $null }
    }

    $matchedKey = $resolved[0]
    $h = $History[$matchedKey]
    $specValues = $h.CurrentValues
    $stable = ($h.MinVersion -eq $OldestVersion) -and ($h.DistinctValueSets.Count -eq 1)
    return [PSCustomObject]@{
        Status         = 'matched'
        MatchedKey     = $matchedKey
        SpecValues     = $specValues
        Stable         = $stable
        Recommendation = if ($stable) { 'ValidateSet' } else { 'ArgumentCompleter' }
    }
}
