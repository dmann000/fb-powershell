#Requires -Version 7.0
<#
.SYNOPSIS
    Builds the committed report of cmdlet query keys that their endpoint does not declare.
.DESCRIPTION
    Compares the AST-based cmdlet parameter inventory with the query parameters declared by
    the pinned REST API spec. A dead key is silently discarded by the array, so a GET can return
    an unfiltered collection and a write can arrive without its selector. This script reports the
    finding without modifying any Public/ cmdlet.
.PARAMETER SpecsDirectory
    Where cached spec JSON files live. Defaults to tools/specs relative to this script.
.PARAMETER PublicDirectory
    Where Public/ cmdlet files live. Defaults to Public/ relative to the repo root.
.PARAMETER CapabilityMapPath
    Path to the capability-map JSON. Defaults to Data/PfbCapabilityMap.json.
.PARAMETER OutputPath
    Where to write Reports/PfbDeadKeyReport.json. Defaults there.
#>
[CmdletBinding()]
param(
    [string]$SpecsDirectory,
    [string]$PublicDirectory,
    [string]$CapabilityMapPath,
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

$scriptDir = $PSScriptRoot
. (Join-Path $scriptDir 'lib/PfbSpecTools.ps1')
. (Join-Path $scriptDir 'lib/PfbCmdletParamTools.ps1')

$repoRoot = Split-Path -Parent $scriptDir
if (-not $SpecsDirectory)    { $SpecsDirectory = Join-Path $scriptDir 'specs' }
if (-not $PublicDirectory)   { $PublicDirectory = Join-Path $repoRoot 'Public' }
if (-not $CapabilityMapPath) { $CapabilityMapPath = Join-Path (Join-Path $repoRoot 'Data') 'PfbCapabilityMap.json' }
if (-not $OutputPath)        { $OutputPath = Join-Path (Join-Path $repoRoot 'Reports') 'PfbDeadKeyReport.json' }

if (-not (Test-Path -LiteralPath $CapabilityMapPath)) {
    throw "Capability map not found at '$CapabilityMapPath'. Run Build-PfbCapabilityMap.ps1 first."
}

$capabilityMap = Get-Content -LiteralPath $CapabilityMapPath -Raw | ConvertFrom-Json -Depth 20
$specVersion = $capabilityMap.generatedFrom | Select-Object -Last 1
if (-not $specVersion) {
    throw "Capability map at '$CapabilityMapPath' has no generatedFrom versions."
}

$specPath = Join-Path $SpecsDirectory "fb$specVersion.json"
if (-not (Test-Path -LiteralPath $specPath)) {
    throw "Pinned analysed spec 'fb$specVersion.json' (per capability map's generatedFrom) not found under '$SpecsDirectory'. Run Update-PfbApiSpecs.ps1 first, or rebuild the capability map against the specs on disk."
}

$spec = Get-Content -LiteralPath $specPath -Raw | ConvertFrom-Json -Depth 64
$inventory = @(Get-PfbCmdletParameterInventory -PublicDirectory $PublicDirectory)

# Task 4 mirrors this exact helper verbatim. It sorts records, not a joined key, using an
# explicit ordinal comparison over the named properties supplied by -Property. Ordinal is
# stable between PS7 and Windows PowerShell 5.1; Sort-Object -Culture '' is invariant
# linguistic and is not. Each collection passes only properties that exist in its emitted
# artifact: deadKeys uses Cmdlet then Parameter, while noSurvivingSelector uses Cmdlet then
# Method then Endpoint.
#
# THE SORT IS UNSTABLE, and that is safe only because the sort keys are currently unique.
# List<T>.Sort with a [System.Comparison[object]] is an introsort: it gives no guarantee about
# the relative order of records whose comparison returns 0. There are 0 duplicate sort keys in
# the committed artifact today -- (Cmdlet, Parameter) is unique across deadKeys and
# (Cmdlet, Method, Endpoint) is unique across noSurvivingSelector -- so the output is
# deterministic and the byte-identity results in Tests/Build-PfbDeadKeyReport.Tests.ps1 are
# real. A future spec that introduces even ONE tie would make byte-identity depend on .NET's
# introsort partitioning, and that file's first-difference assertion would then red
# intermittently and differently across platforms and runtime versions.
# THE FIX, if that day comes: make the order TOTAL by adding a final tie-break property to each
# -Property list (WireKey for deadKeys is enough today), here and in the mirrored comparer in
# Tests/CommittedDeadKeyReport.Tests.ps1. Do not reach for a "stable sort" instead -- a total
# order is what makes the artifact reproducible.
function Sort-PfbDeadKeyRecords {
    param(
        [AllowEmptyCollection()]
        [object[]]$Records,

        [Parameter(Mandatory)]
        [string[]]$Property
    )

    $sorted = [System.Collections.Generic.List[object]]::new()
    foreach ($record in $Records) { $sorted.Add($record) }
    $sorted.Sort([System.Comparison[object]]{
        param($left, $right)
        foreach ($propertyName in $Property) {
            $comparison = [string]::Compare(
                [string]$left.$propertyName,
                [string]$right.$propertyName,
                [System.StringComparison]::Ordinal)
            if ($comparison -ne 0) { return $comparison }
        }
        return 0
    })
    return @($sorted)
}

function Test-PfbDeadKeySelectorName {
    param(
        [Parameter(Mandatory)]
        [string]$WireName
    )

    # Exact anchors are intentional. In particular, do not use a suffix regex that would
    # classify usernames, grids, ids_or_names, or context_names as selectors.
    #
    # This is NOT the empty-pipeline selector policy, and the two deliberately differ (#126).
    # They differ in KIND, not in a handful of keys. This function is an ALLOWLIST of identity
    # shapes; Private/PfbSelectorPolicyConstants.ps1 is a DENYLIST of twelve scope keys where
    # anything unlisted reads as a selector. They therefore disagree on AT LEAST every key that is
    # neither identity-shaped nor denylisted. Do not describe the divergence as narrow.
    #
    # Where it can actually BITE is far smaller, and worth stating exactly rather than by
    # proportion: the only key both classifiers see and disagree about is 'filter'. This function
    # calls it not-a-selector; the runtime calls it a selector, deliberately, because it is the
    # module's one caller-authored predicate. Each is right for its own purpose. Of the 130 cmdlets
    # carrying an empty-pipeline guard, 124 can put that key in a query -- the ones declaring
    # -Filter, which always reaches the query through Add-PfbCommonQueryParams' ContainsKey gate
    # rather than as a literal write.
    #
    # That set cannot grow unnoticed: a divergent key is by definition neither denylisted nor
    # identity-shaped, and Tests/PfbSelectorPolicyCompleteness.Tests.ps1 reds the build when a
    # guarded cmdlet writes exactly such a key. The COUNT will move as cmdlets are added; the SET
    # will not change silently.
    #
    # By contrast the two keys this function excludes BY NAME -- context_names and ids_or_names --
    # cannot reach the runtime policy at all: context_names is injected into a CLONE inside
    # Invoke-PfbApiRequest after the guard has run, and ids_or_names is never written as a query
    # key in Public/. An explicit exclusion here is therefore not evidence of a runtime divergence.
    #
    # Note also where the two AGREE, because the shape of this function invites the opposite
    # assumption: singular name/id are absent from the denylist too, so the runtime reads them as
    # selectors exactly as the first line here does. The classifier that genuinely rejects the
    # singular forms is neither of these -- it is Test-PfbIdentityShapedKey in
    # Tests/PfbSelectorPolicyCompleteness.Tests.ps1, which matches @('names', 'ids') exactly.
    #
    # The divergence is intended because the failure directions are opposite. A report that
    # misclassifies produces a wrong ROW; the runtime policy DISCARDS A REQUEST. Reconcile them
    # only with a reason that survives that asymmetry -- do not "fix" one to match the other.
    if ($WireName -in @('names', 'ids', 'name', 'id')) { return $true }
    if ($WireName -in @('context_names', 'ids_or_names')) { return $false }
    return $WireName.EndsWith('_names', [System.StringComparison]::Ordinal) -or
        $WireName.EndsWith('_ids', [System.StringComparison]::Ordinal)
}

function Get-PfbDeadKeySeverity {
    param(
        [Parameter(Mandatory)]
        [string]$Method
    )

    switch ($Method.ToUpperInvariant()) {
        'DELETE' { return 'DESTRUCTIVE' }
        'PATCH'  { return 'DESTRUCTIVE' }
        'PUT'    { return 'DESTRUCTIVE' }
        'POST'   { return 'CREATE' }
        'GET'    { return 'WRONG-RESULTS' }
        default  { throw "Unsupported HTTP method '$Method' while classifying a dead key." }
    }
}

function Get-PfbDeadKeyDeclarationIndex {
    <#
    .SYNOPSIS
        One record per (method, normalized endpoint) carrying every query key and every
        top-level body property that operation declares. Built ONCE per generator run.
    .DESCRIPTION
        This index exists only to EXPLAIN a deadness that Get-PfbDeclaredQueryKey has already
        proven. It never decides whether a record is dead.

        BUILT ON Get-PfbSpecCapabilities RATHER THAN A BESPOKE WALK, deliberately, for three
        measured reasons -- all three are ways a hand-rolled body read returns a plausible ZERO:

          1. It derives BodyProperties through Get-PfbSchemaPropertyNames, which resolves
             $ref AND allOf. PATCH /alerts' body schema is a bare `$ref`; resolving that ONE
             level lands on a node whose only key is `allOf`, so a reader that then takes
             `.properties` gets an EMPTY LIST -- measured against fb2.28. Alert.flagged is
             reachable no other way, so such a reader classifies Get-PfbAlert -Flagged as
             UNDECLARED: a confident false assertion published under a field name that reads
             as authoritative. The walker returns all 18 properties including `flagged`.
          2. It hops a `type: array` request body onto its `items` element schema (issue #82).
             A bespoke `Get-PfbSchemaPropertyNames -Schema $op.requestBody.content.<type>.schema`
             call has nothing to descend for an array body and silently records zero body
             properties. RESIDUAL, stated because it is a real loss of precision and not a
             bug: a Body site found inside an array ELEMENT reads identically to a top-level
             one, so `declaredElsewhere` cannot tell "the field belongs on each element of the
             posted array" from "the field belongs on the body object". It is the right trade
             anyway -- omitting the hop manufactures a false UNDECLARED, an assertion of
             absence, which is the worse direction -- and it publishes nothing false today:
             measured on fb2.28, ZERO dead keys fall on an array-bodied operation.
          3. It reads body schemas at MaxDepth 32, not the helpers' own default of 8. Depth 8
             truncates the fb2.12-2.16 allOf chains (issue #71); a bespoke walk would have to
             re-decide that value, and the cheap wrong answer is to accept the default. Note
             that 32 is INHERITED, not pinned here: the call below passes no -MaxDepth, so the
             value comes from Get-PfbSpecCapabilities' own default (tools/lib/PfbSpecTools.ps1).
             Lowering that default would silently lower this report's depth too.

        WHAT IT DELIBERATELY DOES *NOT* TAKE FROM THAT FUNCTION IS `Parameters`. That field is
        every parameter regardless of `in:` location, not the query ones. Measured on fb2.28:
        630 header-parameter occurrences (`api-token`, `X-Request-ID`) across 629 of the 632
        operations. Using it as the query-declaration set would inject two header names into
        almost every operation's declarations and could report a genuinely dead key as
        WRONG-VERB. Query keys come from Get-PfbDeclaredQueryKey instead -- the SAME function
        that gates deadness -- so the classification's notion of "declared as a query key" is
        identical to the gate's by construction and the two can never contradict each other.

        WHY A NULL FROM THAT HELPER SKIPS THE OPERATION, AND WHY THAT LOSES NOTHING. It returns
        $null for "this path/verb is not in the spec", which here means only that the
        capability record's normalized path is one of the five UNVERSIONED meta paths
        (/api/login, /api/logout, /api/api_version, /api/login-banner, /oauth2/1.0/token):
        normalizing strips no prefix from them, so re-adding /api/<version>/ misses. Measured
        on fb2.28: exactly those 5 of 632 records, and every versioned path round-trips. No
        record can reach classification through such an endpoint, because the deadness gate
        below has already called this same helper on the record's own endpoint and required a
        non-$null answer -- which proves /api/<version>/<endpoint> is a real path key, and a
        path key carries all of its own verbs. So the index is complete for every endpoint that
        can reach it. Skipping is not a silent gap; it is the honest alternative to recording an
        operation whose query declarations this generator cannot read.

        CASE-INSENSITIVE (Ordinal-ignore-case) SETS on purpose. The deadness gate is
        `@($declared) -contains $wireName`, and PowerShell's -contains is case-INSENSITIVE. An
        ordinal-exact index here would be STRICTER than the gate it explains, so a key the gate
        would have called declared could be reported UNDECLARED. Every key on this surface is
        lower-case snake_case today, so this changes no current row -- it removes a way for the
        explanation to disagree with the finding.
    #>
    param(
        [Parameter(Mandatory)] $Spec,
        [Parameter(Mandatory)] [string]$Version
    )

    $index = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[object]]]::new(
        [System.StringComparer]::OrdinalIgnoreCase)

    foreach ($capability in @(Get-PfbSpecCapabilities -Spec $Spec)) {
        $endpointKey = ([string]$capability.Path).TrimStart('/')
        $method = ([string]$capability.Method).ToUpperInvariant()

        $queryKeys = Get-PfbDeclaredQueryKey -Spec $Spec -Endpoint $endpointKey -Method $method -Version $Version
        if ($null -eq $queryKeys) { continue }

        if (-not $index.ContainsKey($endpointKey)) {
            $index[$endpointKey] = [System.Collections.Generic.List[object]]::new()
        }
        $index[$endpointKey].Add([PSCustomObject]@{
            Method    = $method
            QueryKeys = [System.Collections.Generic.HashSet[string]]::new(
                [string[]]@($queryKeys), [System.StringComparer]::OrdinalIgnoreCase)
            BodyKeys  = [System.Collections.Generic.HashSet[string]]::new(
                [string[]]@($capability.BodyProperties), [System.StringComparer]::OrdinalIgnoreCase)
        })
    }

    return $index
}

function Get-PfbDeadKeyDeclarationSite {
    <#
    .SYNOPSIS
        Every (method, surface) pair on the SAME normalized endpoint that declares $WireKey.
    .DESCRIPTION
        Returns an empty list when nothing on the endpoint declares the key -- which is the
        positive assertion behind UNDECLARED, and is the reason the index above is built with
        the repo's real schema walker rather than a one-level read.

        Only the endpoint the record itself resolved to is consulted. A similarly named
        endpoint is not a declaration, and neither is an older spec version: the caller passes
        the one pinned spec.
    #>
    param(
        [Parameter(Mandatory)] $DeclarationIndex,
        [Parameter(Mandatory)] [string]$Endpoint,
        [Parameter(Mandatory)] [string]$WireKey
    )

    $sites = [System.Collections.Generic.List[object]]::new()
    $endpointKey = $Endpoint.TrimStart('/')
    if (-not $DeclarationIndex.ContainsKey($endpointKey)) { return $sites }

    foreach ($operation in $DeclarationIndex[$endpointKey]) {
        if ($operation.BodyKeys.Contains($WireKey)) {
            $sites.Add([PSCustomObject]@{ Method = $operation.Method; Surface = 'Body' })
        }
        if ($operation.QueryKeys.Contains($WireKey)) {
            $sites.Add([PSCustomObject]@{ Method = $operation.Method; Surface = 'Query' })
        }
    }

    return $sites
}

function Get-PfbDeadKeyClassification {
    <#
    .SYNOPSIS
        WRONG-SURFACE, WRONG-VERB or UNDECLARED for a key already proven dead on $Method.
    .DESCRIPTION
        Priority is diagnostic, not arithmetic: a body declaration anywhere on the endpoint is
        the most actionable finding (the field exists, the cmdlet is sending it on the wrong
        surface), so it outranks a query declaration on another verb. Only when NEITHER exists
        is UNDECLARED emitted, and UNDECLARED is a POSITIVE ASSERTION that no operation on the
        endpoint declares the key on either surface -- see the index's help for why that
        assertion is only safe with a $ref/allOf-aware body reader.

        THE `$_.Method -ne $Method` COMPONENT IS PROVABLY REDUNDANT TODAY, and is kept as a
        statement of intent rather than as a working guard. A Query site on the CURRENT method
        cannot exist: the index's query keys come from Get-PfbDeclaredQueryKey with the same
        endpoint, the same method and the same case-insensitive membership test that just
        declared this key dead. Do not read a surviving mutant of that comparison as a missing
        test -- it is an equivalent mutant. The ARM itself is live and tested: replacing the
        whole condition with $false reds the WRONG-VERB fixture.
    #>
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$DeclarationSite,

        [Parameter(Mandatory)] [string]$Method
    )

    if (@($DeclarationSite | Where-Object { $_.Surface -eq 'Body' }).Count -gt 0) {
        return 'WRONG-SURFACE'
    }
    if (@($DeclarationSite | Where-Object { $_.Surface -eq 'Query' -and $_.Method -ne $Method }).Count -gt 0) {
        return 'WRONG-VERB'
    }
    return 'UNDECLARED'
}

# ORDER IS PART OF THE ARTIFACT: this is an [ordered] dictionary serialized verbatim into
# counts.skipReasons, so inserting a key rewrites the JSON. The two issue #141 Task 4 states
# sit immediately after 'wire name unresolved' because that is the bucket they were being
# absorbed into before they existed, and reading them adjacent to it is how a maintainer sees
# the reclassification rather than a count that merely fell.
#
# THE FOUR OLD KEYS ARE ADMISSIONS OF IGNORANCE; THE TWO NEW ONES ARE ANSWERS. 'wire name
# unresolved' means this AST resolver could not find a key that may well exist. 'outside
# standard request' means the declaring function issues no Invoke-PfbApiRequest call at all,
# and 'not wire parameter' means an audited request control with no query/body key. Neither
# says anything about bespoke HTTP: Connect-PfbArray's -Username/-Password are 'outside
# standard request' AND reach the wire, in a login body posted through Invoke-WebRequest.
# Do not retitle these buckets as "not a wire field".
$skipReasons = [ordered]@{
    'wire name unresolved'          = 0
    'outside standard request'      = 0
    'not wire parameter'            = 0
    'body property'                 = 0
    'endpoint/method ambiguous'     = 0
    'endpoint/verb absent from spec' = 0
}
$declarationIndex = Get-PfbDeadKeyDeclarationIndex -Spec $spec -Version $specVersion
$deadKeyRecords = [System.Collections.Generic.List[object]]::new()
$evaluatedRecords = [System.Collections.Generic.List[object]]::new()

foreach ($record in $inventory) {
    # BEFORE the null-WireName test, not after, and that ordering is the whole point of these
    # two branches. Both Surface values carry WireName = $null BY CONSTRUCTION -- the
    # inventory's Surface ladder tests `if ($wireName) { 'Typed' }` first, so it cannot reach
    # either value with a resolved name -- so a null-WireName test placed first swallows every
    # one of them into 'wire name unresolved' and the reclassification produces no visible
    # movement at all. Tested by fixture in both directions: each state increments only its own
    # bucket, and 'wire name unresolved' keeps its own genuinely-unresolved rows.
    if ($record.Surface -eq 'OutsideStandardRequest') {
        $skipReasons['outside standard request']++
        continue
    }
    if ($record.Surface -eq 'NotWireParameter') {
        $skipReasons['not wire parameter']++
        continue
    }
    if ($null -eq $record.WireName) {
        $skipReasons['wire name unresolved']++
        continue
    }
    if ($record.WireSurface -eq 'Body') {
        $skipReasons['body property']++
        continue
    }
    if ([string]::IsNullOrEmpty([string]$record.Endpoint) -or
        [string]::IsNullOrEmpty([string]$record.Method)) {
        $skipReasons['endpoint/method ambiguous']++
        continue
    }

    $declared = Get-PfbDeclaredQueryKey -Spec $spec -Endpoint $record.Endpoint -Method $record.Method -Version $specVersion
    if ($null -eq $declared) {
        $skipReasons['endpoint/verb absent from spec']++
        continue
    }

    $method = ([string]$record.Method).ToUpperInvariant()
    $wireName = [string]$record.WireName
    $status = if (@($declared) -contains $wireName) { 'OK' } else { 'DEAD KEY' }
    $evaluated = [PSCustomObject]@{
        Cmdlet        = $record.Cmdlet
        Parameter     = $record.Parameter
        WireName      = $wireName
        Method        = $method
        Endpoint      = $record.Endpoint
        Status        = $status
        SelectorShaped = Test-PfbDeadKeySelectorName -WireName $wireName
    }
    $evaluatedRecords.Add($evaluated)

    if ($status -eq 'OK') {
        continue
    }

    # Classification is strictly ADDITIVE to the finding above: $status decided deadness from
    # the current operation's own query declarations, and nothing below can change it. If a
    # change here moves which records are dead, it has exceeded its remit.
    $declarationSites = Get-PfbDeadKeyDeclarationSite -DeclarationIndex $declarationIndex `
        -Endpoint ([string]$record.Endpoint) -WireKey $wireName
    $classification = Get-PfbDeadKeyClassification -DeclarationSite @($declarationSites) -Method $method

    # Deduplicate, and NOT for the reason the top-level sorts carry. The introsort-stability
    # argument documented at the head of Sort-PfbDeadKeyRecords does NOT apply here: a site
    # object holds only Method and Surface and the projection below emits only those two, so a
    # tie on both sort keys is a tie on the ENTIRE serialised record and an unstable sort cannot
    # move a byte among byte-identical elements. Measured: with this dedup removed and a
    # duplicate planted, the two entries serialise to one distinct string.
    #
    # What the dedup actually prevents is a WRONG ROW -- `declaredElsewhere: [DELETE/Query,
    # DELETE/Query]`, published in a committed artifact, asserting two declaration sites where
    # the spec has one. Tests/Build-PfbDeadKeyReport.Tests.ps1:247-249 asserts exactly that
    # ("has a duplicated declaredElsewhere entry") and is the pointer to follow on a red here.
    # Do NOT reach for the "add a final tie-break property" remedy at the head of
    # Sort-PfbDeadKeyRecords: a tie-break makes the order total and still publishes both rows.
    #
    # A duplicate pair is not produced by any spec we pin -- measured on fb2.28: 0 duplicate
    # (Path, Method) groups across 264 normalized paths, exact-case and case-insensitive -- but
    # the claim stops there, and deliberately: the index build adds one entry per capability
    # record with no per-method collapse, so any spec whose version-prefixed path keys normalize
    # NON-INJECTIVELY onto one endpoint reaches this loop with the same (Method, Surface) twice.
    # One operation can also legitimately declare the same key on both surfaces, which is why
    # Surface is a sort key and not only a label.
    $seenSites = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $uniqueSites = [System.Collections.Generic.List[object]]::new()
    foreach ($site in $declarationSites) {
        if ($seenSites.Add(('{0}|{1}' -f $site.Method, $site.Surface))) { $uniqueSites.Add($site) }
    }

    $deadKeyRecords.Add([PSCustomObject]@{
        Cmdlet            = $record.Cmdlet
        Parameter         = $record.Parameter
        Severity          = Get-PfbDeadKeySeverity -Method $method
        WireKey           = $wireName
        Method            = $method
        Endpoint          = $record.Endpoint
        Declared          = @($declared)
        Classification    = $classification
        DeclaredElsewhere = @(Sort-PfbDeadKeyRecords -Records @($uniqueSites) -Property @('Method', 'Surface'))
    })
}

# A skipped selector is unevaluable, not evidence that every selector is dead. Group all
# inventory records by operation, then emit only when the group has at least one selector,
# no selector was skipped for any reason, and every evaluated selector is a DEAD KEY.
#
# Two limits on that "for any reason", stated because the guarantee is narrower than the
# sentence above reads and both were measured rather than assumed:
#
#   1. The rule is OPERATION-scoped, not cmdlet-scoped. Group identity is
#      (Cmdlet, Method, Endpoint), and a selector skipped as `endpoint/method ambiguous`
#      carries a null Method/Endpoint -- so it forms its own null-keyed group and cannot
#      suppress the same cmdlet's real group. 10 such records exist today (across
#      Get-PfbNode, Remove-PfbBucket, Remove-PfbFileSystem, Remove-PfbFileSystemSnapshot,
#      Remove-PfbRealm); for all five the ambiguity affects EVERY selector the cmdlet has,
#      so no evaluated-and-dead selector survives to form a group anyway. The gap needs a
#      cmdlet with some selectors resolved-and-dead and others ambiguous, which does not
#      exist in the current inventory.
#   2. An unresolvable wire name is invisible to the rule -- the `continue` below drops it
#      before the shape test, because the shape of a name that could not be resolved is
#      unknowable. So this really means "no IDENTIFIABLE selector was skipped", and the 125
#      `wire name unresolved` records fall outside it.
#
# Consequence of the rule as written, deliberate rather than overlooked: the 22 body-surface
# selector-shaped records are all Update-Pfb* PATCH parameters (NewName -> name, plus
# ServicePrincipalNames and SubjectAlternativeNames). A request-body `name` can never act as
# a query selector, yet its presence suppresses its operation's group -- so no Update-Pfb*
# cmdlet carrying a -NewName can appear here regardless of how dead its query selectors are.
# That errs toward under-reporting, which is the safe direction for a report whose entries
# are read as destructive-verb hazards.
#
# ALL THREE NARROWINGS ABOVE ARE SUMMARISED FOR CONSUMERS in Reports/README.md, under the
# noSurvivingSelector field's description, with a pointer back to this comment for the full
# account. Keep the two in step: a downstream consumer reading the field as complete would
# build a refusal rail with holes it does not know about. They are deliberately NOT carried as
# a field in the artifact -- that would change its bytes and its schema for a documentation
# problem.
$noSurvivingSelectorRecords = [System.Collections.Generic.List[object]]::new()
$allSelectorRecords = [System.Collections.Generic.List[object]]::new()
foreach ($record in $inventory) {
    if ($null -eq $record.WireName) { continue }
    if (Test-PfbDeadKeySelectorName -WireName ([string]$record.WireName)) {
        $allSelectorRecords.Add([PSCustomObject]@{
            Cmdlet    = $record.Cmdlet
            Parameter = $record.Parameter
            Method    = if ($record.Method) { ([string]$record.Method).ToUpperInvariant() } else { $null }
            Endpoint  = $record.Endpoint
            Evaluated = $false
            Status    = $null
        })
    }
}
foreach ($evaluated in $evaluatedRecords | Where-Object SelectorShaped) {
    $match = $allSelectorRecords | Where-Object {
        $_.Cmdlet -eq $evaluated.Cmdlet -and $_.Parameter -eq $evaluated.Parameter -and
        $_.Method -eq $evaluated.Method -and $_.Endpoint -eq $evaluated.Endpoint
    } | Select-Object -First 1
    if ($match) {
        $match.Evaluated = $true
        $match.Status = $evaluated.Status
    }
}
$selectorGroups = @($allSelectorRecords | Group-Object Cmdlet, Method, Endpoint)
foreach ($group in $selectorGroups) {
    $selectors = @($group.Group)
    if ($selectors.Count -gt 0 -and
        @($selectors | Where-Object { -not $_.Evaluated }).Count -eq 0 -and
        @($selectors | Where-Object { $_.Status -ne 'DEAD KEY' }).Count -eq 0) {
        $first = $selectors | Select-Object -First 1
        $noSurvivingSelectorRecords.Add([PSCustomObject]@{
            Cmdlet   = $first.Cmdlet
            Method   = $first.Method
            Endpoint = $first.Endpoint
        })
    }
}

$sortedDeadKeys = @(Sort-PfbDeadKeyRecords -Records @($deadKeyRecords) -Property @('Cmdlet', 'Parameter') |
    ForEach-Object {
        [ordered]@{
            severity  = $_.Severity
            cmdlet    = $_.Cmdlet
            parameter = $_.Parameter
            wireKey   = $_.WireKey
            method    = $_.Method
            endpoint  = $_.Endpoint
            declared  = @($_.Declared)
            # `declared` above stays exactly what it has always been -- the CURRENT
            # operation's query-key list. These two are appended so no consumer keyed on
            # field order or on the old names moves.
            classification    = $_.Classification
            # ALWAYS an array, EMPTY for UNDECLARED, never $null: a consumer reading null
            # cannot tell "no declaration anywhere" from "this generator did not look".
            declaredElsewhere = @(@($_.DeclaredElsewhere) | ForEach-Object {
                [ordered]@{
                    method  = $_.Method
                    surface = $_.Surface
                }
            })
        }
    })
$sortedNoSurvivingSelector = @(Sort-PfbDeadKeyRecords -Records @($noSurvivingSelectorRecords) -Property @('Cmdlet', 'Method', 'Endpoint') |
    ForEach-Object {
        [ordered]@{
            cmdlet   = $_.Cmdlet
            method   = $_.Method
            endpoint = $_.Endpoint
        }
    })

$manifest = [ordered]@{
    specVersion = [string]$specVersion
    counts      = [ordered]@{
        parametersInventoried = $inventory.Count
        keysEvaluated         = $evaluatedRecords.Count
        ok                    = $evaluatedRecords.Count - $deadKeyRecords.Count
        deadKey               = $deadKeyRecords.Count
        skipReasons           = $skipReasons
    }
    deadKeys = $sortedDeadKeys
    noSurvivingSelector = $sortedNoSurvivingSelector
}

$outputDir = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}
$manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
Write-Host "Wrote $($deadKeyRecords.Count) dead keys from $($inventory.Count) inventoried parameters to $OutputPath" -ForegroundColor Green
