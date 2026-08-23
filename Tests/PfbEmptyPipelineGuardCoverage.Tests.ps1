#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

# Issue #121. The empty-pipeline guard is a 130-file generated population, and a generated
# population decays silently: a new collect-in-process cmdlet arrives without the guard, or an
# existing guard drifts into a scriptblock or onto the wrong hashtable and keeps passing the
# generator's own AlreadyPresent recognizer (tools/Update-PfbEmptyPipelineGuards.ps1) because
# that recognizer matches the command name anywhere in the end block's subtree.
#
# These are AST tripwires, not behaviour tests. They run in CI on every change; the generator
# only runs when somebody invokes it, so this is the durable gate of the two.

BeforeAll {
    $script:moduleRoot = Split-Path -Parent $PSScriptRoot
    $script:publicRoot = Join-Path $script:moduleRoot 'Public'

    # Walk a node's parent chain up to (and excluding) the owning NamedBlockAst, reporting
    # whether any ScriptBlockExpressionAst sits in between. A statement inside a scriptblock
    # returns from the scriptblock, not from the cmdlet.
    function Test-PfbNestedInScriptBlockExpression {
        param(
            [System.Management.Automation.Language.Ast]$Node,
            [System.Management.Automation.Language.Ast]$Stop
        )

        $cursor = $Node.Parent
        while ($null -ne $cursor -and -not [object]::ReferenceEquals($cursor, $Stop)) {
            if ($cursor -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
                return $true
            }
            $cursor = $cursor.Parent
        }
        return $false
    }

    # The variable name a CommandAst passes to a named parameter, or $null when the argument is
    # not a bare variable expression (or the parameter is absent).
    function Get-PfbParameterVariableName {
        param(
            [System.Management.Automation.Language.CommandAst]$Command,
            [string]$ParameterName
        )

        $elements = @($Command.CommandElements)
        for ($i = 0; $i -lt $elements.Count; $i++) {
            $element = $elements[$i]
            if ($element -isnot [System.Management.Automation.Language.CommandParameterAst]) { continue }
            if ($element.ParameterName -ne $ParameterName) { continue }

            # -Param:$value packs the argument onto the CommandParameterAst itself.
            $argument = $element.Argument
            if ($null -eq $argument -and ($i + 1) -lt $elements.Count) {
                $argument = $elements[$i + 1]
            }
            if ($argument -is [System.Management.Automation.Language.VariableExpressionAst]) {
                return $argument.VariablePath.UserPath
            }
            return $null
        }
        return $null
    }

    # Issue #128. Walk the guard's parent chain to the owning end block and report the first
    # CONDITIONALLY EXECUTED block it sits inside, or $null.
    #
    # Not "is it a direct child of the end block" -- that is too strict. A try body and a finally
    # body are StatementBlockAst too and ALWAYS execute, so a guard inside a try is legal and
    # protective. The hazard is specifically a block that may not run: an if/elseif/else clause
    # body, a loop body, a switch clause, a catch, or a trap.
    #
    # THE TRAP: every one of the 130 guards has an IfStatementAst directly above it because
    # `if (Test-PfbEmptyPipelineRead ...) { return }` IS the shipped shape. The leading if condition
    # (Clauses[0].Item1) is unconditional, but an elseif condition (Clauses[i].Item1 for i > 0) is
    # conditional on every earlier clause being false. Clause bodies (Item2) are hazards too.
    #
    # SwitchStatementAst derives from LabeledStatementAst, NOT LoopStatementAst, so it needs its
    # own branch -- a chain that only handles LoopStatementAst misses every switch.
    function Get-PfbConditionalAncestorKind {
        param(
            [System.Management.Automation.Language.Ast]$Node,
            [System.Management.Automation.Language.Ast]$Stop
        )

        $child = $Node
        $cursor = $Node.Parent
        while ($null -ne $cursor) {
            if ([object]::ReferenceEquals($cursor, $Stop)) { break }

            $hazard = $null

            if ($cursor -is [System.Management.Automation.Language.IfStatementAst]) {
                for ($i = 0; $i -lt $cursor.Clauses.Count; $i++) {
                    $clause = $cursor.Clauses[$i]
                    if ($i -gt 0 -and [object]::ReferenceEquals($clause.Item1, $child)) {
                        return 'elseif-condition'
                    }
                    if ([object]::ReferenceEquals($clause.Item2, $child)) {
                        return 'if-clause-body'
                    }
                }
                if ($null -ne $cursor.ElseClause -and
                    [object]::ReferenceEquals($cursor.ElseClause, $child)) {
                    $hazard = 'else-body'
                }
            }
            elseif ($cursor -is [System.Management.Automation.Language.LoopStatementAst]) {
                if ([object]::ReferenceEquals($cursor.Body, $child)) { $hazard = 'loop-body' }
            }
            elseif ($cursor -is [System.Management.Automation.Language.SwitchStatementAst]) {
                foreach ($clause in $cursor.Clauses) {
                    if ([object]::ReferenceEquals($clause.Item2, $child)) {
                        return 'switch-clause'
                    }
                }
                if ($null -ne $cursor.Default -and
                    [object]::ReferenceEquals($cursor.Default, $child)) {
                    $hazard = 'switch-default'
                }
            }
            elseif ($cursor -is [System.Management.Automation.Language.CatchClauseAst]) {
                $hazard = 'catch-body'
            }
            elseif ($cursor -is [System.Management.Automation.Language.TrapStatementAst]) {
                $hazard = 'trap-body'
            }

            if ($null -ne $hazard) { return $hazard }

            $child = $cursor
            $cursor = $cursor.Parent
        }
        return $null
    }

    # Issue #126. Does the function carry a mandatory parameter on EVERY path a caller can take?
    #
    # True when either (a) some mandatory parameter declares no ParameterSetName, so it applies to
    # all sets, or (b) every declared parameter set name has at least one mandatory parameter.
    # A function with no parameter sets and no set-less mandatory parameter is $false -- a bare
    # call binds successfully, which is exactly the property being tested for.
    #
    # `[Parameter(Mandatory)]` omits the expression, so ExpressionOmitted has to be treated as
    # $true; the generated tree uses that form as well as `Mandatory = $true`.
    function Test-PfbMandatoryInEveryParameterSet {
        param(
            [System.Management.Automation.Language.FunctionDefinitionAst]$Function
        )

        $paramBlock = $Function.Body.ParamBlock
        if ($null -eq $paramBlock) { return $false }

        $declaredSets = @()
        $mandatorySets = @()
        $mandatoryInAllSets = $false

        foreach ($parameter in $paramBlock.Parameters) {
            foreach ($attribute in $parameter.Attributes) {
                if ($attribute -isnot [System.Management.Automation.Language.AttributeAst]) { continue }
                if ($attribute.TypeName.Name -notin @('Parameter', 'ParameterAttribute')) { continue }

                $isMandatory = $false
                $setName = $null

                foreach ($named in $attribute.NamedArguments) {
                    if ($named.ArgumentName -eq 'Mandatory') {
                        if ($named.ExpressionOmitted) { $isMandatory = $true }
                        elseif ($named.Argument.Extent.Text -eq '$true') { $isMandatory = $true }
                    }
                    elseif ($named.ArgumentName -eq 'ParameterSetName') {
                        if (-not $named.ExpressionOmitted -and
                            $named.Argument -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                            $setName = $named.Argument.Value
                        }
                    }
                }

                if ($null -ne $setName -and $setName -notin $declaredSets) {
                    $declaredSets += $setName
                }
                if ($isMandatory) {
                    if ($null -eq $setName) { $mandatoryInAllSets = $true }
                    elseif ($setName -notin $mandatorySets) { $mandatorySets += $setName }
                }
            }
        }

        if ($mandatoryInAllSets) { return $true }
        if ($declaredSets.Count -eq 0) { return $false }
        foreach ($set in $declaredSets) {
            if ($set -notin $mandatorySets) { return $false }
        }
        return $true
    }

    # Issue #128. Extracted from the file-walk loop so the same computation can be run against a
    # synthetic fixture. That is not tidiness: #128 requires proving the new dominance rail is not
    # duplicating GuardReturns, which means evaluating the EXISTING properties on the mutant, and
    # GuardReturns is twenty lines of logic that must not be duplicated into the proof.
    function Get-PfbGuardRecord {
        param(
            [System.Management.Automation.Language.FunctionDefinitionAst]$Function,
            [string]$File
        )

        $endBlock = $Function.Body.EndBlock
        $processBlock = $Function.Body.ProcessBlock
        $hasNamedEnd = ($null -ne $endBlock -and -not $endBlock.Unnamed)
        $hasProcess = ($null -ne $processBlock -and -not $processBlock.Unnamed)

        $invokeCalls = @()
        $guardCalls = @()
        if ($null -ne $endBlock) {
            $invokeCalls = @($endBlock.FindAll({
                        param($node)
                        $node -is [System.Management.Automation.Language.CommandAst] -and
                        $node.GetCommandName() -eq 'Invoke-PfbApiRequest'
                    }, $true))

            $guardCalls = @($endBlock.FindAll({
                        param($node)
                        $node -is [System.Management.Automation.Language.CommandAst] -and
                        $node.GetCommandName() -eq 'Test-PfbEmptyPipelineRead'
                    }, $true))
        }

        # Call-shape invariant: the request must stay a direct statement of the cmdlet block, not
        # a statement of some nested scriptblock.
        $allInvokes = @($Function.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.CommandAst] -and
                    $node.GetCommandName() -eq 'Invoke-PfbApiRequest'
                }, $true))
        $nestedInvokes = @($allInvokes | Where-Object {
                Test-PfbNestedInScriptBlockExpression -Node $_ -Stop $Function
            })

        # Guard placement: a guard nested in a scriptblock returns from the scriptblock.
        $nestedGuards = @($guardCalls | Where-Object {
                Test-PfbNestedInScriptBlockExpression -Node $_ -Stop $endBlock
            })

        $guardQueryVars = @($guardCalls |
            ForEach-Object { Get-PfbParameterVariableName -Command $_ -ParameterName 'QueryParams' } |
            Where-Object { $_ })
        $invokeQueryVars = @($invokeCalls |
            ForEach-Object { Get-PfbParameterVariableName -Command $_ -ParameterName 'QueryParams' } |
            Where-Object { $_ })

        # Does the guard read the same hashtable the request is handed? A guard on some
        # other variable is inert.
        $queryVarMismatch = $false
        if ($guardCalls.Count -gt 0) {
            if ($guardQueryVars.Count -ne $guardCalls.Count) {
                $queryVarMismatch = $true
            }
            else {
                foreach ($name in $invokeQueryVars) {
                    if ($name -notin $guardQueryVars) { $queryVarMismatch = $true }
                }
            }
        }

        # Any write to the guarded hashtable AFTER the guard makes the guard unable to fire
        # for the very key it is supposed to see missing.
        #
        # An index-assignment-only detector is NOT enough, and the mirror harm is worse than
        # the one this rail was written for: hoisting a guard above
        # `Add-PfbCommonQueryParams -Into $queryParams` leaves the guard reading an empty
        # hashtable on EVERY piped invocation, so a legitimate piped read carrying names
        # silently returns nothing. That shape passes a literal-key detector and also
        # satisfies the generator's AlreadyPresent recognizer. (This repo has already paid
        # once for a literal-key-only detector -- see the 269-endpoint drift blind spot.)
        #
        # So match every write form the language offers on a variable we already know by
        # name: $q[...] = , $q.Foo = , $q.Add()/.Remove()/.Clear()/.set_Item(), and any
        # command handing the variable to an -Into parameter (the repo's writer convention).
        $queryWriteAfterGuard = $false
        if ($guardCalls.Count -gt 0 -and $guardQueryVars.Count -gt 0) {
            $firstGuardOffset = ($guardCalls |
                ForEach-Object { $_.Extent.StartOffset } |
                Measure-Object -Minimum).Minimum

            $mutatingMethods = @('add', 'remove', 'clear', 'set_item')

            $writeSites = @($endBlock.FindAll({
                        param($node)

                        # $q['k'] = v   /   $q.k = v
                        if ($node -is [System.Management.Automation.Language.AssignmentStatementAst]) {
                            $left = $node.Left
                            if ($left -is [System.Management.Automation.Language.IndexExpressionAst] -and
                                $left.Target -is [System.Management.Automation.Language.VariableExpressionAst]) {
                                return $true
                            }
                            if ($left -is [System.Management.Automation.Language.MemberExpressionAst] -and
                                $left.Expression -is [System.Management.Automation.Language.VariableExpressionAst]) {
                                return $true
                            }
                            return $false
                        }

                        # $q.Add(...) and friends
                        if ($node -is [System.Management.Automation.Language.InvokeMemberExpressionAst]) {
                            return ($node.Expression -is [System.Management.Automation.Language.VariableExpressionAst])
                        }

                        # Add-PfbCommonQueryParams -Into $q
                        if ($node -is [System.Management.Automation.Language.CommandAst]) {
                            return $true
                        }

                        return $false
                    }, $true))

            foreach ($site in $writeSites) {
                if ($site.Extent.StartOffset -le $firstGuardOffset) { continue }

                $writtenVar = $null
                if ($site -is [System.Management.Automation.Language.AssignmentStatementAst]) {
                    $left = $site.Left
                    if ($left -is [System.Management.Automation.Language.IndexExpressionAst]) {
                        $writtenVar = $left.Target.VariablePath.UserPath
                    }
                    else {
                        $writtenVar = $left.Expression.VariablePath.UserPath
                    }
                }
                elseif ($site -is [System.Management.Automation.Language.InvokeMemberExpressionAst]) {
                    $memberName = "$($site.Member)"
                    if ($memberName.ToLowerInvariant() -notin $mutatingMethods) { continue }
                    $writtenVar = $site.Expression.VariablePath.UserPath
                }
                else {
                    $writtenVar = Get-PfbParameterVariableName -Command $site -ParameterName 'Into'
                }

                if ($writtenVar -and $writtenVar -in $guardQueryVars) {
                    $queryWriteAfterGuard = $true
                }
            }
        }

        # I-1, first half: a guard that runs AFTER the request cannot stop it. Offsets, not
        # statement indexes, so this survives any nesting the other rails allow.
        $guardAfterSomeInvoke = $false
        if ($guardCalls.Count -gt 0 -and $invokeCalls.Count -gt 0) {
            $firstGuardOffset = ($guardCalls |
                ForEach-Object { $_.Extent.StartOffset } |
                Measure-Object -Minimum).Minimum
            $firstInvokeOffset = ($invokeCalls |
                ForEach-Object { $_.Extent.StartOffset } |
                Measure-Object -Minimum).Minimum
            $guardAfterSomeInvoke = ($firstGuardOffset -gt $firstInvokeOffset)
        }

        # I-1, second half: the predicate is only a guard if its answer is acted on. A bare
        # `Test-PfbEmptyPipelineRead ...` statement, or `$null = Test-...`, evaluates the
        # predicate and discards it -- and still counts as AlreadyPresent to the generator.
        # Require the call to BE the condition of an if whose taken branch returns.
        $guardReturns = $false
        foreach ($guard in $guardCalls) {
            $pipeline = $guard.Parent
            if ($pipeline -isnot [System.Management.Automation.Language.PipelineAst]) { continue }
            $ifStatement = $pipeline.Parent
            if ($ifStatement -isnot [System.Management.Automation.Language.IfStatementAst]) { continue }

            foreach ($clause in $ifStatement.Clauses) {
                if (-not [object]::ReferenceEquals($clause.Item1, $pipeline)) { continue }
                $returns = @($clause.Item2.FindAll({
                            param($node)
                            $node -is [System.Management.Automation.Language.ReturnStatementAst]
                        }, $true) | Where-Object {
                        # A return inside a scriptblock in the branch returns from the
                        # scriptblock, not the cmdlet.
                        -not (Test-PfbNestedInScriptBlockExpression -Node $_ -Stop $clause.Item2)
                    })
                if ($returns.Count -gt 0) { $guardReturns = $true }
            }
        }

        $conditionalKinds = @()
        if ($guardCalls.Count -gt 0) {
            $conditionalKinds = @($guardCalls |
                ForEach-Object { Get-PfbConditionalAncestorKind -Node $_ -Stop $endBlock } |
                Where-Object { $_ })
        }

        [PSCustomObject]@{
            File                                = $File
            Function                            = $Function.Name
            Verb                                = ($Function.Name -split '-', 2)[0]
            Line                                = $Function.Extent.StartLineNumber
            HasProcess                          = $hasProcess
            HasNamedEnd                         = $hasNamedEnd
            InvokeCallsInEnd                    = $invokeCalls.Count
            InvokeCallsTotal                    = $allInvokes.Count
            GuardCallsInEnd                     = $guardCalls.Count
            InvokeNestedInScriptBlockExpression = ($nestedInvokes.Count -gt 0)
            NestedInvokeLines                   = @($nestedInvokes | ForEach-Object { $_.Extent.StartLineNumber })
            GuardNestedInScriptBlockExpression  = ($nestedGuards.Count -gt 0)
            QueryVarMismatch                    = $queryVarMismatch
            QueryWriteAfterGuard                = $queryWriteAfterGuard
            GuardAfterSomeInvoke                = $guardAfterSomeInvoke
            GuardReturns                        = $guardReturns
            GuardInConditionalBlock             = ($conditionalKinds.Count -gt 0)
            GuardConditionalKinds               = $conditionalKinds
            MandatoryInEveryParameterSet        = (Test-PfbMandatoryInEveryParameterSet -Function $Function)
        }
    }

    $script:records = @(
        foreach ($file in (Get-ChildItem -Path $script:publicRoot -Filter '*.ps1' -Recurse -File)) {
            $relative = $file.FullName.Substring($script:moduleRoot.Length).TrimStart('\', '/').Replace('\', '/')

            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $file.FullName, [ref]$tokens, [ref]$errors)
            if ($errors.Count -gt 0) {
                throw "Parse errors in ${relative}: $(($errors | ForEach-Object { $_.Message }) -join '; ')"
            }

            $functions = @($ast.FindAll({
                        param($node)
                        $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
                    }, $true))

            foreach ($function in $functions) {
                Get-PfbGuardRecord -Function $function -File $relative
            }
        }
    )

    $script:qualifying = @($script:records | Where-Object {
            $_.HasProcess -and $_.HasNamedEnd -and $_.InvokeCallsInEnd -gt 0
        })
    $script:totalInvokeCalls = (@($script:records | ForEach-Object { $_.InvokeCallsTotal }) |
        Measure-Object -Sum).Sum
    $script:endBlockInvokeCalls = (@($script:records | ForEach-Object { $_.InvokeCallsInEnd }) |
        Measure-Object -Sum).Sum
}

Describe 'Empty-pipeline guard coverage' {

    It 'scans a population large enough for the other assertions to mean something' {
        # Not a pinned census -- the shipped rail must not red on legitimate surface growth.
        # These floors only prove the AST walk found the surface at all.
        #
        # The load-bearing one is $script:qualifying (130 measured): it is computed from
        # InvokeCallsInEnd, so an end-block detector regression drives it to zero and reds the
        # rail rather than silently emptying the coverage It. The end-block call floor is set on
        # that same metric for the same reason. The whole-function total is the loosest of the
        # three and is floored with headroom, so a consolidation refactor cannot red it.
        #
        # The $script:qualifying floor is deliberately tight (120 against 130 measured). Its job is
        # to catch a PARTIAL detector regression, not just a total collapse: at 100 a defect that
        # silently dropped 29 cmdlets from the guarded population would still pass. The headroom
        # that remains absorbs a small, legitimate shrink -- a handful of cmdlets consolidated or
        # retired -- without a test edit. It stays a floor rather than an equality on purpose: the
        # review proved by mutation that the sibling gate's equality passes vacuously (0 -eq 0)
        # under total detector collapse, and a floor cannot false-positive on surface growth.
        $script:records.Count | Should -BeGreaterThan 400
        $script:qualifying.Count | Should -BeGreaterThan 120
        $script:endBlockInvokeCalls | Should -BeGreaterThan 250
        $script:totalInvokeCalls | Should -BeGreaterThan 400
    }

    It 'guards every collect-in-process function that issues its request from end' {
        # Explicit and empty. Get-PfbNetworkConnectionStatistics, Get-PfbFleetKey and
        # Set-PfbContext are NOT exclusions -- they never satisfy the qualifying predicate.
        $allowedUnguarded = @()

        $offenders = @($script:records | Where-Object {
                $_.HasProcess -and $_.HasNamedEnd -and $_.InvokeCallsInEnd -gt 0 -and
                $_.GuardCallsInEnd -eq 0 -and $_.Function -notin $allowedUnguarded
            })
        $detail = @($offenders | ForEach-Object { "$($_.File): $($_.Function)" }) -join "`n"
        $detail | Should -BeNullOrEmpty -Because "every collect-in-process/request-in-end function must guard an empty pipeline; offenders:`n$detail"
    }

    It 'makes the diagnostic remediation safe for every state-changing guarded cmdlet' {
        # Issue #126. Write-PfbEmptyPipelineDiagnostic tells the caller to "call <cmdlet> directly
        # instead of piping to it". For a read verb the worst case of following that advice is an
        # unfiltered read. For anything else it could mean an UNSCOPED DESTRUCTIVE call -- unless
        # the cmdlet carries a mandatory selector on every path, in which case a bare call prompts
        # for the scope it genuinely requires instead of running unscoped.
        #
        # That property used to be asserted by a hand-maintained list of cmdlet names in the
        # diagnostic's own comment, and the list went stale. This derives it instead.
        #
        # Get and Test are the read verbs; EVERYTHING ELSE is treated as state-changing, so a newly
        # introduced verb fails closed and has to be considered. That matches the denylist
        # philosophy the whole feature is built on.
        $readVerbs = @('Get', 'Test')

        $stateChanging = @($script:qualifying | Where-Object { $_.Verb -notin $readVerbs })

        # Not vacuous: if the verb classification or the guarded-set derivation regresses, this
        # population empties and the offender assertion below would pass having checked nothing.
        $stateChanging.Count |
            Should -BeGreaterThan 0 -Because 'the guarded set must still contain at least one state-changing cmdlet for this assertion to mean anything'

        $offenders = @($stateChanging | Where-Object { -not $_.MandatoryInEveryParameterSet })
        $detail = @($offenders | ForEach-Object { "$($_.File): $($_.Function)" }) -join "`n"
        $detail | Should -BeNullOrEmpty -Because "a state-changing guarded cmdlet without a mandatory parameter in every parameter set turns the diagnostic's `"call it directly`" advice into an unscoped destructive call; offenders:`n$detail"
    }

    It 'keeps every Invoke-PfbApiRequest call directly in the cmdlet block' {
        # A request issued from inside a scriptblock is unreachable by a `return` guard.
        $nested = @($script:records | Where-Object InvokeNestedInScriptBlockExpression)
        $detail = @($nested | ForEach-Object {
                "$($_.File):$($_.NestedInvokeLines -join ',') $($_.Function)"
            }) -join "`n"
        $detail | Should -BeNullOrEmpty -Because "Invoke-PfbApiRequest must stay directly in the cmdlet block; nested sites:`n$detail"
    }

    It 'writes no query key unconditionally after the guard' {
        # A guard is only protective if no query key is written after it. Get-PfbRemoteArray is
        # the one legitimate exception: current_fleet_only is a scope flag, not a selector, and
        # it is written on both branches of an if/else -- so its guard is placed ABOVE that write
        # (see Task 4 / Step 10b of the issue #121 plan). Allowlisted by NAME, never by an
        # occurrence count: it carries two such writes today, one per branch, and collapsing the
        # branches must not red this rail.
        $allowedPostGuardWrite = @('Get-PfbRemoteArray')

        $postGuardWriters = @($script:records | Where-Object {
                $_.GuardCallsInEnd -gt 0 -and $_.QueryWriteAfterGuard -and
                $_.Function -notin $allowedPostGuardWrite
            })
        $detail = @($postGuardWriters | ForEach-Object { "$($_.File): $($_.Function)" }) -join "`n"
        $detail | Should -BeNullOrEmpty -Because "a query key written after the guard makes the guard unable to fire; offenders:`n$detail"
    }

    It 'places every guard where it can actually return, on the hashtable the request receives' {
        # Guard CORRECTNESS, not guard existence. The generator's AlreadyPresent recognizer
        # matches the command name anywhere in the end block's subtree, so a guard that drifted
        # into a ForEach-Object scriptblock, or that reads a hashtable the request never sees,
        # still reports a clean fixed point from the tool. Both allowlists are explicit and empty.
        $allowedNestedGuard = @()
        $allowedQueryVarMismatch = @()

        $nestedGuards = @($script:records | Where-Object {
                $_.GuardNestedInScriptBlockExpression -and $_.Function -notin $allowedNestedGuard
            })
        $nestedDetail = @($nestedGuards | ForEach-Object { "$($_.File): $($_.Function)" }) -join "`n"
        $nestedDetail | Should -BeNullOrEmpty -Because "a guard inside a scriptblock returns from the scriptblock, not the cmdlet; offenders:`n$nestedDetail"

        $mismatched = @($script:records | Where-Object {
                $_.GuardCallsInEnd -gt 0 -and $_.QueryVarMismatch -and
                $_.Function -notin $allowedQueryVarMismatch
            })
        $mismatchDetail = @($mismatched | ForEach-Object { "$($_.File): $($_.Function)" }) -join "`n"
        $mismatchDetail | Should -BeNullOrEmpty -Because "a guard must read the same hashtable the request is handed; offenders:`n$mismatchDetail"
    }

    It 'runs every guard before the request, and acts on its answer' {
        # Existence, placement and subject are not enough. Two more shapes are inert AND still
        # satisfy the generator's AlreadyPresent recognizer, so without these the drift gate and
        # this rail would both read green on a guard that does nothing:
        #   - a guard sitting BELOW the Invoke-PfbApiRequest it is meant to stop;
        #   - a bare `Test-PfbEmptyPipelineRead ...` (or `$null = Test-...`) whose boolean is
        #     evaluated and thrown away.
        # Both allowlists are explicit and empty.
        $allowedGuardAfterInvoke = @()
        $allowedGuardWithoutReturn = @()

        $late = @($script:records | Where-Object {
                $_.GuardAfterSomeInvoke -and $_.Function -notin $allowedGuardAfterInvoke
            })
        $lateDetail = @($late | ForEach-Object { "$($_.File): $($_.Function)" }) -join "`n"
        $lateDetail | Should -BeNullOrEmpty -Because "a guard below the request cannot stop it; offenders:`n$lateDetail"

        $inert = @($script:records | Where-Object {
                $_.GuardCallsInEnd -gt 0 -and -not $_.GuardReturns -and
                $_.Function -notin $allowedGuardWithoutReturn
            })
        $inertDetail = @($inert | ForEach-Object { "$($_.File): $($_.Function)" }) -join "`n"
        $inertDetail | Should -BeNullOrEmpty -Because "a guard whose answer is discarded never returns; offenders:`n$inertDetail"
    }

    It 'runs every guard unconditionally on the path to the request' {
        # Issue #128. The existing properties are all satisfied by a guard placed in a block that
        # may not execute -- see the mutation proof below. This is the dominance assertion.
        #
        # The allowlist is explicit and empty, and should stay that way: the generator cannot emit
        # the bad shape. Get-PfbTopLevelStatement (tools/Update-PfbEmptyPipelineGuards.ps1) walks
        # from the request up to the direct child of the end block and THROWS rather than
        # inserting anywhere else. The only route in is a hand edit against its grain.
        $allowedConditionalGuard = @()

        $offenders = @($script:records | Where-Object {
                $_.GuardInConditionalBlock -and $_.Function -notin $allowedConditionalGuard
            })
        $detail = @($offenders | ForEach-Object {
                "$($_.File): $($_.Function) [$($_.GuardConditionalKinds -join ',')]"
            }) -join "`n"
        $detail | Should -BeNullOrEmpty -Because "a guard in a conditionally executed block does not run on the path it exists to stop; offenders:`n$detail"
    }

    It 'detects every conditional placement without flagging unconditional placements' {
        # #128's mutation proof: the foreach mutant satisfies every existing rail, the new
        # properties identify why it is unsafe, every other conditional-block kind is recognized,
        # and unconditional try/finally bodies plus the guard's own if condition stay legal.
        # Get-PfbGuardRecord is called here rather than during discovery because BeforeAll defines it.
        $mutant = @'
function Get-PfbFixture {
    process { }
    end {
        $queryParams = @{}
        foreach ($n in $allNames) {
            if (Test-PfbEmptyPipelineRead -Caller $PSCmdlet -QueryParams $queryParams) { return }
        }
        Invoke-PfbApiRequest -Method GET -Endpoint 'x' -QueryParams $queryParams
    }
}
'@
        $hazardFixtures = [ordered]@{
            'elseif-condition' = @'
function Get-PfbFixture {
    process { }
    end {
        $queryParams = @{}
        if ($condition) { $null = 1 }
        elseif (Test-PfbEmptyPipelineRead -Caller $PSCmdlet -QueryParams $queryParams) { return }
        Invoke-PfbApiRequest -Method GET -Endpoint 'x' -QueryParams $queryParams
    }
}
'@
            'if-clause-body' = @'
function Get-PfbFixture {
    process { }
    end {
        $queryParams = @{}
        if ($condition) {
            if (Test-PfbEmptyPipelineRead -Caller $PSCmdlet -QueryParams $queryParams) { return }
        }
        Invoke-PfbApiRequest -Method GET -Endpoint 'x' -QueryParams $queryParams
    }
}
'@
            'else-body' = @'
function Get-PfbFixture {
    process { }
    end {
        $queryParams = @{}
        if ($condition) { $null = 1 }
        else {
            if (Test-PfbEmptyPipelineRead -Caller $PSCmdlet -QueryParams $queryParams) { return }
        }
        Invoke-PfbApiRequest -Method GET -Endpoint 'x' -QueryParams $queryParams
    }
}
'@
            'switch-clause' = @'
function Get-PfbFixture {
    process { }
    end {
        $queryParams = @{}
        switch ($value) {
            'x' {
                if (Test-PfbEmptyPipelineRead -Caller $PSCmdlet -QueryParams $queryParams) { return }
            }
        }
        Invoke-PfbApiRequest -Method GET -Endpoint 'x' -QueryParams $queryParams
    }
}
'@
            'switch-default' = @'
function Get-PfbFixture {
    process { }
    end {
        $queryParams = @{}
        switch ($value) {
            default {
                if (Test-PfbEmptyPipelineRead -Caller $PSCmdlet -QueryParams $queryParams) { return }
            }
        }
        Invoke-PfbApiRequest -Method GET -Endpoint 'x' -QueryParams $queryParams
    }
}
'@
            'catch-body' = @'
function Get-PfbFixture {
    process { }
    end {
        $queryParams = @{}
        try { throw 'fixture' }
        catch {
            if (Test-PfbEmptyPipelineRead -Caller $PSCmdlet -QueryParams $queryParams) { return }
        }
        Invoke-PfbApiRequest -Method GET -Endpoint 'x' -QueryParams $queryParams
    }
}
'@
            'trap-body' = @'
function Get-PfbFixture {
    process { }
    end {
        $queryParams = @{}
        trap {
            if (Test-PfbEmptyPipelineRead -Caller $PSCmdlet -QueryParams $queryParams) { return }
        }
        Invoke-PfbApiRequest -Method GET -Endpoint 'x' -QueryParams $queryParams
    }
}
'@
        }
        $unconditionalFixtures = [ordered]@{
            'guard-if-condition' = @'
function Get-PfbFixture {
    process { }
    end {
        $queryParams = @{}
        if (Test-PfbEmptyPipelineRead -Caller $PSCmdlet -QueryParams $queryParams) { return }
        Invoke-PfbApiRequest -Method GET -Endpoint 'x' -QueryParams $queryParams
    }
}
'@
            'try-body' = @'
function Get-PfbFixture {
    process { }
    end {
        $queryParams = @{}
        try {
            if (Test-PfbEmptyPipelineRead -Caller $PSCmdlet -QueryParams $queryParams) { return }
            Invoke-PfbApiRequest -Method GET -Endpoint 'x' -QueryParams $queryParams
        }
        catch { throw }
    }
}
'@
            'finally-body' = @'
function Get-PfbFixture {
    process { }
    end {
        $queryParams = @{}
        try { $null = 1 }
        finally {
            if (Test-PfbEmptyPipelineRead -Caller $PSCmdlet -QueryParams $queryParams) { $null = 1 }
        }
        Invoke-PfbApiRequest -Method GET -Endpoint 'x' -QueryParams $queryParams
    }
}
'@
        }

        function Get-FixtureRecord {
            param([string]$Source, [string]$Label)

            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseInput(
                $Source, [ref]$tokens, [ref]$errors)
            if ($errors.Count -gt 0) {
                throw "Parse errors in ${Label}: $(($errors | ForEach-Object { $_.Message }) -join '; ')"
            }
            $fn = $ast.Find({
                    param($node)
                    $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
                }, $true)
            return (Get-PfbGuardRecord -Function $fn -File $Label)
        }

        $mutantRecord = Get-FixtureRecord -Source $mutant -Label 'loop-body'

        # Every existing property is green on the mutant. If any of these reds, the gap this rail
        # addresses does not exist and the new assertion is redundant.
        $mutantRecord.GuardCallsInEnd | Should -BeGreaterThan 0 -Because 'the guard exists'
        $mutantRecord.GuardNestedInScriptBlockExpression |
            Should -BeFalse -Because 'a foreach body is a StatementBlockAst, not a ScriptBlockExpressionAst'
        $mutantRecord.QueryVarMismatch |
            Should -BeFalse -Because 'the guard reads the hashtable the request receives'
        $mutantRecord.QueryWriteAfterGuard | Should -BeFalse -Because 'no key is written after the guard'
        $mutantRecord.GuardAfterSomeInvoke | Should -BeFalse -Because 'the guard precedes the request'
        $mutantRecord.GuardReturns | Should -BeTrue -Because 'the guard is the condition of an if whose branch returns'

        # The new properties must fire positively on the mutation and identify its AST position.
        $mutantRecord.GuardInConditionalBlock | Should -BeTrue
        $mutantRecord.GuardConditionalKinds | Should -Contain 'loop-body'

        foreach ($kind in $hazardFixtures.Keys) {
            $record = Get-FixtureRecord -Source $hazardFixtures[$kind] -Label $kind
            $record.GuardInConditionalBlock | Should -BeTrue -Because "$kind is conditionally executed"
            $record.GuardConditionalKinds | Should -Contain $kind
        }

        foreach ($kind in $unconditionalFixtures.Keys) {
            $record = Get-FixtureRecord -Source $unconditionalFixtures[$kind] -Label $kind
            $record.GuardInConditionalBlock |
                Should -BeFalse -Because "$kind executes whenever control reaches its containing path"
            $record.GuardConditionalKinds | Should -BeNullOrEmpty
        }
    }

    It 'has a working scriptblock-nesting detector' {
        # The one one-way predicate in this file. Every other detector fails safe -- a broken
        # Get-PfbParameterVariableName drives QueryVarMismatch true and reds, a broken guard
        # finder reds the coverage It -- but if Test-PfbNestedInScriptBlockExpression regressed to
        # always returning $false, the call-shape It and the nested half of the placement It would
        # both pass vacuously and no floor would notice. So assert the predicate against a fixture
        # with a known answer in each direction, independent of the tree.
        $fixture = @'
function Test-Fixture {
    end {
        Invoke-PfbApiRequest -Endpoint 'direct'
        1..2 | ForEach-Object { Invoke-PfbApiRequest -Endpoint 'nested' }
    }
}
'@
        $fixtureAst = [System.Management.Automation.Language.Parser]::ParseInput(
            $fixture, [ref]$null, [ref]$null)
        $fixtureFunction = $fixtureAst.Find({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
            }, $true)

        $calls = @($fixtureFunction.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.CommandAst] -and
                    $node.GetCommandName() -eq 'Invoke-PfbApiRequest'
                }, $true))
        $calls.Count | Should -Be 2

        $answers = @($calls | ForEach-Object {
                Test-PfbNestedInScriptBlockExpression -Node $_ -Stop $fixtureFunction
            })
        $answers[0] | Should -BeFalse -Because 'the first call is a direct statement of the end block'
        $answers[1] | Should -BeTrue -Because 'the second call is inside a ForEach-Object scriptblock'
    }
}
