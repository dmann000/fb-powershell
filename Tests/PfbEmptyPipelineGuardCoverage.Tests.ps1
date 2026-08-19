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
                $endBlock = $function.Body.EndBlock
                $processBlock = $function.Body.ProcessBlock
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

                # Call-shape invariant: the request must stay a direct statement of the cmdlet
                # block, not a statement of some nested scriptblock.
                $allInvokes = @($function.FindAll({
                            param($node)
                            $node -is [System.Management.Automation.Language.CommandAst] -and
                            $node.GetCommandName() -eq 'Invoke-PfbApiRequest'
                        }, $true))
                $nestedInvokes = @($allInvokes | Where-Object {
                        Test-PfbNestedInScriptBlockExpression -Node $_ -Stop $function
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

                [PSCustomObject]@{
                    File                                = $relative
                    Function                            = $function.Name
                    Line                                = $function.Extent.StartLineNumber
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
                }
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
        $script:records.Count | Should -BeGreaterThan 400
        $script:qualifying.Count | Should -BeGreaterThan 100
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
