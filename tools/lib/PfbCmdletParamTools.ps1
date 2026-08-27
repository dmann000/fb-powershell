<#
.SYNOPSIS
    AST-based inventory of every typed parameter across Public/**/*.ps1, with best-effort
    resolution of each parameter's REST "wire name" (the request-body or query-string key
    it's assigned to). Dot-sourced by tools/Build-PfbFieldCmdletMap.ps1 and its Pester
    tests, parallel to tools/lib/PfbSpecTools.ps1 and tools/lib/PfbValueEnumTools.ps1.

.DESCRIPTION
    Every cmdlet in this module follows one of a small number of body-construction
    patterns (confirmed by direct inspection of New-PfbAlertWatcher, Get-PfbArrayPerformance,
    New-PfbBucket, New-PfbNetworkInterface, New-PfbFileSystem, Update-PfbFileSystem):

        if ($Param) { $body['wire_name'] = $Param }
        if ($Param) { $body['wire_name'] = @($Param) }         # array parameters
        if ($queryParams.ContainsKey(...)) ...                  # not matched, no enum data anyway
        $queryParams['wire_name'] = $Param
        $queryParams = @{ 'wire_name' = $Param }               # hashtable-literal initializer
        $body['wire_name'] = @{ name = $Param }                # nested single-key reference
                                                               # object -- OUTER key wins

    ...plus one indirect pattern, where a shared private helper does the assignment for the
    cmdlet and the cmdlet body therefore contains no literal key at all:

        Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters `
            -Names $allNames -Ids $allIds

    That helper (Private/Add-PfbCommonQueryParams.ps1, introduced by issue #32/PR #49 and
    extended across ~196 Get-Pfb* cmdlets by issue #33/PR #51) is mirrored by
    Get-PfbCommonQueryParamMap. Without it, every migrated cmdlet's -Filter/-Sort/-Limit/
    -TotalOnly/-Name/-Id resolved no wire name, which cascaded into
    Get-PfbParameterCoverageGaps (tools/lib/PfbApiDriftTools.ps1) demoting the cmdlet's whole
    endpoint into its notVerified bucket -- i.e. a pure mechanical refactor made hundreds of
    endpoints silently drop out of gap analysis, and the report's headline missing-field
    count fell as if the gaps had been fixed. The hashtable-literal initializer above
    (Get-PfbHashtableLiteralWireNameForParameter) was invisible for the same reason: only the
    IndexExpressionAst form was ever recognized, so ~99 (cmdlet, parameter) pairs across ~82
    mostly-New-Pfb* cmdlets -- New-PfbApiClient's own -Name among them -- were reported as
    AttributesOnly/TypedUnresolved despite demonstrably reaching the wire.

    The nested single-key reference object (Get-PfbNestedReferenceWireNameForParameter) is the
    same class of blindness, one level deeper: the API models "point this resource at that
    one" as `{"account": {"name": "acct1"}}`, and the capability map records TOP-LEVEL body
    properties only -- there is no `account.name` in it -- so the field such a parameter
    covers is the OUTER key. Leaving it unresolved cost 11 (cmdlet, parameter) pairs across 8
    cmdlets, and via the notVerified gate their whole endpoints.

    A parameter is classified into exactly one Surface:
      - 'Typed': a wire name was resolved via a direct (optionally @()-wrapped) assignment.
      - 'AttributesOnly': the cmdlet has an -Attributes hashtable escape hatch and this
        parameter's value is NOT assigned via a simple pattern above (e.g. it's piped
        through ForEach-Object first, like New-PfbNetworkInterface's -AttachedServers) --
        deliberately NOT guessed at, since over-matching here would misattribute a value
        enum to the wrong field.
      - 'TypedUnresolved': no -Attributes escape hatch exists AND no simple assignment was
        found -- surfaced so a human can look, never silently dropped.

    -Array and -Attributes are never returned as inventory records themselves -- they are
    plumbing, not spec-documented fields with values to validate.

    Each 'Typed' record also carries a best-effort Endpoint/Method: the literal
    -Endpoint/-Method arguments of the Invoke-PfbApiRequest call the parameter's
    resolved body/queryParams variable actually feeds, IF every such call in the
    function agrees on exactly one (Method, Endpoint) pair. Left $null (never guessed)
    when the variable feeds zero calls, or more than one distinct pair -- e.g.
    Get-PfbNode's try/catch fallback that reuses the same $queryParams against two
    genuinely different endpoints ('nodes' then 'blades'). This is what lets
    Build-PfbFieldCmdletMap.ps1 resolve an 'inline-parameter'-kind value-enum record
    (see tools/lib/PfbValueEnumTools.ps1), which is keyed by exact endpoint identity,
    against the one specific cmdlet parameter that calls it.
#>

# Deliberately NOT Set-StrictMode -- same reasoning as PfbSpecTools.ps1 / PfbValueEnumTools.ps1.

function Test-PfbAssignmentGuardedBySwitch {
    <#
    .SYNOPSIS
        True if $Assignment is lexically inside an `if ($ParameterName) { ... }` clause
        whose condition is exactly a bare reference to $ParameterName -- the guard shape
        this function's caller requires before trusting a literal string assignment as
        derived from that parameter. The caller's own gate is boolean-like (switch, bool,
        or Nullable[bool]); this function tests only the guard shape and neither knows nor
        cares which of those types the parameter has.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.Ast]$Assignment,

        [Parameter(Mandatory)]
        [string]$ParameterName
    )

    $expectedCondition = '$' + $ParameterName
    $node = $Assignment.Parent
    while ($node) {
        if ($node -is [System.Management.Automation.Language.IfStatementAst]) {
            foreach ($clause in $node.Clauses) {
                if ($clause.Item1.Extent.Text.Trim() -eq $expectedCondition) {
                    $withinBody = $clause.Item2.FindAll({ param($n) $n -eq $Assignment }, $true)
                    if (@($withinBody).Count -gt 0) { return $true }
                }
            }
        }
        $node = $node.Parent
    }
    return $false
}

function Resolve-PfbSingleExpression {
    <#
    .SYNOPSIS
        Unwraps the StatementAst layers PowerShell's parser puts around a single-expression
        right-hand side, returning the innermost ExpressionAst (or the input unchanged when
        it is not that shape).
    .DESCRIPTION
        Both AssignmentStatementAst.Right and a HashtableAst key/value pair's Item2 are typed
        StatementAst, and the parser wraps a bare expression in a CommandExpressionAst --
        sometimes itself inside a single-element PipelineAst -- rather than exposing the
        BinaryExpressionAst/HashtableAst/VariableExpressionAst directly. Casting without
        unwrapping silently yields $null, which reads as "pattern not matched" instead of
        "wrong layer". Both layers are peeled here, in either order, so callers do not each
        re-derive the same lore (previously duplicated inline; see also
        Find-PfbAccumulatorVariable, which peels a loop condition the same way).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.Ast]$Ast
    )

    $node = $Ast
    for ($i = 0; $i -lt 3; $i++) {
        if ($node -is [System.Management.Automation.Language.PipelineAst]) {
            if ($node.PipelineElements.Count -ne 1) { return $node }
            $node = $node.PipelineElements[0]
            continue
        }
        if ($node -is [System.Management.Automation.Language.CommandExpressionAst]) {
            $node = $node.Expression
            continue
        }
        break
    }
    return $node
}

function Test-PfbInvokeHasNoArguments {
    <#
    .SYNOPSIS
        True when an InvokeMemberExpressionAst represents a zero-argument method call.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.InvokeMemberExpressionAst]$Invoke
    )

    # A zero-argument call exposes Arguments as $null, not as an empty collection --
    # and @($null).Count is 1, so the null case must be tested before wrapping.
    if ($null -eq $Invoke.Arguments) { return $true }
    return (@($Invoke.Arguments).Count -eq 0)
}

function Test-PfbWireValueIsParameter {
    <#
    .SYNOPSIS
        True if -ValueAst -- the value half of a wire-key assignment, either
        `$body['k'] = <this>` or the `@{ 'k' = <this> }` literal form -- hands the named
        parameter's own value to the wire in one of the exact shapes this repo uses.
    .DESCRIPTION
        Deliberately shape-exact rather than "mentions the variable anywhere": over-matching
        would misattribute a wire name (and, downstream, a spec value enum) to the wrong
        field. Accepted:
            $Param                  -- direct
            @($Param)               -- array-wrapped
            $Param -join ','        -- joined into a plural query key
            [bool]$Param            -- exact Boolean cast, BOOLEAN-LIKE parameters only
            ([bool]$Param).ToString().ToLower()
                                    -- exact zero-argument method chain rooted at that cast,
                                       BOOLEAN-LIKE parameters only
            'literal'               -- ONLY for a BOOLEAN-LIKE parameter whose mere presence is
                                       keyed to a hardcoded string, and only inside an
                                       `if ($Param)` guard
            if ($Param) { 'a' } else { 'b' }
                                    -- ONLY for a BOOLEAN-LIKE parameter, and only in exactly
                                       that shape: one clause plus an else (no elseif), a
                                       condition that is textually the bare `$Param` or
                                       `-not $Param` and nothing more, and a single constant
                                       statement in each branch. This is how a [Nullable[bool]]
                                       reaches a string-valued query key (real:
                                       New-PfbFileSystemReplicaLink's remote_default_exports,
                                       whose $false must reach the wire, so the assignment is
                                       guarded on $PSBoundParameters.ContainsKey rather than on
                                       truthiness). Boolean-like means [switch], [bool] or
                                       [Nullable[bool]] -- see -IsBooleanLikeParameter, computed
                                       by Get-PfbCmdletParameterInventory from the declared
                                       StaticType. A wider condition or a non-constant branch
                                       means the wire value is derived from something other
                                       than this parameter alone, and stays refused.
        Refused (correctly, per this file's "never guess" contract): anything else, e.g.
        `"$Param"`. Member access, unary expressions and composite operands remain refused:
        each can derive the wire value from a property, operation or additional operand rather
        than from the named parameter alone. The array-projection shape
        `@($Param | ForEach-Object { @{ name = $_ } })`
        is also refused HERE by design -- it is matched by the sibling
        Test-PfbWireValueIsParameterProjection, and only ever from the nested-reference
        resolver, which credits the OUTER key. Matching it in this predicate would let the
        direct resolvers credit the INNER key instead, naming a field that does not exist.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.Ast]$ValueAst,

        [Parameter(Mandatory)]
        [string]$ParameterName,

        [switch]$IsBooleanLikeParameter
    )

    $text = $ValueAst.Extent.Text.Trim()
    $simple = '$' + $ParameterName
    if ($text -eq $simple -or $text -eq ('@(' + $simple + ')')) { return $true }

    $expr = Resolve-PfbSingleExpression -Ast $ValueAst

    $binary = $expr -as [System.Management.Automation.Language.BinaryExpressionAst]
    if ($binary -and $binary.Operator -eq [System.Management.Automation.Language.TokenKind]::Join) {
        $joinLeft = $binary.Left -as [System.Management.Automation.Language.VariableExpressionAst]
        if ($joinLeft -and $joinLeft.VariablePath.UserPath -eq $ParameterName) { return $true }
    }

    if ($IsBooleanLikeParameter) {
        # Exact [bool]$Param, optionally beneath the exact zero-argument
        # `(...).ToString().ToLower()` chain. Walk AST nodes rather than text so member access,
        # unary expressions and composite cast operands cannot be mistaken for the parameter.
        $boolCast = $expr -as [System.Management.Automation.Language.ConvertExpressionAst]
        if (-not $boolCast) {
            $toLower = $expr -as [System.Management.Automation.Language.InvokeMemberExpressionAst]
            if ($toLower -and (Test-PfbInvokeHasNoArguments -Invoke $toLower) -and
                $toLower.Member -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
                $toLower.Member.Value -eq 'ToLower') {
                $toString = $toLower.Expression -as [System.Management.Automation.Language.InvokeMemberExpressionAst]
                if ($toString -and (Test-PfbInvokeHasNoArguments -Invoke $toString) -and
                    $toString.Member -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
                    $toString.Member.Value -eq 'ToString') {
                    $parenthesizedRoot = $toString.Expression -as [System.Management.Automation.Language.ParenExpressionAst]
                    if ($parenthesizedRoot) {
                        $chainRoot = Resolve-PfbSingleExpression -Ast $parenthesizedRoot.Pipeline
                        $boolCast = $chainRoot -as [System.Management.Automation.Language.ConvertExpressionAst]
                    }
                }
            }
        }

        if ($boolCast) {
            $castType = $boolCast.Type.TypeName.GetReflectionType()
            if ($castType -eq [bool]) {
                $castChild = $boolCast.Child -as [System.Management.Automation.Language.VariableExpressionAst]
                if ($castChild -and $castChild.VariablePath.UserPath -eq $ParameterName) { return $true }
            }
        }
    }

    if ($IsBooleanLikeParameter -and $expr -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
        if (Test-PfbAssignmentGuardedBySwitch -Assignment $ValueAst -ParameterName $ParameterName) { return $true }
    }

    # `if ($Param) { 'true' } else { 'false' }` as the VALUE half. An if-expression right-hand
    # side arrives as an IfStatementAst directly (Resolve-PfbSingleExpression peels only the
    # Pipeline/CommandExpression wrappers a bare expression gets, and correctly leaves this
    # alone). Every condition below is load-bearing: without them the branch would credit the
    # parameter with a key whose value some OTHER expression decides.
    if ($IsBooleanLikeParameter -and $expr -is [System.Management.Automation.Language.IfStatementAst]) {
        $clauses = @($expr.Clauses)
        if ($clauses.Count -eq 1 -and $null -ne $expr.ElseClause) {
            $condition = $clauses[0].Item1.Extent.Text.Trim()
            if ($condition -eq $simple -or $condition -eq ('-not ' + $simple)) {
                $allConstant = $true
                foreach ($block in @($clauses[0].Item2, $expr.ElseClause)) {
                    if (@($block.Statements).Count -ne 1) { $allConstant = $false; break }
                    # StringConstantExpressionAst derives from ConstantExpressionAst, so the one
                    # test covers both the quoted and the bare-number forms.
                    $branch = Resolve-PfbSingleExpression -Ast $block.Statements[0]
                    if ($branch -isnot [System.Management.Automation.Language.ConstantExpressionAst]) {
                        $allConstant = $false; break
                    }
                }
                if ($allConstant) { return $true }
            }
        }
    }

    return $false
}

function Test-PfbWireValueIsParameterProjection {
    <#
    .SYNOPSIS
        True if -ValueAst is an array PROJECTION of the named parameter into single-key
        sub-objects -- `@($Param | ForEach-Object { @{ name = $_ } })` -- the idiom this
        module uses to build an array-of-references body field from a friendly [string[]].
    .DESCRIPTION
        Sibling of Test-PfbWireValueIsParameter, deliberately kept separate rather than
        folded into it. The two answer different questions: that one asks "does this value
        hand the parameter to the wire as-is", this one asks "does this value hand each
        ELEMENT of the parameter to the wire wrapped in a sub-object". Only the nested-
        reference resolver may act on the second, because only it credits the OUTER key --
        the direct resolvers would have nowhere correct to attribute it, and would name an
        `attached_servers.name` field that does not exist in the capability map.

        Shape-exact, matching this file's "never guess" contract. Accepted:
            @($Param | ForEach-Object { @{ key = $_ } })
            $Param | ForEach-Object { @{ key = $_ } }        -- unwrapped
            @($Param | % { @{ key = $_ } })                  -- alias
        The inner key need not be literally 'name' (see the scalar resolver's
        eradication_config precedent). Refused: a multi-key projection hashtable (a
        composite, whose per-field ownership cannot be attributed to one parameter); an
        innermost value that is anything but the bare $_ (`@{ name = $_.Name }`); a
        pipeline source that is not the bare parameter; a longer pipeline (a Where-Object
        filter in between means the wire value is a SUBSET, so the parameter does not cover
        the field); and a ForEach-Object carrying any argument other than its script block.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.Ast]$ValueAst,

        [Parameter(Mandatory)]
        [string]$ParameterName
    )

    $candidate = Resolve-PfbSingleExpression -Ast $ValueAst

    # `@( ... )` wraps the pipeline in an ArrayExpressionAst; the unwrapped form arrives as
    # the PipelineAst itself (Resolve-PfbSingleExpression returns a multi-element pipeline
    # unchanged -- it only peels SINGLE-element ones).
    $pipeline = $null
    if ($candidate -is [System.Management.Automation.Language.ArrayExpressionAst]) {
        if ($candidate.SubExpression.Statements.Count -ne 1) { return $false }
        $pipeline = $candidate.SubExpression.Statements[0] -as [System.Management.Automation.Language.PipelineAst]
    }
    else {
        $pipeline = $candidate -as [System.Management.Automation.Language.PipelineAst]
    }
    if (-not $pipeline -or $pipeline.PipelineElements.Count -ne 2) { return $false }

    # Element 1: the bare parameter, and nothing else. This is where the parameter's identity
    # comes from -- the innermost value is $_, which names nothing.
    $source = $pipeline.PipelineElements[0] -as [System.Management.Automation.Language.CommandExpressionAst]
    if (-not $source) { return $false }
    $sourceVar = $source.Expression -as [System.Management.Automation.Language.VariableExpressionAst]
    if (-not $sourceVar -or $sourceVar.VariablePath.UserPath -ne $ParameterName) { return $false }

    # Element 2: ForEach-Object with exactly one argument, a script block.
    $command = $pipeline.PipelineElements[1] -as [System.Management.Automation.Language.CommandAst]
    if (-not $command -or $command.CommandElements.Count -ne 2) { return $false }
    $commandName = $command.CommandElements[0] -as [System.Management.Automation.Language.StringConstantExpressionAst]
    if (-not $commandName -or $commandName.Value -notin @('ForEach-Object', '%')) { return $false }
    $scriptBlockExpr = $command.CommandElements[1] -as [System.Management.Automation.Language.ScriptBlockExpressionAst]
    if (-not $scriptBlockExpr) { return $false }

    # Script block body: exactly one statement, a single-string-key hashtable literal whose
    # one value is the bare pipeline variable.
    $scriptBlock = $scriptBlockExpr.ScriptBlock
    if ($scriptBlock.BeginBlock -or $scriptBlock.ProcessBlock -or $scriptBlock.DynamicParamBlock) { return $false }
    if (-not $scriptBlock.EndBlock -or $scriptBlock.EndBlock.Statements.Count -ne 1) { return $false }

    $hash = (Resolve-PfbSingleExpression -Ast $scriptBlock.EndBlock.Statements[0]) -as [System.Management.Automation.Language.HashtableAst]
    if (-not $hash -or $hash.KeyValuePairs.Count -ne 1) { return $false }
    if (-not ($hash.KeyValuePairs[0].Item1 -as [System.Management.Automation.Language.StringConstantExpressionAst])) { return $false }

    $innerValue = Resolve-PfbSingleExpression -Ast $hash.KeyValuePairs[0].Item2
    $innerVar = $innerValue -as [System.Management.Automation.Language.VariableExpressionAst]
    return ($null -ne $innerVar -and $innerVar.VariablePath.UserPath -eq '_')
}

function Get-PfbCommonQueryParamMap {
    <#
    .SYNOPSIS
        The wire-name mapping that Private/Add-PfbCommonQueryParams.ps1 performs on a
        calling cmdlet's behalf, so a parameter routed through that shared helper still
        resolves a wire name even though the calling cmdlet contains no literal
        `$queryParams['...'] = $Param` line of its own.
    .DESCRIPTION
        HARDCODED MIRROR of Private/Add-PfbCommonQueryParams.ps1 (issue #32/PR #49
        centralized -Filter/-Sort/-Limit/-TotalOnly/-Names/-Ids there; issue #33/PR #51
        migrated the rest). It is deliberately a copy rather than derived at runtime: this
        tools/ library parses Public/ as text and must not depend on the module being
        importable. Tests/PfbCmdletParamTools.Tests.ps1 asserts this table still matches
        the helper's own AST assignments, so the two cannot silently drift.

        Two different detection rules, because the helper learns its inputs two different ways:

          ByParameterName  -- the helper reads these straight out of the caller's
            $PSBoundParameters (`if ($BoundParameters.ContainsKey('Filter')) {...}`), so the
            caller's own param() name is the ONLY signal available. Only trusted when the
            call site actually forwards $PSBoundParameters.
          ByHelperArgument -- the helper takes these as its own parameters (-Names/-Ids), so
            the signal is whichever variable the call site passes to that argument. That is
            usually a `process`-block accumulator ($allNames), not the parameter itself --
            handled for free by Get-PfbCmdletParameterInventory's existing
            Find-PfbAccumulatorVariable retry. A call site may also hand the accumulator
            over as the exact zero-argument `$allNames.ToArray()` (the helper's -Names/-Ids
            are [string[]]-typed; real: Get-PfbUserGroupQuotaPolicy) -- same source variable,
            unwrapped structurally by Get-PfbCommonQueryParamHelperWireName.

        NOT included: the non-generic keys (file_system_names, policy_names, role_names,
        member_names, ...). Per issue #32's design those cmdlets deliberately kept their own
        explicit `$queryParams[...] = ...` lines after the helper call and were NOT routed
        through -Names/-Ids, so the literal-assignment resolver still handles them -- and
        must keep doing so, which is why the helper fallback runs only after it.
    .OUTPUTS
        [PSCustomObject]@{ HelperName; ByParameterName; ByHelperArgument }
    #>
    [CmdletBinding()]
    param()

    return [PSCustomObject]@{
        HelperName       = 'Add-PfbCommonQueryParams'
        ByParameterName  = [ordered]@{
            Filter    = 'filter'
            Sort      = 'sort'
            Limit     = 'limit'
            TotalOnly = 'total_only'
        }
        ByHelperArgument = [ordered]@{
            Names = 'names'
            Ids   = 'ids'
        }
    }
}

function Get-PfbHelperArgumentSourceVariable {
    <#
    .SYNOPSIS
        Returns the source variable behind an Add-PfbCommonQueryParams helper argument.
    .DESCRIPTION
        Accepted, shape-exactly, are a bare variable and a zero-argument instance
        `$variable.ToArray()` call. Everything else is refused: a different member name,
        a non-variable invocation target, an argument-bearing call, a longer member chain,
        or a static invocation. The helper's generic key must never be credited to data
        whose source cannot be identified exactly.

        `$var::ToArray()` is the reason the static check is a guard of its own rather than
        a consequence of the others: it parses as an InvokeMemberExpressionAst whose member
        is literally ToArray, carries zero arguments, and whose Expression is a bare
        VariableExpressionAst -- so it passes every other test here and resolves unless
        Static is tested explicitly.

        Extracted rather than inlined so the guards are reachable from a unit test against a
        parsed AST, independent of the fixture-file path. A guard with a single kill route is
        one outer-check bug away from being silently uncovered.
    .OUTPUTS
        $null, or the source variable's bare name (without '$').
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.Ast]$ArgumentAst
    )

    $bare = $ArgumentAst -as [System.Management.Automation.Language.VariableExpressionAst]
    if ($bare) { return $bare.VariablePath.UserPath }

    $invoke = $ArgumentAst -as [System.Management.Automation.Language.InvokeMemberExpressionAst]
    if (-not $invoke) { return $null }
    if ($invoke.Static) { return $null }
    # Defensive, not behavioural: a dynamic member name ($var.$name()) exposes no .Value, so
    # the next line already refuses it while this file runs without Set-StrictMode. Kept so the
    # refusal survives a future strict mode, which is why no mutation of it can be killed.
    if ($invoke.Member -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) { return $null }
    if ($invoke.Member.Value -ne 'ToArray') { return $null }
    if (-not (Test-PfbInvokeHasNoArguments -Invoke $invoke)) { return $null }

    $target = $invoke.Expression -as [System.Management.Automation.Language.VariableExpressionAst]
    if (-not $target) { return $null }
    return $target.VariablePath.UserPath
}

function Get-PfbCommonQueryParamHelperWireName {
    <#
    .SYNOPSIS
        The Add-PfbCommonQueryParams-aware half of wire-name resolution: finds the key the
        shared helper assigns on this cmdlet's behalf for -ParameterName, or $null.
    .DESCRIPTION
        Never guesses, matching the rest of this file: requires a literal -Into <variable>
        (that variable is what Get-PfbEndpointForVariable later traces to an
        Invoke-PfbApiRequest call, so without it there is nothing to attribute), requires
        -BoundParameters to be literally $PSBoundParameters before trusting the
        ByParameterName rule, and returns $null if two helper calls in the same function
        disagree on the (WireName, TargetVariable) pair. A ByHelperArgument's value is read
        only as a plain variable (`-Names $allNames`) or the exact zero-argument
        `$var.ToArray()` call on a bare variable (real: Get-PfbUserGroupQuotaPolicy, which
        must convert its [List[string]] accumulators to arrays for the helper's [string[]]
        parameters); any other member call shape stays refused.

        RESIDUAL ABSTENTION HAZARD, for whoever changes a caller. This function collapses two
        different answers into one $null: "no Add-PfbCommonQueryParams call names this
        parameter" (silence -- keep looking) and "two calls disagree about it" (abstention --
        stop looking, the truth is genuinely undetermined).

        Resolve-PfbParameterWireLanding cannot tell the two apart: this $null collapses to an
        empty helper tier and reads as silence -- see its own .DESCRIPTION, "One abstention
        remains invisible here". Get-PfbCmdletParameterInventory's accumulator retry then fires
        on that empty landing set, so a helper abstention DOES reach a fifth source. That is
        deliberate for issue #141 Task 4, which must leave every real-tree resolution tuple
        untouched -- it is a RECORDED LIMIT, not a mitigation, and this block is not a licence
        to assume the caller is guarding it. A caller that additionally treated $null here as
        "not my parameter" and fell through to a looser resolver would compound that into a
        confident wrong wire name, which is the exact failure the never-guess contract exists
        to prevent.

        Nothing in the tree reaches it today, and that is measured rather than assumed: only
        Get-PfbQuotaUser has two helper call sites, both target $queryParams, and the
        ByParameterName rule has no Name entry, so the distinct (WireName, TargetVariable)
        count is 1 everywhere. It is a live hazard for a FUTURE cmdlet, not a present defect.
    .OUTPUTS
        $null, or [PSCustomObject]@{ WireName; TargetVariable } -- same shape as
        Get-PfbWireNameForParameter.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.FunctionDefinitionAst]$FunctionAst,

        [Parameter(Mandatory)]
        [string]$ParameterName
    )

    $map = Get-PfbCommonQueryParamMap
    $helperName = $map.HelperName

    $calls = @($FunctionAst.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.CommandAst] -and
        $node.GetCommandName() -eq $helperName
    }, $true))
    if ($calls.Count -eq 0) { return $null }

    $found = [System.Collections.Generic.List[string]]::new()

    foreach ($call in $calls) {
        $elements = $call.CommandElements
        $intoVariable = $null
        $forwardsBoundParameters = $false
        $argumentVariables = @{}

        for ($i = 0; $i -lt $elements.Count; $i++) {
            $el = $elements[$i]
            if ($el -isnot [System.Management.Automation.Language.CommandParameterAst]) { continue }

            # `-Into:$queryParams` colon form parks the value on the CommandParameterAst
            # itself; `-Into $queryParams` puts it in the NEXT element. Reading $next
            # unconditionally would misread the colon form as taking the following switch.
            $argExpr = if ($el.Argument) { $el.Argument }
                       elseif ($i + 1 -lt $elements.Count) { $elements[$i + 1] }
                       else { $null }
            if (-not $argExpr) { continue }
            $argVar = $argExpr -as [System.Management.Automation.Language.VariableExpressionAst]

            if ($el.ParameterName -eq 'Into') {
                if ($argVar) { $intoVariable = $argVar.VariablePath.UserPath }
            }
            elseif ($el.ParameterName -eq 'BoundParameters') {
                if ($argVar -and $argVar.VariablePath.UserPath -eq 'PSBoundParameters') { $forwardsBoundParameters = $true }
            }
            elseif ($map.ByHelperArgument.Contains($el.ParameterName)) {
                # Bare `$allNames` or the exact zero-argument `$allNames.ToArray()` -- how a
                # [List[string]] accumulator is handed to the helper's [string[]]-typed
                # -Names/-Ids (real: Get-PfbUserGroupQuotaPolicy). Every refusal reason lives
                # in Get-PfbHelperArgumentSourceVariable, one guard per line.
                $sourceName = Get-PfbHelperArgumentSourceVariable -ArgumentAst $argExpr
                if ($sourceName) { $argumentVariables[$el.ParameterName] = $sourceName }
            }
        }

        if (-not $intoVariable) { continue }

        foreach ($helperArg in $map.ByHelperArgument.Keys) {
            if ($argumentVariables.ContainsKey($helperArg) -and $argumentVariables[$helperArg] -eq $ParameterName) {
                $found.Add("$($map.ByHelperArgument[$helperArg])|$intoVariable")
            }
        }

        if ($forwardsBoundParameters -and $map.ByParameterName.Contains($ParameterName)) {
            $found.Add("$($map.ByParameterName[$ParameterName])|$intoVariable")
        }
    }

    $distinct = @($found | Select-Object -Unique)
    if ($distinct.Count -ne 1) { return $null }

    $parts = $distinct[0] -split '\|', 2
    return [PSCustomObject]@{ WireName = $parts[0]; TargetVariable = $parts[1] }
}

function Resolve-PfbWireLandingArbitration {
    <#
    .SYNOPSIS
        Reduces the candidate wire landings of ONE parameter to at most one resolution,
        keeping only what every candidate agrees on.
    .DESCRIPTION
        A candidate is one proven assignment of the parameter into a payload variable, joined
        to that variable's argument-proven request role: the complete tuple
        (WireName, WireSurface, Method, Endpoint), plus the TargetVariable it came through.

        Arbitration is deliberately independent of AST traversal order. Selecting the first
        match -- which is what this file did before issue #141 Task 3 -- publishes whichever
        landing the parser happened to reach first and silently discards the rest, and the
        name gate was the only thing hiding how bad that is. Retiring the gate makes
        Remove-PfbFileSystem's $destroyQuery the earlier match for -DeleteLinkOnEradication,
        so first-match would have reported PATCH file-systems with confidence while the DELETE
        file-systems landing of the very same key vanished from the report.

        So: components that every candidate shares are kept, and the rest are nulled. There is
        no separate deduplication pass because none is needed -- repeated identical tuples
        agree on every component by construction, and therefore survive whole. A key assigned
        in both arms of an if/else is one landing, not an ambiguity.

        WireName is the one component whose absence voids the whole resolution. With no agreed
        key there is nothing nameable left to publish, and returning a record carrying a null
        WireName would additionally suppress the accumulator retry in
        Get-PfbCmdletParameterInventory, which fires only when this returns $null.
    .OUTPUTS
        $null, or [PSCustomObject]@{ WireName; TargetVariable; WireSurface; Method; Endpoint }.
        WireSurface is 'Body', 'Query' or 'Unresolved'; Method and Endpoint are either both
        populated or both $null.
    #>
    [CmdletBinding()]
    param(
        # [PSCustomObject]@{ WireName; TargetVariable; WireSurface; Method; Endpoint }
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Candidate
    )

    $candidates = @($Candidate)
    if ($candidates.Count -eq 0) { return $null }

    # ORDINAL, deliberately. PowerShell's -ne is case-INSENSITIVE for strings, so a
    # component-wise merge written with it judges 'names' and 'Names' to agree and then
    # publishes whichever the parser reached first -- a source-order artefact of exactly the
    # kind this whole function exists to eliminate, and one that would go unnoticed because
    # the clash is never reported. It would also put this function at odds with
    # Get-PfbRequestRoleForVariable, whose List[string].Contains distinctness tests are
    # ordinal: the role tracer and the arbitrator have to mean the same thing by "the same
    # string". Wire keys, HTTP methods and endpoints are all case-sensitive on the wire, and
    # there being no differing-case pair in Public/ today is the same argument that would
    # have justified keeping the name switch.
    $agreedValue = {
        param($Property)
        $first = $candidates[0].$Property
        foreach ($item in $candidates) {
            $value = $item.$Property
            if ($null -eq $value -and $null -eq $first) { continue }
            if ($null -eq $value -or $null -eq $first) { return $null }
            if (-not [string]::Equals([string]$value, [string]$first, [System.StringComparison]::Ordinal)) { return $null }
        }
        return $first
    }

    $wireName = & $agreedValue 'WireName'
    if (-not $wireName) { return $null }

    $wireSurface = & $agreedValue 'WireSurface'
    if (-not $wireSurface) { $wireSurface = 'Unresolved' }

    $method = & $agreedValue 'Method'
    $endpoint = & $agreedValue 'Endpoint'
    if (-not ($method -and $endpoint)) {
        $method = $null
        $endpoint = $null
    }

    return [PSCustomObject]@{
        WireName       = $wireName
        TargetVariable = (& $agreedValue 'TargetVariable')
        WireSurface    = $wireSurface
        Method         = $method
        Endpoint       = $endpoint
    }
}

function New-PfbWireLanding {
    <#
    .SYNOPSIS
        Builds one arbitration candidate from a proven (key, payload variable) assignment,
        or $null when that variable has no argument-proven request role.
    .DESCRIPTION
        This is the role gate, and it stands exactly where the
        `-notin @('body', 'queryParams')` name gate used to. A variable that is never handed
        to Invoke-PfbApiRequest -Body/-QueryParams is an intermediate, not a payload:
        New-PfbFileSystem's $nfsBody is keyed and then folded into $body under a
        sub-object, so crediting -ExportPolicy with $nfsBody's 'export_policy' key would name
        a top-level field that no request this cmdlet makes actually has. The old gate
        excluded such variables by recognising two blessed names; this one excludes them by
        failing to prove they are sent, which also admits $q, $payload and $destroyQuery.
    .OUTPUTS
        $null, or [PSCustomObject]@{ WireName; TargetVariable; WireSurface; Method; Endpoint }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.FunctionDefinitionAst]$FunctionAst,

        [Parameter(Mandatory)]
        [string]$WireName,

        [Parameter(Mandatory)]
        [string]$TargetVariable
    )

    $role = Get-PfbRequestRoleForVariable -FunctionAst $FunctionAst -TargetVariable $TargetVariable
    if (-not $role) { return $null }

    return [PSCustomObject]@{
        WireName       = $WireName
        TargetVariable = $TargetVariable
        WireSurface    = $role.WireSurface
        Method         = $role.Method
        Endpoint       = $role.Endpoint
    }
}

function Resolve-PfbParameterWireLanding {
    <#
    .SYNOPSIS
        The whole wire-landing resolution of ONE parameter: the landings the winning idiom
        proved, AND the single answer they arbitrate to -- returned together, so a caller can
        tell an abstention from a silence.
    .DESCRIPTION
        Four idioms are tried in a fixed precedence, and the FIRST idiom that produces any
        proven landing answers -- including by abstaining. Precedence is between idioms only;
        within one idiom every landing is collected and arbitrated together
        (Resolve-PfbWireLandingArbitration), so the answer never depends on which assignment
        the parser reached first.

        A tier that finds landings and then abstains does not fall through to the next tier.
        Falling through would let a weaker idiom quietly supply a name for a parameter whose
        stronger, ambiguous evidence had just been discarded -- which is the first-match
        failure wearing a different hat.

        That invariant is a property of HOW each tier is consulted, so it has to be
        implemented at all four, not just the first. Every tier is asked for its LANDINGS
        (Get-PfbHashtableLiteralWireLanding, Get-PfbNestedReferenceWireLanding), and the
        decision to answer is made on `landings.Count -gt 0` -- never on the truthiness of an
        arbitrated result, which cannot tell "found nothing" from "found landings that
        disagreed". An earlier revision of this resolver got that right for the index tier
        and wrong for the other three: a literal tier holding two disagreeing keys returned
        $null and the nested tier then published its own key, exactly the guess the tier
        order exists to prevent.

        RETURNING BOTH HALVES is what carries that same distinction ACROSS the return, which
        a lone arbitrated value cannot. `Resolution` is $null both when nothing was found and
        when what was found disagreed; `Landings` is empty only in the first case. Issue #141
        Task 4 introduced this shape because Get-PfbCmdletParameterInventory's accumulator
        retry fired on the arbitrated $null, so a parameter that had just abstained had a
        FIFTH source consulted on its behalf and could be published with a confident name --
        an abstention laundered into an answer. That caller now retries only on an empty
        `Landings`, i.e. only on genuine silence.

        One abstention remains invisible here, and deliberately so: the one inside
        Get-PfbCommonQueryParamHelperWireName, which returns $null when two helper calls
        disagree. It collapses to an empty helper tier and so reads as silence. Surfacing it
        would change which parameters reach the accumulator retry -- a resolution change --
        and issue #141 Task 4 is required to leave every real-tree resolution tuple untouched.
        It is recorded here rather than fixed silently.
    .OUTPUTS
        [PSCustomObject]@{ Landings; Resolution }.
        Landings is the winning idiom's UNARBITRATED candidate array, empty when no idiom
        proved anything at all. Resolution is Resolve-PfbWireLandingArbitration's verdict over
        exactly those landings -- $null, or
        [PSCustomObject]@{ WireName; TargetVariable; WireSurface; Method; Endpoint }.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.FunctionDefinitionAst]$FunctionAst,

        [Parameter(Mandatory)]
        [string]$ParameterName,

        [switch]$IsBooleanLikeParameter
    )

    $assignments = $FunctionAst.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $node.Left -is [System.Management.Automation.Language.IndexExpressionAst]
    }, $true)

    $landings = [System.Collections.Generic.List[object]]::new()

    foreach ($assign in $assignments) {
        $indexExpr = $assign.Left
        $targetVar = $indexExpr.Target -as [System.Management.Automation.Language.VariableExpressionAst]
        if (-not $targetVar) { continue }

        $keyExpr = $indexExpr.Index -as [System.Management.Automation.Language.StringConstantExpressionAst]
        if (-not $keyExpr) { continue }

        if (Test-PfbWireValueIsParameter -ValueAst $assign.Right -ParameterName $ParameterName -IsBooleanLikeParameter:$IsBooleanLikeParameter) {
            $landing = New-PfbWireLanding -FunctionAst $FunctionAst -WireName $keyExpr.Value -TargetVariable $targetVar.VariablePath.UserPath
            if ($landing) { $landings.Add($landing) }
        }
    }

    # $null, never an empty array, means "no tier has answered yet": an empty array is falsy
    # in PowerShell but so is a one-element array holding $null, and the tiers below are
    # selected on `-eq $null` precisely so no truthiness rule is being relied on anywhere in
    # this function. Every tier below is consulted for its LANDINGS, never for its arbitrated
    # answer -- asking `if ($literalMatch)` instead would read an abstention as a miss and
    # fall through, which is the whole failure this resolver exists to prevent.
    $tierLandings = $null
    if ($landings.Count -gt 0) { $tierLandings = $landings.ToArray() }

    # Second idiom: the whole hashtable is built as a LITERAL initializer rather than keyed
    # into afterwards -- `$queryParams = @{ 'names' = $Name }`, the dominant shape across
    # New-Pfb*/Remove-Pfb*/Update-Pfb* (New-PfbApiClient, New-PfbAlertWatcher,
    # New-PfbObjectStoreAccount, the whole Policy/*Rule family, ...). Runs after the index
    # form, not instead of it: a cmdlet routinely does both (literal initializer for its
    # -Name, then `$body['x'] = $X` lines), and both key sets must resolve.
    if ($null -eq $tierLandings) {
        $literalLandings = @(Get-PfbHashtableLiteralWireLanding -FunctionAst $FunctionAst -ParameterName $ParameterName -IsBooleanLikeParameter:$IsBooleanLikeParameter)
        if ($literalLandings.Count -gt 0) { $tierLandings = $literalLandings }
    }

    # Third idiom: a nested single-key REFERENCE OBJECT -- `$body['account'] = @{ name =
    # $Account }` -- whose wire field is the OUTER key. Runs strictly after both direct
    # forms above so it can only ever add a resolution, never rename one: a parameter that
    # already resolved via a direct assignment stopped at the tier that proved it.
    if ($null -eq $tierLandings) {
        $nestedLandings = @(Get-PfbNestedReferenceWireLanding -FunctionAst $FunctionAst -ParameterName $ParameterName -IsBooleanLikeParameter:$IsBooleanLikeParameter)
        if ($nestedLandings.Count -gt 0) { $tierLandings = $nestedLandings }
    }

    # No literal assignment of any shape in this function body -- but the parameter may
    # still reach the wire through the shared Private/Add-PfbCommonQueryParams.ps1 helper,
    # which performs the assignment on the cmdlet's behalf (issue #32/#33). Deliberately
    # LAST: a cmdlet whose Name/Id-equivalent maps to a non-generic key (policy_names,
    # file_system_names, ...) kept its own explicit line after the helper call, and that
    # literal must win.
    if ($null -eq $tierLandings) {
        $helperLandings = [System.Collections.Generic.List[object]]::new()
        foreach ($helperMatch in @(Get-PfbCommonQueryParamHelperWireName -FunctionAst $FunctionAst -ParameterName $ParameterName)) {
            if (-not $helperMatch) { continue }
            $landing = New-PfbWireLanding -FunctionAst $FunctionAst -WireName $helperMatch.WireName -TargetVariable $helperMatch.TargetVariable
            if ($landing) { $helperLandings.Add($landing) }
        }
        if ($helperLandings.Count -gt 0) { $tierLandings = $helperLandings.ToArray() }
    }

    if ($null -eq $tierLandings) {
        return [PSCustomObject]@{ Landings = @(); Resolution = $null }
    }

    return [PSCustomObject]@{
        Landings   = @($tierLandings)
        Resolution = (Resolve-PfbWireLandingArbitration -Candidate $tierLandings)
    }
}

function Get-PfbWireNameForParameter {
    <#
    .SYNOPSIS
        Finds the request-body or query-string key a given parameter is assigned to
        inside a cmdlet function body, or $null if no simple assignment pattern matches.
    .DESCRIPTION
        A thin projection of Resolve-PfbParameterWireLanding onto its arbitrated half. All of
        the tier precedence, the within-tier arbitration and the sticky-abstention invariant
        live there; see that function's .DESCRIPTION.

        SCOPE OF THE INVARIANT -- the stickiness holds inside the resolver and stops at THIS
        function's return, because $null is the only signal this shape has and it is spent
        twice: once for "no idiom proved anything" and once for "an idiom proved landings that
        disagreed". A caller that must tell those apart -- Get-PfbCmdletParameterInventory
        must, or its accumulator retry launders an abstention into a confident name -- calls
        Resolve-PfbParameterWireLanding and reads `Landings`. Do not infer from a $null here
        that no landings existed.
    .OUTPUTS
        $null, or [PSCustomObject]@{ WireName; TargetVariable; WireSurface; Method; Endpoint }.
        TargetVariable is the payload variable the assignment targeted, or $null when the
        landings came through more than one; WireSurface is 'Body', 'Query' or 'Unresolved'.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.FunctionDefinitionAst]$FunctionAst,

        [Parameter(Mandatory)]
        [string]$ParameterName,

        [switch]$IsBooleanLikeParameter
    )

    return (Resolve-PfbParameterWireLanding -FunctionAst $FunctionAst -ParameterName $ParameterName -IsBooleanLikeParameter:$IsBooleanLikeParameter).Resolution
}

function Get-PfbHashtableLiteralWireNameForParameter {
    <#
    .SYNOPSIS
        The hashtable-literal-initializer half of wire-name resolution: finds the key a
        parameter is given inside `$body = @{ ... }` / `$queryParams = @{ ... }`, or $null.
    .DESCRIPTION
        Only TOP-LEVEL key/value pairs of a hashtable literal assigned directly to a
        variable named body/queryParams are considered, and a nested sub-object's INNER key
        is never treated as the wire name: in `$body = @{ group = @{ name = $GroupName } }`
        (real: New-PfbQuotaGroup) the wire field is `group`, so crediting -GroupName with
        `name` would both mis-name the field and collide with every other sub-object's
        `name`. Resolving such a parameter to its OUTER key is a separate, deliberately
        later step -- see Get-PfbNestedReferenceWireNameForParameter. Value shapes are
        matched by the same Test-PfbWireValueIsParameter used by the index-assignment path,
        so a pipeline transform is still refused rather than guessed at.
    .OUTPUTS
        $null, or [PSCustomObject]@{ WireName; TargetVariable; WireSurface; Method; Endpoint }
        -- same shape as Get-PfbWireNameForParameter, arbitrated the same way. Callers that
        need to tell "this idiom found nothing" apart from "this idiom found landings and
        then abstained" must use Get-PfbHashtableLiteralWireLanding instead: both outcomes
        are $null here.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.FunctionDefinitionAst]$FunctionAst,

        [Parameter(Mandatory)]
        [string]$ParameterName,

        [switch]$IsBooleanLikeParameter
    )

    $landings = @(Get-PfbHashtableLiteralWireLanding -FunctionAst $FunctionAst -ParameterName $ParameterName -IsBooleanLikeParameter:$IsBooleanLikeParameter)
    if ($landings.Count -eq 0) { return $null }
    return Resolve-PfbWireLandingArbitration -Candidate $landings
}

function Get-PfbHashtableLiteralWireLanding {
    <#
    .SYNOPSIS
        Every hashtable-literal landing for a parameter, unarbitrated.
    .DESCRIPTION
        Exists so an idiom's ABSTENTION is distinguishable from its silence. An arbitrated
        $null means either "no landing" or "landings that disagreed", and
        Get-PfbWireNameForParameter must not treat those alike: falling through to a weaker
        idiom after a stronger one abstained lets the weaker one publish a wire name for a
        parameter whose better evidence was just discarded, which is first-match arbitration
        wearing a different hat.
    .OUTPUTS
        An array, possibly empty, of the landing objects New-PfbWireLanding builds.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.FunctionDefinitionAst]$FunctionAst,

        [Parameter(Mandatory)]
        [string]$ParameterName,

        [switch]$IsBooleanLikeParameter
    )

    $assignments = @($FunctionAst.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $node.Left -is [System.Management.Automation.Language.VariableExpressionAst]
    }, $true))

    $landings = [System.Collections.Generic.List[object]]::new()

    foreach ($assign in $assignments) {
        $targetVar = $assign.Left -as [System.Management.Automation.Language.VariableExpressionAst]

        $hashtable = (Resolve-PfbSingleExpression -Ast $assign.Right) -as [System.Management.Automation.Language.HashtableAst]
        if (-not $hashtable) { continue }

        foreach ($pair in $hashtable.KeyValuePairs) {
            # KeyValuePairs entries are Tuple<ExpressionAst, StatementAst>. Keys in this repo
            # are written both quoted ('names') and bare (destroyed); StringConstantExpressionAst
            # covers both and exposes the unquoted text as .Value.
            $keyExpr = $pair.Item1 -as [System.Management.Automation.Language.StringConstantExpressionAst]
            if (-not $keyExpr) { continue }

            if (Test-PfbWireValueIsParameter -ValueAst $pair.Item2 -ParameterName $ParameterName -IsBooleanLikeParameter:$IsBooleanLikeParameter) {
                $landing = New-PfbWireLanding -FunctionAst $FunctionAst -WireName $keyExpr.Value -TargetVariable $targetVar.VariablePath.UserPath
                if ($landing) { $landings.Add($landing) }
            }
        }
    }

    return $landings.ToArray()
}

function Get-PfbNestedReferenceWireNameForParameter {
    <#
    .SYNOPSIS
        The nested-single-key-reference-object half of wire-name resolution: finds the OUTER
        key of `$body['account'] = @{ name = $Account }` / `$body = @{ account = @{ name =
        $Account } }`, or $null.
    .DESCRIPTION
        The REST API models a reference to another resource as a single-key sub-object
        (`{"account": {"name": "acct1"}}`), and the capability map records TOP-LEVEL body
        properties only -- there is no `account.name` field in it. So the wire name a
        parameter feeding such a sub-object exposes is the outer key (`account`), and any
        attempt to credit it with the inner key would name a field that does not exist.

        Two parameters legitimately resolving to the SAME outer key is therefore correct,
        not a collision to suppress: `-Account`/`-AccountId` both address the one `account`
        field, and the endpoint's gap analysis only ever asks whether `account` is covered.

        Never guesses, matching the rest of this file:
          - the target variable must have an argument-proven request role (an intermediate
            like New-PfbFileSystem's $nfsBody is never handed to Invoke-PfbApiRequest, so
            its keys are not the keys of any request);
          - the outer key must be a literal string constant;
          - the nested hashtable must have EXACTLY ONE key/value pair, itself string-keyed
            -- a multi-key sub-object is a composite whose per-field ownership cannot be
            attributed to one parameter;
          - only ONE level of nesting is descended;
          - the innermost value must satisfy either Test-PfbWireValueIsParameter (the scalar
            form, `@{ name = $Account }`) or Test-PfbWireValueIsParameterProjection (the
            array form, New-PfbNetworkInterface's `@($AttachedServers | ForEach-Object
            { @{ name = $_ } })`). Shapes that still cannot be attributed to one parameter
            remain refused: a multi-key projection item, an innermost `$_.Member` rather than
            the bare `$_`, and a filtered pipeline, whose wire value is a SUBSET of the
            parameter.

        Deliberately invoked LAST of the three literal forms by
        Get-PfbWireNameForParameter, after both direct-assignment resolvers: it can then
        only ever turn an unresolved parameter into a Typed one, never rename an
        already-resolved wire name.
    .OUTPUTS
        $null, or [PSCustomObject]@{ WireName; TargetVariable; WireSurface; Method; Endpoint }
        -- same shape as Get-PfbWireNameForParameter, arbitrated the same way. As with the
        hashtable-literal form, a caller that must tell abstention from silence has to use
        Get-PfbNestedReferenceWireLanding.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.FunctionDefinitionAst]$FunctionAst,

        [Parameter(Mandatory)]
        [string]$ParameterName,

        [switch]$IsBooleanLikeParameter
    )

    $landings = @(Get-PfbNestedReferenceWireLanding -FunctionAst $FunctionAst -ParameterName $ParameterName -IsBooleanLikeParameter:$IsBooleanLikeParameter)
    if ($landings.Count -eq 0) { return $null }
    return Resolve-PfbWireLandingArbitration -Candidate $landings
}

function Get-PfbNestedReferenceWireLanding {
    <#
    .SYNOPSIS
        Every nested-reference landing for a parameter, unarbitrated -- see
        Get-PfbHashtableLiteralWireLanding for why the unarbitrated form exists.
    .DESCRIPTION
        Two sub-forms in a fixed order, the index form then the literal-initializer form,
        mirroring the order Get-PfbWireNameForParameter uses for the direct shapes. The
        literal sub-form is consulted only when the index sub-form found NOTHING, so an index
        sub-form that found landings owns the answer even if those landings then disagree.
    .OUTPUTS
        An array, possibly empty, of the landing objects New-PfbWireLanding builds.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.FunctionDefinitionAst]$FunctionAst,

        [Parameter(Mandatory)]
        [string]$ParameterName,

        [switch]$IsBooleanLikeParameter
    )

    # Local predicate: is $Candidate a single-string-key hashtable literal whose one value
    # hands $ParameterName to the wire?
    $isReferenceObjectFor = {
        param($Candidate)
        # Array-of-references projection: the parameter's identity is the pipeline SOURCE, so
        # this cannot route through Test-PfbWireValueIsParameter the way the scalar form does.
        if (Test-PfbWireValueIsParameterProjection -ValueAst $Candidate -ParameterName $ParameterName) { return $true }

        $hash = (Resolve-PfbSingleExpression -Ast $Candidate) -as [System.Management.Automation.Language.HashtableAst]
        if (-not $hash) { return $false }
        if ($hash.KeyValuePairs.Count -ne 1) { return $false }
        $innerPair = $hash.KeyValuePairs[0]
        if (-not ($innerPair.Item1 -as [System.Management.Automation.Language.StringConstantExpressionAst])) { return $false }
        return (Test-PfbWireValueIsParameter -ValueAst $innerPair.Item2 -ParameterName $ParameterName -IsBooleanLikeParameter:$IsBooleanLikeParameter)
    }

    $assignments = @($FunctionAst.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.AssignmentStatementAst]
    }, $true))

    $indexLandings = [System.Collections.Generic.List[object]]::new()

    foreach ($assign in $assignments) {
        $indexExpr = $assign.Left -as [System.Management.Automation.Language.IndexExpressionAst]
        if (-not $indexExpr) { continue }
        $targetVar = $indexExpr.Target -as [System.Management.Automation.Language.VariableExpressionAst]
        if (-not $targetVar) { continue }

        $keyExpr = $indexExpr.Index -as [System.Management.Automation.Language.StringConstantExpressionAst]
        if (-not $keyExpr) { continue }

        if (& $isReferenceObjectFor $assign.Right) {
            $landing = New-PfbWireLanding -FunctionAst $FunctionAst -WireName $keyExpr.Value -TargetVariable $targetVar.VariablePath.UserPath
            if ($landing) { $indexLandings.Add($landing) }
        }
    }

    if ($indexLandings.Count -gt 0) { return $indexLandings.ToArray() }

    $literalLandings = [System.Collections.Generic.List[object]]::new()

    foreach ($assign in $assignments) {
        $targetVar = $assign.Left -as [System.Management.Automation.Language.VariableExpressionAst]
        if (-not $targetVar) { continue }

        $hashtable = (Resolve-PfbSingleExpression -Ast $assign.Right) -as [System.Management.Automation.Language.HashtableAst]
        if (-not $hashtable) { continue }

        foreach ($pair in $hashtable.KeyValuePairs) {
            $keyExpr = $pair.Item1 -as [System.Management.Automation.Language.StringConstantExpressionAst]
            if (-not $keyExpr) { continue }

            if (& $isReferenceObjectFor $pair.Item2) {
                $landing = New-PfbWireLanding -FunctionAst $FunctionAst -WireName $keyExpr.Value -TargetVariable $targetVar.VariablePath.UserPath
                if ($landing) { $literalLandings.Add($landing) }
            }
        }
    }

    return $literalLandings.ToArray()
}

function Find-PfbAccumulatorVariable {
    <#
    .SYNOPSIS
        Finds the accumulator variable a parameter feeds via
        `foreach ($x in $Param) { $accumulator.Add($x) }`, so its eventual wire-name
        assignment can be traced by re-running Get-PfbWireNameForParameter against the
        accumulator's own name.
    .DESCRIPTION
        Never guesses: returns $null unless there is exactly one such foreach loop over
        $ParameterName, its body contains exactly one .Add(...) call whose target is a
        bare variable and whose single argument is the loop variable, AND that same
        accumulator variable is never .Add()-ed to from anywhere else in the function
        (an ambiguous shared accumulator fed by more than one parameter's own loop).
    .OUTPUTS
        $null, or the accumulator's bare variable name (string, no leading '$').
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.FunctionDefinitionAst]$FunctionAst,

        [Parameter(Mandatory)]
        [string]$ParameterName
    )

    # ForEachStatementAst.Condition (the collection expression after `in`) is always wrapped
    # in a PipelineAst containing a single CommandExpressionAst -- the parser never exposes
    # a bare VariableExpressionAst directly here, so unwrap two levels before casting (the
    # same wrapping phenomenon as AssignmentStatementAst.Right, documented on
    # Get-PfbWireNameForParameter's $rhsExpr, just one layer deeper for a loop condition).
    $allForeachLoops = @($FunctionAst.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.ForEachStatementAst]
    }, $true))

    $foreachLoops = @($allForeachLoops | Where-Object {
        $cond = $_.Condition
        if ($cond -is [System.Management.Automation.Language.PipelineAst] -and $cond.PipelineElements.Count -eq 1) {
            $cond = $cond.PipelineElements[0]
        }
        if ($cond -is [System.Management.Automation.Language.CommandExpressionAst]) {
            $cond = $cond.Expression
        }
        $cond -is [System.Management.Automation.Language.VariableExpressionAst] -and
        $cond.VariablePath.UserPath -eq $ParameterName
    })

    if ($foreachLoops.Count -ne 1) { return $null }
    $loop = $foreachLoops[0]
    $loopVarName = $loop.Variable.VariablePath.UserPath

    $addCallsInLoop = @($loop.Body.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
        $node.Member -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
        $node.Member.Value -eq 'Add' -and
        $node.Expression -is [System.Management.Automation.Language.VariableExpressionAst] -and
        $node.Arguments.Count -eq 1 -and
        $node.Arguments[0] -is [System.Management.Automation.Language.VariableExpressionAst] -and
        $node.Arguments[0].VariablePath.UserPath -eq $loopVarName
    }, $true))

    if ($addCallsInLoop.Count -ne 1) { return $null }
    $accumulatorName = $addCallsInLoop[0].Expression.VariablePath.UserPath

    $allAddCallsForAccumulator = @($FunctionAst.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
        $node.Member -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
        $node.Member.Value -eq 'Add' -and
        $node.Expression -is [System.Management.Automation.Language.VariableExpressionAst] -and
        $node.Expression.VariablePath.UserPath -eq $accumulatorName
    }, $true))

    if ($allAddCallsForAccumulator.Count -ne 1) { return $null }

    return $accumulatorName
}

function Get-PfbRequestRoleForVariable {
    <#
    .SYNOPSIS
        The request role a variable actually plays -- Body or Query, and the operation it
        reaches -- read from the ARGUMENTS of the Invoke-PfbApiRequest calls it is passed
        to, never from its name.
    .DESCRIPTION
        This replaces a `switch ($TargetVariable) { 'body' {...} 'queryParams' {...} }` trust
        gate, which was an inference from a name and so a standing violation of the
        never-guess contract in both directions (issue #141). It under-reported: a cmdlet
        keying into $q, $payload or $destroyQuery had no role at all, so every parameter it
        proved was silently dropped. And it could over-report: a variable literally named
        $body but passed to -QueryParams would have been published as a Body landing. That
        second class has zero current occurrences in Public/, which is precisely why it needs
        a resolver that cannot express it rather than a one-off survey.

        A call contributes a LANDING when the variable is passed, as the bare variable, to
        -Body (surface 'Body') or -QueryParams (surface 'Query'). Both argument forms are
        read: `-Body $payload` parks the value in the NEXT command element, while
        `-Body:$payload` parks it on the CommandParameterAst's own .Argument. Reading only
        the next element -- as the retired implementation did -- misses the colon form.

        Anything other than the bare variable is refused: `-Body @{}`, `-Body $wrapper.Inner`,
        `-Body ($payload + @{})`, `-Body $payload['alpha']`. In none of those is the
        variable's key set provably the key set of the request.

        Method and Endpoint come from LITERAL -Method/-Endpoint arguments of the same call,
        matching the exclusively literal style every cmdlet in this repo uses for both, and
        are reported only when every landing agrees on one operation. A call whose -Method or
        -Endpoint is a variable, or which omits one, still counts as a landing with an
        UNKNOWN operation -- it is exactly the landing that cannot be read, so allowing a
        readable sibling call to win would publish an operation the variable does not
        exclusively reach.

        Returns $null when the variable has no landing at all, and when it lands on BOTH
        surfaces: a payload sent as body in one call and as query string in another has no
        single role to report, and picking either would be a guess.
    .OUTPUTS
        $null, or [PSCustomObject]@{ TargetVariable; WireSurface; Method; Endpoint }.
        WireSurface is 'Body' or 'Query'. Method and Endpoint are either both populated or
        both $null -- half an operation identifies nothing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.FunctionDefinitionAst]$FunctionAst,

        [Parameter(Mandatory)]
        [string]$TargetVariable
    )

    $commands = @($FunctionAst.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.CommandAst] -and
        $node.GetCommandName() -eq 'Invoke-PfbApiRequest'
    }, $true))

    $landings = [System.Collections.Generic.List[object]]::new()

    foreach ($cmd in $commands) {
        $elements = @($cmd.CommandElements)
        $surfaces = [System.Collections.Generic.List[string]]::new()
        $method = $null
        $endpoint = $null

        for ($i = 0; $i -lt $elements.Count; $i++) {
            $el = $elements[$i] -as [System.Management.Automation.Language.CommandParameterAst]
            if (-not $el) { continue }

            # `-Name:$value` carries its argument on the parameter itself; `-Name $value`
            # carries it in the next element.
            #
            # The `-isnot [CommandParameterAst]` test below stops `-QueryParams -AutoPaginate`
            # from binding the following SWITCH as an argument. Be aware that it is currently
            # unobservable and cannot be mutation-killed: every branch that consumes $arg
            # re-validates it (`-as [VariableExpressionAst]`, `-is [StringConstant...]`), and a
            # CommandParameterAst fails all of them, so deleting this test changes no result.
            # It is kept because it makes the binding rule correct AT THE POINT the argument
            # is chosen rather than by luck downstream -- the next branch added here would
            # otherwise inherit a bug none of the existing tests can see. Do not read its
            # presence as evidence that a test covers it.
            $arg = $el.Argument
            if (-not $arg -and ($i + 1) -lt $elements.Count) {
                $nextElement = $elements[$i + 1]
                if ($nextElement -isnot [System.Management.Automation.Language.CommandParameterAst]) {
                    $arg = $nextElement
                }
            }
            if (-not $arg) { continue }

            switch ($el.ParameterName) {
                'Body' {
                    $var = $arg -as [System.Management.Automation.Language.VariableExpressionAst]
                    if ($var -and $var.VariablePath.UserPath -eq $TargetVariable -and -not $surfaces.Contains('Body')) {
                        $surfaces.Add('Body')
                    }
                }
                'QueryParams' {
                    $var = $arg -as [System.Management.Automation.Language.VariableExpressionAst]
                    if ($var -and $var.VariablePath.UserPath -eq $TargetVariable -and -not $surfaces.Contains('Query')) {
                        $surfaces.Add('Query')
                    }
                }
                'Method' {
                    if ($arg -is [System.Management.Automation.Language.StringConstantExpressionAst]) { $method = $arg.Value }
                }
                'Endpoint' {
                    if ($arg -is [System.Management.Automation.Language.StringConstantExpressionAst]) { $endpoint = $arg.Value }
                }
            }
        }

        foreach ($surface in $surfaces) {
            $landings.Add([PSCustomObject]@{ Surface = $surface; Method = $method; Endpoint = $endpoint })
        }
    }

    if ($landings.Count -eq 0) { return $null }

    $distinctSurfaces = [System.Collections.Generic.List[string]]::new()
    foreach ($landing in $landings) {
        if (-not $distinctSurfaces.Contains($landing.Surface)) { $distinctSurfaces.Add($landing.Surface) }
    }
    if ($distinctSurfaces.Count -ne 1) { return $null }

    # An empty string is the sentinel for 'this landing's operation could not be read'. It
    # participates in the distinctness test like any other value, which is what stops a
    # readable call from speaking for an unreadable one.
    #
    # The method is NOT case-folded on the way in. Folding would report a `-Method 'get'` as
    # 'GET' -- a literal that appears nowhere in the source -- and would quietly merge two
    # operations this function is supposed to be able to tell apart. List[string].Contains is
    # ordinal, so differing case reads as differing operations, which matches the ordinal
    # comparison Resolve-PfbWireLandingArbitration uses. Every -Method argument in Public/ is
    # upper case today (all 541 of them), so this costs nothing and forecloses a guess.
    $distinctOperations = [System.Collections.Generic.List[string]]::new()
    foreach ($landing in $landings) {
        $operation = ''
        if ($landing.Method -and $landing.Endpoint) {
            $operation = '{0}|{1}' -f $landing.Method, $landing.Endpoint
        }
        if (-not $distinctOperations.Contains($operation)) { $distinctOperations.Add($operation) }
    }

    $resolvedMethod = $null
    $resolvedEndpoint = $null
    if ($distinctOperations.Count -eq 1 -and $distinctOperations[0] -ne '') {
        $parts = $distinctOperations[0] -split '\|', 2
        $resolvedMethod = $parts[0]
        $resolvedEndpoint = $parts[1]
    }

    return [PSCustomObject]@{
        TargetVariable = $TargetVariable
        WireSurface    = $distinctSurfaces[0]
        Method         = $resolvedMethod
        Endpoint       = $resolvedEndpoint
    }
}

function Get-PfbEndpointForVariable {
    <#
    .SYNOPSIS
        Compatibility wrapper: the (Method, Endpoint) pair a payload variable reaches, or
        $null when that operation is not provably unique.
    .DESCRIPTION
        Delegates wholly to Get-PfbRequestRoleForVariable and keeps no independent notion of
        which variables are payloads -- the name switch this function used to carry is the
        defect issue #141 Task 3 removed, and reintroducing a copy of it here would restore
        the defect for every caller of this entry point.

        Still returns $null when the variable feeds zero Invoke-PfbApiRequest calls, or more
        than one call with a DIFFERENT (Method, Endpoint) pair -- Get-PfbNode's try/catch
        fallback reuses one $queryParams against 'nodes' then 'blades', which is correctly
        ambiguous rather than a case to force-pick one of. It now additionally returns $null
        when the surface itself is ambiguous, and resolves variables of any name.
    .OUTPUTS
        $null, or [PSCustomObject]@{ Method; Endpoint }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.FunctionDefinitionAst]$FunctionAst,

        [Parameter(Mandatory)]
        [string]$TargetVariable
    )

    $role = Get-PfbRequestRoleForVariable -FunctionAst $FunctionAst -TargetVariable $TargetVariable
    if (-not $role) { return $null }
    if (-not ($role.Method -and $role.Endpoint)) { return $null }

    return [PSCustomObject]@{ Method = $role.Method; Endpoint = $role.Endpoint }
}

function Get-PfbCmdletBodyInsertionTarget {
    <#
    .SYNOPSIS
        Insertion-point coordinates (drift-report-actionable-plan decision 12) for adding a
        typed parameter to -FunctionAst for a currently-missing body-property gap -- NEVER
        a diff/patch: a patch goes stale the moment the file is next touched and cannot see
        mutual-exclusivity/parameter-set constraints a human editing by hand must respect.
    .DESCRIPTION
        PayloadVariable/AssignmentStyle describe what THIS cmdlet's function body already
        does for its OTHER body fields, so a human adding one more matches the file's own
        convention instead of inventing a new one:
          - PayloadVariable is the literal variable name every `-Body <var>` argument on
            this function's Invoke-PfbApiRequest call(s) agrees on (never guessed when
            calls disagree, or an argument isn't a plain variable -- same "only ever ADD a
            resolution, never guess" discipline as every other function in this file).
          - If PayloadVariable is this cmdlet's OWN -Attributes parameter (the common
            "-Body $Attributes" shape for write cmdlets with no typed body parameters at
            all, e.g. Update-PfbCertificate), AssignmentStyle is 'attributesOnly': there is
            no existing per-field assignment line to imitate, because the caller supplies
            the whole hashtable directly -- adding a typed parameter here means introducing
            the FIRST one, not extending an established pattern.
          - Otherwise AssignmentStyle counts existing assignments INTO PayloadVariable using
            the same two literal-assignment idioms Get-PfbWireNameForParameter already
            recognizes: `$var['key'] = ...` (index form) vs. `$var = @{ 'key' = ... }`
            (hashtable-literal-initializer form, counted only when it declares at least ONE
            key/value pair -- an EMPTY `$var = @{}` bootstrap is the standard first line of
            the INDEX idiom too and must not be miscounted as 'literal'). Whichever has MORE
            occurrences in this function wins; a single non-empty literal initializer (even
            with zero further index-form assignments after it) still counts as 'literal',
            since it establishes every key at once. 'unknown' when PayloadVariable resolved
            but this function contains no assignment into it at all (e.g. populated by a
            private helper this AST-only inspector does not trace) -- surfaced rather than
            guessed, per this file's "never guess" convention.
        ParamBlockLine is the line of the LAST existing parameter in the param() block (or
        the block's own opening line if it declares none) -- inserting a new parameter
        after that line keeps it inside the existing block, below whatever
        identity/ParameterSet parameters the cmdlet already declares, matching every
        hand-written cmdlet in this module.
        HasAttributes reuses the exact detection Get-PfbCmdletParameterInventory already
        uses (`$_.Name.VariablePath.UserPath -eq 'Attributes'`), so this never disagrees
        with the cmdlet-inventory's own AttributesOnly/EscapeHatchOnly classification.
    .OUTPUTS
        [PSCustomObject]@{ ParamBlockLine; PayloadVariable; AssignmentStyle; HasAttributes }
        -- $null if -FunctionAst has no param() block at all (a function with no
        parameters cannot be an Invoke-PfbApiRequest-calling cmdlet in this module, so this
        should not occur for any cmdlet name sourced from Get-PfbModuleCalledEndpoints).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.FunctionDefinitionAst]$FunctionAst
    )

    $paramBlock = $FunctionAst.Body.ParamBlock
    if (-not $paramBlock) { return $null }

    $hasAttributesParam = [bool]($paramBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'Attributes' })

    $paramBlockLine = if ($paramBlock.Parameters.Count -gt 0) {
        ($paramBlock.Parameters | Select-Object -Last 1).Extent.EndLineNumber
    }
    else {
        $paramBlock.Extent.StartLineNumber
    }

    $bodyCalls = @($FunctionAst.FindAll({
                param($n)
                $n -is [System.Management.Automation.Language.CommandAst] -and
                $n.GetCommandName() -eq 'Invoke-PfbApiRequest'
            }, $true))

    $bodyVarNames = [System.Collections.Generic.List[string]]::new()
    foreach ($cmd in $bodyCalls) {
        $elements = $cmd.CommandElements
        for ($i = 0; $i -lt $elements.Count; $i++) {
            $el = $elements[$i]
            if ($el -isnot [System.Management.Automation.Language.CommandParameterAst]) { continue }
            if ($el.ParameterName -ne 'Body') { continue }
            $argExpr = if ($el.Argument) { $el.Argument } elseif ($i + 1 -lt $elements.Count) { $elements[$i + 1] } else { $null }
            $argVar = $argExpr -as [System.Management.Automation.Language.VariableExpressionAst]
            if ($argVar) { $bodyVarNames.Add($argVar.VariablePath.UserPath) }
        }
    }
    $distinctBodyVars = @($bodyVarNames | Select-Object -Unique)
    $payloadVariable = if ($distinctBodyVars.Count -eq 1) { $distinctBodyVars[0] } else { $null }

    $assignmentStyle = $null
    if ($payloadVariable -eq 'Attributes') {
        $assignmentStyle = 'attributesOnly'
    }
    elseif ($payloadVariable) {
        $indexAssignments = @($FunctionAst.FindAll({
                    param($n)
                    $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                    $n.Left -is [System.Management.Automation.Language.IndexExpressionAst] -and
                    ($n.Left.Target -as [System.Management.Automation.Language.VariableExpressionAst]) -and
                    ($n.Left.Target).VariablePath.UserPath -eq $payloadVariable
                }, $true))

        $literalCandidates = @($FunctionAst.FindAll({
                    param($n)
                    $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                    $n.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
                    $n.Left.VariablePath.UserPath -eq $payloadVariable
                }, $true))
        # An EMPTY hashtable-literal bootstrap (`$body = @{}`) does not count as 'literal'
        # style -- it establishes zero keys and is the standard first line of the 'index'
        # idiom too (`$body = @{}` followed by `$body['x'] = ...`). Only a literal that
        # actually declares at least one key/value pair reflects the "establish every key
        # at once" convention this style name describes.
        $literalAssignments = @($literalCandidates | Where-Object {
                $hash = (Resolve-PfbSingleExpression -Ast $_.Right) -as [System.Management.Automation.Language.HashtableAst]
                $hash -and $hash.KeyValuePairs.Count -gt 0
            })

        # A genuine TIE (indexAssignments.Count -eq literalAssignments.Count, both > 0)
        # falls through to this 'literal' branch silently -- there is no distinct 'tie'
        # outcome. Measured across the real high-confidence gap population: 274
        # attributesOnly / 95 unknown / 25 index / 1 literal / 7 unresolved, i.e. a true
        # tie is essentially unreachable in practice today. That is a measured-safe
        # observation about current data, not a design guarantee -- a future cmdlet could
        # legitimately produce a tie, and it would resolve to 'literal' without any flag
        # that the detection was actually ambiguous.
        if ($indexAssignments.Count -gt $literalAssignments.Count) { $assignmentStyle = 'index' }
        elseif ($literalAssignments.Count -gt 0) { $assignmentStyle = 'literal' }
        else { $assignmentStyle = 'unknown' }
    }

    return [PSCustomObject]@{
        ParamBlockLine  = $paramBlockLine
        PayloadVariable = $payloadVariable
        AssignmentStyle = $assignmentStyle
        HasAttributes   = $hasAttributesParam
    }
}

# Every value Get-PfbCmdletParameterInventory can put in a row's Surface field. Consumers
# branch on Surface EXHAUSTIVELY against this list rather than on "not Typed", so adding a
# value here is a compile-time-ish event: the consumers throw on a Surface they were never
# taught, instead of quietly folding it into whichever bucket their negation happened to
# catch. See tools/lib/PfbApiDriftTools.ps1's Get-PfbParameterCoverageGaps.
#
# The two NON-APPLICABLE values are the point of issue #141 Task 4. Before it, a parameter
# that is not a wire field AT ALL was indistinguishable from one whose wire field this
# AST-only resolver merely failed to find, so it lowered the drift report's confidence in
# every endpoint its cmdlet reaches -- doubt manufactured out of a parameter that could not
# have covered a gap in the first place.
$script:PfbParameterSurfaces = @(
    # The parameter's wire key is proven.
    'Typed'
    # Not proven, and the cmdlet exposes an -Attributes escape hatch the field may reach through.
    'AttributesOnly'
    # Not proven, and there is no escape hatch either -- a real gap in this resolver's reach.
    'TypedUnresolved'
    # NON-APPLICABLE: an audited request control, not a field. See $script:PfbNotWireParameters.
    'NotWireParameter'
    # NON-APPLICABLE: the declaring function issues no Invoke-PfbApiRequest call at all.
    'OutsideStandardRequest'
)

# The audited allowlist behind the 'NotWireParameter' surface: parameters that are proven, by
# reading the cmdlet, to steer the request rather than to appear in it. Every entry was read
# individually -- this is the one place in this file where a fact is asserted by a human
# rather than resolved from the AST, so it is deliberately an enumeration of exact
# 'Cmdlet|Parameter' identities and NOT a name pattern. `-Eradicate` and `-Force` as SHAPES
# mean nothing: New-PfbFileSystem's body switches are switches too, and a future
# `-Eradicate` that did become a wire field would be silently mis-filed by any rule keyed on
# the name. Tests/PfbCmdletParamTools.Tests.ps1 re-validates every entry against the real
# Public/ AST, so an entry that goes stale (its cmdlet or parameter disappears, or the
# parameter acquires a provable wire landing) fails the suite rather than rotting here.
#
#   Remove-PfbBucket|Eradicate               `if (-not $Eradicate)` selects which request to
#   Remove-PfbFileSystem|Eradicate           issue (destroy vs. eradicate) and gates the
#   Remove-PfbFileSystemSnapshot|Eradicate   ShouldProcess prompt; it is never keyed into a
#   Remove-PfbRealm|Eradicate                payload.
#   Remove-PfbServer|Eradicate
#   Remove-PfbFileSystemSession|Force        `if (-not $Force) { throw ... }` decides whether
#                                            any request is made at all.
$script:PfbNotWireParameters = @(
    'Remove-PfbBucket|Eradicate'
    'Remove-PfbFileSystem|Eradicate'
    'Remove-PfbFileSystemSession|Force'
    'Remove-PfbFileSystemSnapshot|Eradicate'
    'Remove-PfbRealm|Eradicate'
    'Remove-PfbServer|Eradicate'
)

function Get-PfbParameterSurfaceName {
    <#
    .SYNOPSIS
        Every legal value of an inventory row's Surface field, in classification order.
    .DESCRIPTION
        Exposed as a function rather than read as $script:PfbParameterSurfaces by consumers
        and tests, so the single source of truth survives being dot-sourced into a Pester
        scope where a $script:-qualified read resolves against the test file instead.
    .OUTPUTS
        [string[]]
    #>
    [CmdletBinding()]
    param()
    return @($script:PfbParameterSurfaces)
}

function Get-PfbNotWireParameterAllowlist {
    <#
    .SYNOPSIS
        The audited 'Cmdlet|Parameter' identities classified 'NotWireParameter'.
    .OUTPUTS
        [string[]], each entry '<Cmdlet>|<Parameter>'.
    #>
    [CmdletBinding()]
    param()
    return @($script:PfbNotWireParameters)
}

function Test-PfbFunctionMakesStandardRequest {
    <#
    .SYNOPSIS
        Whether a function issues at least one Invoke-PfbApiRequest call.
    .DESCRIPTION
        The structural fact behind the 'OutsideStandardRequest' surface. A function with no
        such call has no request for a parameter to land in, so NONE of its parameters can
        resolve -- New-PfbWireLanding refuses every candidate for want of a role -- and
        reporting all of them as "wire name unresolved" describes a failure that never
        happened. Connect-PfbArray, Set-PfbContext, Set-PfbCredential and Invoke-PfbInContext
        are the real shapes: connection, context and credential plumbing.

        Deliberately a plain "does this call exist" question and NOT an attempt to decide
        whether the cmdlet reaches the API by some other route. A cmdlet that reaches it
        through a Private/ helper would be misdescribed by the NAME of this surface, so the
        name says exactly what is measured: outside the standard request path.
    .OUTPUTS
        [bool]
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.FunctionDefinitionAst]$FunctionAst
    )

    $calls = @($FunctionAst.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.CommandAst] -and
        $node.GetCommandName() -eq 'Invoke-PfbApiRequest'
    }, $true))

    return ($calls.Count -gt 0)
}

function Get-PfbCmdletParameterInventory {
    <#
    .SYNOPSIS
        Inventories every typed parameter (excluding -Array/-Attributes themselves)
        across every function defined under -PublicDirectory.
    .OUTPUTS
        [PSCustomObject]@{ File; Line; Cmdlet; Parameter; HasValidateSet; ValidateSetValues;
        WireName; TargetVariable; WireSurface; Surface; Endpoint; Method }

        TargetVariable is the resolved assignment target -- the payload variable name, of
        whatever spelling -- or $null when the parameter proved landings through more than
        one. WireSurface is the coarse classification ('Query' | 'Body' | 'Unresolved') of
        the surface those landings agree on: the distinction between a query selector and a
        request-body property, which name shape alone cannot supply, and which is read from
        the -Body/-QueryParams argument the variable is passed as rather than from the
        variable's own name (see Get-PfbRequestRoleForVariable).

        Endpoint/Method are $null unless every landing of the parameter agrees on one
        literal Invoke-PfbApiRequest (method, endpoint) pair -- never guessed.

        Surface is one of Get-PfbParameterSurfaceName's five values, decided in that order:
          - 'Typed' -- a wire key was proven.
          - 'OutsideStandardRequest' -- the declaring function issues no Invoke-PfbApiRequest
            call, so there is no request for this parameter to have landed in. NON-APPLICABLE:
            not an unresolved wire name, and never a reason to doubt an endpoint's gap list.
          - 'NotWireParameter' -- an audited request control
            (Get-PfbNotWireParameterAllowlist). Also NON-APPLICABLE.
          - 'AttributesOnly' -- unresolved, but the cmdlet has an -Attributes escape hatch.
          - 'TypedUnresolved' -- unresolved with no escape hatch.
        The last two are the only ones that lower a consumer's confidence. Splitting the two
        non-applicable states out of them is issue #141 Task 4: before it, 34 real parameters
        that are not wire fields at all were reported as wire names this resolver had failed
        to find, and each one cast doubt on every endpoint its cmdlet reaches.

        Line is the parameter's own declaration line ($p.Extent.StartLineNumber),
        alongside the File it already carried -- so a consumer reporting on a
        non-'Typed' Surface (Get-PfbParameterCoverageGaps's `confidence.unresolvedParameters`
        in tools/lib/PfbApiDriftTools.ps1) can point a reader at an exact file:line rather
        than making them search the whole file for the parameter name.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PublicDirectory
    )

    $results = [System.Collections.Generic.List[object]]::new()
    # Belt-and-braces only -- the load-bearing sort is on the records at the end of this
    # function (issue #85). This one keeps the walk itself, and so any intermediate debugging
    # output, stable too.
    $files = @(Get-ChildItem -Path $PublicDirectory -Filter '*.ps1' -Recurse -File | Sort-Object -Property FullName -Culture '')

    foreach ($file in $files) {
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)

        $functionAsts = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)

        foreach ($funcAst in $functionAsts) {
            $paramBlock = $funcAst.Body.ParamBlock
            if (-not $paramBlock) { continue }

            $hasAttributesParam = [bool]($paramBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'Attributes' })
            # Hoisted out of the parameter loop: it is a fact about the FUNCTION, and asking
            # it per parameter would re-walk the whole function body once per declaration.
            $makesStandardRequest = Test-PfbFunctionMakesStandardRequest -FunctionAst $funcAst

            foreach ($p in $paramBlock.Parameters) {
                $paramName = $p.Name.VariablePath.UserPath
                if ($paramName -in @('Array', 'Attributes')) { continue }

                $validateSetValues = $null
                foreach ($attr in $p.Attributes) {
                    if ($attr -is [System.Management.Automation.Language.AttributeAst] -and $attr.TypeName.Name -eq 'ValidateSet') {
                        $validateSetValues = @($attr.PositionalArguments | ForEach-Object { $_.SafeGetValue() })
                    }
                }

                # Boolean-like, not switch-only: a [bool] or [Nullable[bool]] reaches a wire key
                # through the same presence-keyed literal and if-expression shapes a [switch]
                # does. [Nullable[bool]]'s StaticType is System.Nullable`1[[System.Boolean,...]],
                # so compare against the constructed type rather than string-matching its name.
                $isBooleanLike = $p.StaticType -in @(
                    [System.Management.Automation.SwitchParameter]
                    [bool]
                    [System.Nullable[bool]]
                )
                # Resolve-PfbParameterWireLanding, not Get-PfbWireNameForParameter: the retry
                # below must fire on SILENCE only, and the arbitrated value alone cannot tell
                # silence from an abstention (both are $null). Retrying after an abstention
                # consults a FIFTH source on behalf of a parameter whose own evidence had just
                # been ruled contradictory, and republishes it with a confident name -- the
                # exact laundering the tier stickiness exists to prevent, escaping through the
                # caller. Measured before the fix: a parameter written to both $q['alpha'] and
                # $q['beta'] AND fed to an accumulator keyed at $q['names'] emitted a Typed row
                # naming 'names'.
                $primary = Resolve-PfbParameterWireLanding -FunctionAst $funcAst -ParameterName $paramName -IsBooleanLikeParameter:$isBooleanLike
                $wireInfo = $primary.Resolution
                if ($primary.Landings.Count -eq 0) {
                    $accumulatorName = Find-PfbAccumulatorVariable -FunctionAst $funcAst -ParameterName $paramName
                    if ($accumulatorName) {
                        $wireInfo = Get-PfbWireNameForParameter -FunctionAst $funcAst -ParameterName $accumulatorName
                    }
                }
                $wireName = if ($wireInfo) { $wireInfo.WireName } else { $null }

                # Classification order matters, and is asserted by the Surface ladder tests.
                # The two NON-APPLICABLE states are tested BEFORE the two unresolved ones
                # because they are answers, not failures: 'OutsideStandardRequest' first
                # because it is a property of the whole function and subsumes every parameter
                # on it, then the audited per-parameter allowlist. 'Typed' still outranks both
                # -- a proven landing is a proven landing, and the allowlist is re-validated
                # against the real AST by the suite precisely so an entry that acquires one
                # fails loudly rather than being shadowed here.
                $surface = if ($wireName) { 'Typed' }
                elseif (-not $makesStandardRequest) { 'OutsideStandardRequest' }
                elseif ($script:PfbNotWireParameters -contains ('{0}|{1}' -f $funcAst.Name, $paramName)) { 'NotWireParameter' }
                elseif ($hasAttributesParam) { 'AttributesOnly' }
                else { 'TypedUnresolved' }

                # Surface, method and endpoint all arrive already arbitrated from
                # Get-PfbWireNameForParameter, which resolves them from the request arguments
                # of the calls the payload variable is actually passed to (issue #141 Task 3).
                # They are deliberately NOT re-derived here from TargetVariable: that was the
                # retired name gate, and a parameter landing through more than one payload
                # variable has no single TargetVariable to re-derive them from.
                $targetVariable = if ($wireInfo) { $wireInfo.TargetVariable } else { $null }
                $wireSurface = if ($wireInfo) { $wireInfo.WireSurface } else { 'Unresolved' }

                $results.Add([PSCustomObject]@{
                    File              = $file.FullName
                    Line              = $p.Extent.StartLineNumber
                    Cmdlet            = $funcAst.Name
                    Parameter         = $paramName
                    HasValidateSet    = [bool]$validateSetValues
                    ValidateSetValues = $validateSetValues
                    WireName          = $wireName
                    TargetVariable    = $targetVariable
                    WireSurface       = $wireSurface
                    Surface           = $surface
                    Endpoint          = if ($wireInfo) { $wireInfo.Endpoint } else { $null }
                    Method            = if ($wireInfo) { $wireInfo.Method } else { $null }
                })
            }
        }
    }

    # Sort at EMIT, not merely at input (issue #85). $files above is an unsorted recursive
    # Get-ChildItem, whose order is filesystem-dependent -- and this list is verbatim the
    # emit order of `entries`/`attributesOnly`/`typedUnresolved` in
    # Reports/PfbFieldCmdletMap.json and of every markdown row in
    # Reports/PfbFieldCmdletMapping.md (tools/Build-PfbFieldCmdletMap.ps1:76-95, :137-148).
    # Regenerating on a Linux runner instead of a Windows workstation therefore produced a
    # 10,218-line diff with zero semantic change: all 2015 entries moved, not one changed
    # content, and the two files were even identical in byte LENGTH.
    #
    # Sorting the file list alone would be the fragile fix -- FullName carries
    # platform-specific separators -- so the canonical order is imposed on the records
    # themselves. -Culture '' is the invariant culture: without it the runner's locale
    # could reintroduce the very divergence this removes. File/Line are tiebreakers only,
    # for the (not currently occurring) case of one function name declared twice.
    return @($results | Sort-Object -Property Cmdlet, Parameter, File, Line -Culture '')
}

function Get-PfbInventoryTupleSet {
    <#
    .SYNOPSIS
        Reduces an inventory to the row-identity -> resolution-tuple map the regression gate
        compares.
    .DESCRIPTION
        Identity is 'Cmdlet|Parameter'; the tuple is
        'Surface|WireName|WireSurface|Method|Endpoint', with $null rendered as the empty
        string. TargetVariable is deliberately NOT in the tuple: it names the local variable a
        landing came through, so it changes whenever the resolver's internal accounting does
        (issue #141 Task 3 nulled it for Remove-PfbFileSystem -DeleteLinkOnEradication, which
        now proves two landings) without any consumer reading it and without one byte of the
        request changing. File and Line are out for the same reason in reverse -- they move
        whenever anyone edits a cmdlet, and would swamp a real regression in noise.
    .OUTPUTS
        [System.Collections.Generic.Dictionary[string,string]], ordinal-keyed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Inventory
    )

    $set = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
    foreach ($row in $Inventory) {
        if ($null -eq $row) { continue }
        $key = '{0}|{1}' -f $row.Cmdlet, $row.Parameter
        $set[$key] = '{0}|{1}|{2}|{3}|{4}' -f $row.Surface, $row.WireName, $row.WireSurface, $row.Method, $row.Endpoint
    }
    return $set
}

function Compare-PfbInventoryTupleSet {
    <#
    .SYNOPSIS
        The row-level regression gate for a resolver change: every inventory row that
        disappeared, and every row whose resolution tuple moved without being declared.
    .DESCRIPTION
        Issue #141 Task 4 exists because a resolver change can WITHDRAW a resolution as
        easily as add one, and the totals do not show it -- Update-PfbBucketAuditFilter
        -BucketName went from a confident 'bucket_names' to unresolved while the Typed count
        went UP, and the only thing that caught it was a human diffing rows by hand inside a
        code review. This makes that diff runnable.

        A change is tolerated only when it is DECLARED, and a declaration must name the exact
        before and after tuple, not just the row: "this row is expected to move" would let any
        subsequent move through unseen. Comparison is ordinal throughout, matching
        Resolve-PfbWireLandingArbitration -- 'names' and 'Names' are different answers.

        A declaration that matched nothing is reported in UnusedDeclaration and fails the
        gate. A stale declaration is how a gate rots into a rubber stamp: it silently pre-
        authorises whatever change later happens to land on that row.

        Added rows are reported but never fail: a new cmdlet legitimately adds rows, and this
        gate is about what the resolver stopped knowing.
    .PARAMETER DeclaredChange
        Objects with Key ('<Cmdlet>|<Parameter>'), From and To (tuple strings, as
        Get-PfbInventoryTupleSet renders them).
    .OUTPUTS
        [PSCustomObject]@{ Removed; Added; Changed; Undeclared; UnusedDeclaration; IsClean }.
        Removed/Added are [string[]] of row identities. Changed/Undeclared are
        [PSCustomObject]@{ Key; From; To }[]. IsClean is $true only when nothing was removed,
        every change was declared, and every declaration was used.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Baseline,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Current,

        [AllowEmptyCollection()]
        [object[]]$DeclaredChange = @()
    )

    $baselineSet = Get-PfbInventoryTupleSet -Inventory $Baseline
    $currentSet = Get-PfbInventoryTupleSet -Inventory $Current

    $removed = [System.Collections.Generic.List[string]]::new()
    $changed = [System.Collections.Generic.List[object]]::new()
    foreach ($key in $baselineSet.get_Keys()) {
        if (-not $currentSet.ContainsKey($key)) { $removed.Add($key); continue }
        if (-not [string]::Equals($baselineSet[$key], $currentSet[$key], [System.StringComparison]::Ordinal)) {
            $changed.Add([PSCustomObject]@{ Key = $key; From = $baselineSet[$key]; To = $currentSet[$key] })
        }
    }

    $added = [System.Collections.Generic.List[string]]::new()
    foreach ($key in $currentSet.get_Keys()) {
        if (-not $baselineSet.ContainsKey($key)) { $added.Add($key) }
    }

    $declarations = @($DeclaredChange | Where-Object { $null -ne $_ })
    $matchedDeclaration = [System.Collections.Generic.List[object]]::new()
    $undeclared = [System.Collections.Generic.List[object]]::new()
    foreach ($change in $changed) {
        $hit = $null
        foreach ($declaration in $declarations) {
            if ([string]::Equals([string]$declaration.Key, $change.Key, [System.StringComparison]::Ordinal) -and
                [string]::Equals([string]$declaration.From, $change.From, [System.StringComparison]::Ordinal) -and
                [string]::Equals([string]$declaration.To, $change.To, [System.StringComparison]::Ordinal)) {
                $hit = $declaration
                break
            }
        }
        if ($hit) { $matchedDeclaration.Add($hit) } else { $undeclared.Add($change) }
    }

    $unusedDeclaration = [System.Collections.Generic.List[object]]::new()
    foreach ($declaration in $declarations) {
        if (-not $matchedDeclaration.Contains($declaration)) { $unusedDeclaration.Add($declaration) }
    }

    return [PSCustomObject]@{
        Removed           = $removed.ToArray()
        Added             = $added.ToArray()
        Changed           = $changed.ToArray()
        Undeclared        = $undeclared.ToArray()
        UnusedDeclaration = $unusedDeclaration.ToArray()
        IsClean           = ($removed.Count -eq 0 -and $undeclared.Count -eq 0 -and $unusedDeclaration.Count -eq 0)
    }
}
