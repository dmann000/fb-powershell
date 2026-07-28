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
        Test-PfbAssignmentGuardedBySwitch's caller requires before trusting a literal
        string assignment as switch-derived.
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
            'literal'               -- ONLY for a [switch] whose mere presence is keyed to a
                                       hardcoded string, and only inside an `if ($Param)` guard
        Refused (correctly, per this file's "never guess" contract): anything else, e.g.
        `"$Param"`. The array-projection shape `@($Param | ForEach-Object { @{ name = $_ } })`
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

        [switch]$IsSwitchParameter
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

    if ($IsSwitchParameter -and $expr -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
        if (Test-PfbAssignmentGuardedBySwitch -Assignment $ValueAst -ParameterName $ParameterName) { return $true }
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
            Find-PfbAccumulatorVariable retry.

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
        ByParameterName rule, only reads plain variable arguments, and returns $null if two
        helper calls in the same function disagree on the (WireName, TargetVariable) pair.
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
                if ($argVar) { $argumentVariables[$el.ParameterName] = $argVar.VariablePath.UserPath }
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

function Get-PfbWireNameForParameter {
    <#
    .SYNOPSIS
        Finds the request-body or query-string key a given parameter is assigned to
        inside a cmdlet function body, or $null if no simple assignment pattern matches.
    .OUTPUTS
        $null, or [PSCustomObject]@{ WireName; TargetVariable } -- TargetVariable is the
        literal variable name the assignment targeted ('body' or 'queryParams'), needed
        by Get-PfbEndpointForVariable to find the specific Invoke-PfbApiRequest call(s)
        that variable is later passed to.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.FunctionDefinitionAst]$FunctionAst,

        [Parameter(Mandatory)]
        [string]$ParameterName,

        [switch]$IsSwitchParameter
    )

    $assignments = $FunctionAst.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $node.Left -is [System.Management.Automation.Language.IndexExpressionAst]
    }, $true)

    foreach ($assign in $assignments) {
        $indexExpr = $assign.Left
        $targetVar = $indexExpr.Target -as [System.Management.Automation.Language.VariableExpressionAst]
        if (-not $targetVar) { continue }
        if ($targetVar.VariablePath.UserPath -notin @('body', 'queryParams')) { continue }

        $keyExpr = $indexExpr.Index -as [System.Management.Automation.Language.StringConstantExpressionAst]
        if (-not $keyExpr) { continue }

        if (Test-PfbWireValueIsParameter -ValueAst $assign.Right -ParameterName $ParameterName -IsSwitchParameter:$IsSwitchParameter) {
            return [PSCustomObject]@{
                WireName       = $keyExpr.Value
                TargetVariable = $targetVar.VariablePath.UserPath
            }
        }
    }

    # Second idiom: the whole hashtable is built as a LITERAL initializer rather than keyed
    # into afterwards -- `$queryParams = @{ 'names' = $Name }`, the dominant shape across
    # New-Pfb*/Remove-Pfb*/Update-Pfb* (New-PfbApiClient, New-PfbAlertWatcher,
    # New-PfbObjectStoreAccount, the whole Policy/*Rule family, ...). Runs after the index
    # form, not instead of it: a cmdlet routinely does both (literal initializer for its
    # -Name, then `$body['x'] = $X` lines), and both key sets must resolve.
    $literalMatch = Get-PfbHashtableLiteralWireNameForParameter -FunctionAst $FunctionAst -ParameterName $ParameterName -IsSwitchParameter:$IsSwitchParameter
    if ($literalMatch) { return $literalMatch }

    # Third idiom: a nested single-key REFERENCE OBJECT -- `$body['account'] = @{ name =
    # $Account }` -- whose wire field is the OUTER key. Runs strictly after both direct
    # forms above so it can only ever add a resolution, never rename one: a parameter that
    # already resolved via a direct assignment returned before reaching here.
    $nestedMatch = Get-PfbNestedReferenceWireNameForParameter -FunctionAst $FunctionAst -ParameterName $ParameterName -IsSwitchParameter:$IsSwitchParameter
    if ($nestedMatch) { return $nestedMatch }

    # No literal assignment of any shape in this function body -- but the parameter may
    # still reach the wire through the shared Private/Add-PfbCommonQueryParams.ps1 helper,
    # which performs the assignment on the cmdlet's behalf (issue #32/#33). Deliberately
    # LAST: a cmdlet whose Name/Id-equivalent maps to a non-generic key (policy_names,
    # file_system_names, ...) kept its own explicit line after the helper call, and that
    # literal must win.
    return Get-PfbCommonQueryParamHelperWireName -FunctionAst $FunctionAst -ParameterName $ParameterName
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
        $null, or [PSCustomObject]@{ WireName; TargetVariable } -- same shape as
        Get-PfbWireNameForParameter.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.FunctionDefinitionAst]$FunctionAst,

        [Parameter(Mandatory)]
        [string]$ParameterName,

        [switch]$IsSwitchParameter
    )

    $assignments = @($FunctionAst.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $node.Left -is [System.Management.Automation.Language.VariableExpressionAst]
    }, $true))

    foreach ($assign in $assignments) {
        $targetVar = $assign.Left -as [System.Management.Automation.Language.VariableExpressionAst]
        if ($targetVar.VariablePath.UserPath -notin @('body', 'queryParams')) { continue }

        $hashtable = (Resolve-PfbSingleExpression -Ast $assign.Right) -as [System.Management.Automation.Language.HashtableAst]
        if (-not $hashtable) { continue }

        foreach ($pair in $hashtable.KeyValuePairs) {
            # KeyValuePairs entries are Tuple<ExpressionAst, StatementAst>. Keys in this repo
            # are written both quoted ('names') and bare (destroyed); StringConstantExpressionAst
            # covers both and exposes the unquoted text as .Value.
            $keyExpr = $pair.Item1 -as [System.Management.Automation.Language.StringConstantExpressionAst]
            if (-not $keyExpr) { continue }

            if (Test-PfbWireValueIsParameter -ValueAst $pair.Item2 -ParameterName $ParameterName -IsSwitchParameter:$IsSwitchParameter) {
                return [PSCustomObject]@{
                    WireName       = $keyExpr.Value
                    TargetVariable = $targetVar.VariablePath.UserPath
                }
            }
        }
    }

    return $null
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
          - the target variable must be body/queryParams (an intermediate like
            New-PfbFileSystem's $nfsBody is not traceable to an Invoke-PfbApiRequest call);
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
        $null, or [PSCustomObject]@{ WireName; TargetVariable } -- same shape as
        Get-PfbWireNameForParameter.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.FunctionDefinitionAst]$FunctionAst,

        [Parameter(Mandatory)]
        [string]$ParameterName,

        [switch]$IsSwitchParameter
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
        return (Test-PfbWireValueIsParameter -ValueAst $innerPair.Item2 -ParameterName $ParameterName -IsSwitchParameter:$IsSwitchParameter)
    }

    $assignments = @($FunctionAst.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.AssignmentStatementAst]
    }, $true))

    # Index form first, then the literal-initializer form, mirroring the order
    # Get-PfbWireNameForParameter uses for the direct shapes.
    foreach ($assign in $assignments) {
        $indexExpr = $assign.Left -as [System.Management.Automation.Language.IndexExpressionAst]
        if (-not $indexExpr) { continue }
        $targetVar = $indexExpr.Target -as [System.Management.Automation.Language.VariableExpressionAst]
        if (-not $targetVar) { continue }
        if ($targetVar.VariablePath.UserPath -notin @('body', 'queryParams')) { continue }

        $keyExpr = $indexExpr.Index -as [System.Management.Automation.Language.StringConstantExpressionAst]
        if (-not $keyExpr) { continue }

        if (& $isReferenceObjectFor $assign.Right) {
            return [PSCustomObject]@{
                WireName       = $keyExpr.Value
                TargetVariable = $targetVar.VariablePath.UserPath
            }
        }
    }

    foreach ($assign in $assignments) {
        $targetVar = $assign.Left -as [System.Management.Automation.Language.VariableExpressionAst]
        if (-not $targetVar) { continue }
        if ($targetVar.VariablePath.UserPath -notin @('body', 'queryParams')) { continue }

        $hashtable = (Resolve-PfbSingleExpression -Ast $assign.Right) -as [System.Management.Automation.Language.HashtableAst]
        if (-not $hashtable) { continue }

        foreach ($pair in $hashtable.KeyValuePairs) {
            $keyExpr = $pair.Item1 -as [System.Management.Automation.Language.StringConstantExpressionAst]
            if (-not $keyExpr) { continue }

            if (& $isReferenceObjectFor $pair.Item2) {
                return [PSCustomObject]@{
                    WireName       = $keyExpr.Value
                    TargetVariable = $targetVar.VariablePath.UserPath
                }
            }
        }
    }

    return $null
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

function Get-PfbEndpointForVariable {
    <#
    .SYNOPSIS
        Finds the (Method, Endpoint) pair a body/queryParams variable is passed to via
        Invoke-PfbApiRequest -Body/-QueryParams within a function, IF every such call
        agrees on exactly one (Method, Endpoint) pair.
    .DESCRIPTION
        Never guesses: returns $null when the variable feeds zero Invoke-PfbApiRequest
        calls, or more than one call with a DIFFERENT (Method, Endpoint) pair (e.g.
        Get-PfbNode's try/catch fallback that reuses the same $queryParams against two
        genuinely different endpoints, 'nodes' then 'blades' -- correctly ambiguous,
        not a case to force-pick one of). Only literal, unquoted-bareword-or-quoted-
        string -Method/-Endpoint arguments are recognized, matching the exclusively
        literal style every cmdlet in this repo actually uses for both.
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

    $targetParamName = switch ($TargetVariable) {
        'body' { 'Body' }
        'queryParams' { 'QueryParams' }
        default { $null }
    }
    if (-not $targetParamName) { return $null }

    $commands = $FunctionAst.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.CommandAst] -and
        $node.GetCommandName() -eq 'Invoke-PfbApiRequest'
    }, $true)

    $pairs = [System.Collections.Generic.List[string]]::new()

    foreach ($cmd in $commands) {
        $elements = $cmd.CommandElements
        $usesVariable = $false
        $method = $null
        $endpoint = $null

        for ($i = 0; $i -lt $elements.Count; $i++) {
            $el = $elements[$i]
            if ($el -isnot [System.Management.Automation.Language.CommandParameterAst]) { continue }
            $next = if ($i + 1 -lt $elements.Count) { $elements[$i + 1] } else { $null }
            if (-not $next) { continue }

            if ($el.ParameterName -eq $targetParamName -and
                $next -is [System.Management.Automation.Language.VariableExpressionAst] -and
                $next.VariablePath.UserPath -eq $TargetVariable) {
                $usesVariable = $true
            }
            elseif ($el.ParameterName -eq 'Method' -and $next -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                $method = $next.Value
            }
            elseif ($el.ParameterName -eq 'Endpoint' -and $next -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                $endpoint = $next.Value
            }
        }

        if ($usesVariable -and $method -and $endpoint) {
            $pairs.Add("$($method.ToUpperInvariant())|$endpoint")
        }
    }

    $distinct = @($pairs | Select-Object -Unique)
    if ($distinct.Count -ne 1) { return $null }

    $parts = $distinct[0] -split '\|', 2
    return [PSCustomObject]@{ Method = $parts[0]; Endpoint = $parts[1] }
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

function Get-PfbCmdletParameterInventory {
    <#
    .SYNOPSIS
        Inventories every typed parameter (excluding -Array/-Attributes themselves)
        across every function defined under -PublicDirectory.
    .OUTPUTS
        [PSCustomObject]@{ File; Line; Cmdlet; Parameter; HasValidateSet; ValidateSetValues;
        WireName; Surface; Endpoint; Method }

        Endpoint/Method are $null unless the parameter's wire-name assignment resolved
        to exactly one Invoke-PfbApiRequest call's endpoint (see
        Get-PfbEndpointForVariable) -- never guessed.

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
    $files = Get-ChildItem -Path $PublicDirectory -Filter '*.ps1' -Recurse -File

    foreach ($file in $files) {
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)

        $functionAsts = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)

        foreach ($funcAst in $functionAsts) {
            $paramBlock = $funcAst.Body.ParamBlock
            if (-not $paramBlock) { continue }

            $hasAttributesParam = [bool]($paramBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'Attributes' })

            foreach ($p in $paramBlock.Parameters) {
                $paramName = $p.Name.VariablePath.UserPath
                if ($paramName -in @('Array', 'Attributes')) { continue }

                $validateSetValues = $null
                foreach ($attr in $p.Attributes) {
                    if ($attr -is [System.Management.Automation.Language.AttributeAst] -and $attr.TypeName.Name -eq 'ValidateSet') {
                        $validateSetValues = @($attr.PositionalArguments | ForEach-Object { $_.SafeGetValue() })
                    }
                }

                $isSwitch = $p.StaticType -eq [System.Management.Automation.SwitchParameter]
                $wireInfo = Get-PfbWireNameForParameter -FunctionAst $funcAst -ParameterName $paramName -IsSwitchParameter:$isSwitch
                if (-not $wireInfo) {
                    $accumulatorName = Find-PfbAccumulatorVariable -FunctionAst $funcAst -ParameterName $paramName
                    if ($accumulatorName) {
                        $wireInfo = Get-PfbWireNameForParameter -FunctionAst $funcAst -ParameterName $accumulatorName
                    }
                }
                $wireName = if ($wireInfo) { $wireInfo.WireName } else { $null }

                $endpointInfo = if ($wireInfo) { Get-PfbEndpointForVariable -FunctionAst $funcAst -TargetVariable $wireInfo.TargetVariable } else { $null }

                $surface = if ($wireName) { 'Typed' }
                elseif ($hasAttributesParam) { 'AttributesOnly' }
                else { 'TypedUnresolved' }

                $results.Add([PSCustomObject]@{
                    File              = $file.FullName
                    Line              = $p.Extent.StartLineNumber
                    Cmdlet            = $funcAst.Name
                    Parameter         = $paramName
                    HasValidateSet    = [bool]$validateSetValues
                    ValidateSetValues = $validateSetValues
                    WireName          = $wireName
                    Surface           = $surface
                    Endpoint          = if ($endpointInfo) { $endpointInfo.Endpoint } else { $null }
                    Method            = if ($endpointInfo) { $endpointInfo.Method } else { $null }
                })
            }
        }
    }

    return $results
}
