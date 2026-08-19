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

                # Any unconditional index-write to the guarded hashtable AFTER the guard makes the
                # guard unable to fire for the very key it is supposed to see missing.
                $queryWriteAfterGuard = $false
                if ($guardCalls.Count -gt 0 -and $guardQueryVars.Count -gt 0) {
                    $firstGuardOffset = ($guardCalls |
                        ForEach-Object { $_.Extent.StartOffset } |
                        Measure-Object -Minimum).Minimum

                    $indexAssignments = @($endBlock.FindAll({
                                param($node)
                                $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                                $node.Left -is [System.Management.Automation.Language.IndexExpressionAst] -and
                                $node.Left.Target -is [System.Management.Automation.Language.VariableExpressionAst]
                            }, $true))

                    foreach ($assignment in $indexAssignments) {
                        if ($assignment.Left.Target.VariablePath.UserPath -notin $guardQueryVars) { continue }
                        if ($assignment.Extent.StartOffset -gt $firstGuardOffset) {
                            $queryWriteAfterGuard = $true
                        }
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
                }
            }
        }
    )

    $script:qualifying = @($script:records | Where-Object {
            $_.HasProcess -and $_.HasNamedEnd -and $_.InvokeCallsInEnd -gt 0
        })
    $script:totalInvokeCalls = (@($script:records | ForEach-Object { $_.InvokeCallsTotal }) |
        Measure-Object -Sum).Sum
}

Describe 'Empty-pipeline guard coverage' {

    It 'scans a population large enough for the other assertions to mean something' {
        # Not a pinned census -- the shipped rail must not red on legitimate surface growth.
        # These floors only prove the AST walk found the surface at all.
        $script:records.Count | Should -BeGreaterThan 400
        $script:qualifying.Count | Should -BeGreaterThan 100
        $script:totalInvokeCalls | Should -BeGreaterThan 500
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
}
