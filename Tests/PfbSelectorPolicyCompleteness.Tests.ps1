#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

# Issue #126. The empty-pipeline selector policy is a DENYLIST: a query key nobody classified
# reads as a selector and the request is issued. That default is a COMPATIBILITY property, not a
# safety one -- a future key that broadens a result set would default to "selector" and return
# more than the caller addressed, silently, because the warning fires only on KNOWN non-selectors.
#
# This file is what makes the default unreachable. It does not defend the default; it asserts no
# release can contain a key that reaches it. An unclassified key in the guarded population reds
# the build and names the file.
#
# Scoped to the GUARDED population, never all of Public/. Widening it reds on the unmodified tree,
# drags mutation controls (cascade_delete, disruptive, recursive) into a read-only policy, and
# applies pressure in the UNSAFE direction: the natural way to green an unclassified-key failure
# is to add the key to the non-selector list, and gids/uids/user_sids are genuine selectors whose
# spelling the shape test cannot match. All three are written only by NON-guarded cmdlets.

BeforeAll {
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule

    $script:moduleRoot = Split-Path -Parent $PSScriptRoot
    $script:publicRoot = Join-Path $script:moduleRoot 'Public'

    # The CI-side shape test. Deliberately NOT the runtime policy and never consulted by it: this
    # classifies context_names as a selector and $script:PfbNonSelectorQueryKeys does not. It is
    # also not tools/Build-PfbDeadKeyReport.ps1's Test-PfbDeadKeySelectorName, which excludes
    # context_names and ids_or_names and admits singular name/id -- see the comment at that site.
    function Test-PfbIdentityShapedKey {
        param([string]$WireName)

        if ($WireName -in @('names', 'ids')) { return $true }
        return $WireName.EndsWith('_names', [System.StringComparison]::Ordinal) -or
        $WireName.EndsWith('_ids', [System.StringComparison]::Ordinal)
    }

    # The AST argument a CommandAst passes to a named parameter, or $null when absent. Returns the
    # AST rather than a variable name, because -QueryParams legitimately takes either a variable
    # or an inline hashtable literal and the gate has to see both.
    function Get-PfbParameterArgumentAst {
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
            if ($null -ne $element.Argument) { return $element.Argument }
            if (($i + 1) -lt $elements.Count) { return $elements[$i + 1] }
            return $null
        }
        return $null
    }

    # Every query key a guarded function writes, as records. Takes a FunctionDefinitionAst so the
    # same code runs over Public/ and over the synthetic fixtures below -- a gate whose scanner is
    # only ever pointed at the real tree cannot be shown to red.
    function Get-PfbGuardedQueryKey {
        param(
            [System.Management.Automation.Language.FunctionDefinitionAst]$Function,
            [string]$Label
        )

        $endBlock = $Function.Body.EndBlock
        $processBlock = $Function.Body.ProcessBlock
        if ($null -eq $endBlock -or $endBlock.Unnamed) { return @() }
        if ($null -eq $processBlock -or $processBlock.Unnamed) { return @() }

        $invokes = @($endBlock.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.CommandAst] -and
                    $node.GetCommandName() -eq 'Invoke-PfbApiRequest'
                }, $true))
        if ($invokes.Count -eq 0) { return @() }

        $records = [System.Collections.Generic.List[object]]::new()
        $queryVars = [System.Collections.Generic.List[string]]::new()

        foreach ($invoke in $invokes) {
            $argument = Get-PfbParameterArgumentAst -Command $invoke -ParameterName 'QueryParams'
            if ($null -eq $argument) { continue }

            if ($argument -is [System.Management.Automation.Language.VariableExpressionAst]) {
                $name = $argument.VariablePath.UserPath
                if ($queryVars -notcontains $name) { $queryVars.Add($name) }
            }
            elseif ($argument -is [System.Management.Automation.Language.HashtableAst]) {
                # Inline: Invoke-PfbApiRequest ... -QueryParams @{ limit = 1 }
                foreach ($pair in $argument.KeyValuePairs) {
                    $records.Add([PSCustomObject]@{
                            Source = $Label
                            Key    = $pair.Item1.Extent.Text.Trim("'", '"')
                            Shape  = 'inline-literal'
                            Line   = $pair.Item1.Extent.StartLineNumber
                        })
                }
            }
        }

        if ($queryVars.Count -eq 0) { return @($records) }

        foreach ($node in @($Function.FindAll({ param($n) $true }, $true))) {

            if ($node -is [System.Management.Automation.Language.AssignmentStatementAst]) {
                $left = $node.Left

                # $q['key'] = v
                if ($left -is [System.Management.Automation.Language.IndexExpressionAst] -and
                    $left.Target -is [System.Management.Automation.Language.VariableExpressionAst] -and
                    $queryVars -contains $left.Target.VariablePath.UserPath) {
                    $records.Add([PSCustomObject]@{
                            Source = $Label
                            Key    = $left.Index.Extent.Text.Trim("'", '"')
                            Shape  = 'index-assign'
                            Line   = $left.Extent.StartLineNumber
                        })
                }
                # $q.key = v
                elseif ($left -is [System.Management.Automation.Language.MemberExpressionAst] -and
                    $left.Expression -is [System.Management.Automation.Language.VariableExpressionAst] -and
                    $queryVars -contains $left.Expression.VariablePath.UserPath) {
                    $records.Add([PSCustomObject]@{
                            Source = $Label
                            Key    = "$($left.Member)"
                            Shape  = 'member-assign'
                            Line   = $left.Extent.StartLineNumber
                        })
                }
                # $q = @{ key = v }
                elseif ($left -is [System.Management.Automation.Language.VariableExpressionAst] -and
                    $queryVars -contains $left.VariablePath.UserPath) {
                    $right = $node.Right
                    $table = $null
                    if ($right -is [System.Management.Automation.Language.CommandExpressionAst]) {
                        $table = $right.Expression
                    }
                    if ($table -is [System.Management.Automation.Language.HashtableAst]) {
                        foreach ($pair in $table.KeyValuePairs) {
                            $records.Add([PSCustomObject]@{
                                    Source = $Label
                                    Key    = $pair.Item1.Extent.Text.Trim("'", '"')
                                    Shape  = 'hashtable-literal'
                                    Line   = $pair.Item1.Extent.StartLineNumber
                                })
                        }
                    }
                }
                continue
            }

            # $q.Add('key', v) / $q.set_Item('key', v)
            if ($node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
                $node.Expression -is [System.Management.Automation.Language.VariableExpressionAst] -and
                $queryVars -contains $node.Expression.VariablePath.UserPath) {
                $member = "$($node.Member)".ToLowerInvariant()
                if ($member -in @('add', 'set_item') -and @($node.Arguments).Count -ge 1) {
                    $records.Add([PSCustomObject]@{
                            Source = $Label
                            Key    = $node.Arguments[0].Extent.Text.Trim("'", '"')
                            Shape  = "method-$member"
                            Line   = $node.Extent.StartLineNumber
                        })
                }
            }
        }

        return @($records)
    }

    # Parse a fixture string and hand back its single function's records.
    function Get-PfbFixtureQueryKey {
        param([string]$Source, [string]$Label)

        $ast = [System.Management.Automation.Language.Parser]::ParseInput($Source, [ref]$null, [ref]$null)
        $function = $ast.Find({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
            }, $true)
        return @(Get-PfbGuardedQueryKey -Function $function -Label $Label)
    }

    $script:guardedFunctionCount = 0
    $script:keyRecords = @(
        foreach ($file in (Get-ChildItem -Path $script:publicRoot -Filter '*.ps1' -Recurse -File)) {
            $relative = $file.FullName.Substring($script:moduleRoot.Length).TrimStart('\', '/').Replace('\', '/')

            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $file.FullName, [ref]$null, [ref]$errors)
            if ($errors.Count -gt 0) {
                throw "Parse errors in ${relative}: $(($errors | ForEach-Object { $_.Message }) -join '; ')"
            }

            foreach ($function in @($ast.FindAll({
                            param($node)
                            $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
                        }, $true))) {

                $endBlock = $function.Body.EndBlock
                $processBlock = $function.Body.ProcessBlock
                $isGuarded = ($null -ne $endBlock -and -not $endBlock.Unnamed -and
                    $null -ne $processBlock -and -not $processBlock.Unnamed -and
                    @($endBlock.FindAll({
                                param($node)
                                $node -is [System.Management.Automation.Language.CommandAst] -and
                                $node.GetCommandName() -eq 'Invoke-PfbApiRequest'
                            }, $true)).Count -gt 0)
                if (-not $isGuarded) { continue }

                $script:guardedFunctionCount++
                Get-PfbGuardedQueryKey -Function $function -Label "${relative}: $($function.Name)"
            }
        }
    )

    $script:nonSelectorKeys = InModuleScope PureStorageFlashBladePowerShell {
        [string[]]@($script:PfbNonSelectorQueryKeys)
    }
}

Describe 'Selector policy completeness' {

    It 'scans a guarded population large enough for the other assertions to mean something' {
        # A floor, not a pinned census -- the gate must not red on legitimate surface growth. Its
        # only job is to stop the whole file passing vacuously if the guarded-population detector
        # regresses to finding nothing. Measured at 130 guarded functions and 107 write sites.
        $script:guardedFunctionCount | Should -BeGreaterThan 100
        @($script:keyRecords).Count | Should -BeGreaterThan 80
    }

    It 'classifies every query key written by a guarded cmdlet' {
        # THE gate. An unclassified key reds the build and names the file, so the runtime default
        # -- issue the request -- is unreachable in a release.
        #
        # Greening a failure here is a DECISION, not a chore, and the two ways out are not
        # equivalent. If the key addresses objects the caller chose, it needs no entry: it is a
        # selector and the shape test should already match it. If it does not, add it to
        # Private/PfbSelectorPolicyConstants.ps1 WITH the one-line reason the others carry. The
        # test for a key nobody has classified: if the SERVER decides how many objects come back,
        # it is scope.
        $unclassified = @($script:keyRecords | Where-Object {
                $_.Key -notin $script:nonSelectorKeys -and -not (Test-PfbIdentityShapedKey -WireName $_.Key)
            })

        $detail = @($unclassified | ForEach-Object { "$($_.Source) [$($_.Shape)] line $($_.Line): $($_.Key)" }) -join "`n"
        $detail | Should -BeNullOrEmpty -Because "every query key a guarded cmdlet writes must be a classified non-selector or identity-shaped; unclassified:`n$detail"
    }

    It 'reds on an unclassified key regardless of the hashtable variable name' {
        # Non-vacuity, and specifically against the gap that sank the obvious implementation.
        # tools/lib/PfbCmdletParamTools.ps1 restricts assignment targets to variables named
        # 'body' or 'queryParams'; Public/ uses queryParams 616 times, q 20 times and destroyQuery
        # once. A gate reusing that machinery misses 21 real sites and still reads green.
        $fixtures = @(
            @{
                Label  = 'queryParams-shaped'
                Source = @'
function Get-PfbFixture {
    process { }
    end {
        $queryParams = @{}
        $queryParams['some_future_flag'] = 'true'
        Invoke-PfbApiRequest -Method GET -Endpoint 'x' -QueryParams $queryParams
    }
}
'@
            }
            @{
                Label  = 'q-shaped'
                Source = @'
function Get-PfbFixture {
    process { }
    end {
        $q = @{}
        $q['some_future_flag'] = 'true'
        Invoke-PfbApiRequest -Method GET -Endpoint 'x' -QueryParams $q
    }
}
'@
            }
            @{
                Label  = 'inline-literal'
                Source = @'
function Get-PfbFixture {
    process { }
    end {
        Invoke-PfbApiRequest -Method GET -Endpoint 'x' -QueryParams @{ some_future_flag = 'true' }
    }
}
'@
            }
            @{
                Label  = 'hashtable-literal-assignment'
                Source = @'
function Get-PfbFixture {
    process { }
    end {
        $destroyQuery = @{ some_future_flag = 'true' }
        Invoke-PfbApiRequest -Method GET -Endpoint 'x' -QueryParams $destroyQuery
    }
}
'@
            }
        )

        foreach ($fixture in $fixtures) {
            $records = Get-PfbFixtureQueryKey -Source $fixture.Source -Label $fixture.Label
            @($records).Count |
                Should -BeGreaterThan 0 -Because "the scanner must see the key in the $($fixture.Label) shape"

            $unclassified = @($records | Where-Object {
                    $_.Key -notin $script:nonSelectorKeys -and -not (Test-PfbIdentityShapedKey -WireName $_.Key)
                })
            @($unclassified).Count |
                Should -BeGreaterThan 0 -Because "the $($fixture.Label) fixture must red the gate"
        }
    }

    It 'stays quiet on a classified key and on an identity-shaped one' {
        # The other half of non-vacuity: a scanner that flagged everything would pass the It above
        # and be useless. Both exits from the gate have to be reachable.
        $clean = @'
function Get-PfbFixture {
    process { }
    end {
        $queryParams = @{}
        $queryParams['limit'] = 10
        $queryParams['policy_names'] = 'p'
        Invoke-PfbApiRequest -Method GET -Endpoint 'x' -QueryParams $queryParams
    }
}
'@
        $records = Get-PfbFixtureQueryKey -Source $clean -Label 'clean'
        @($records).Count | Should -Be 2

        $unclassified = @($records | Where-Object {
                $_.Key -notin $script:nonSelectorKeys -and -not (Test-PfbIdentityShapedKey -WireName $_.Key)
            })
        @($unclassified).Count | Should -Be 0
    }

    It 'ignores a cmdlet that is not in the guarded population' {
        # Scope proof. gids, uids and user_sids are genuine selectors the shape test cannot match,
        # and they are safe only because the cmdlets writing them have no named process block. If
        # the scanner ever starts picking up unguarded cmdlets, this reds before those three do --
        # which matters, because their failure would push a maintainer to list a real selector as
        # a non-selector.
        $unguarded = @'
function Get-PfbFixture {
    end {
        $queryParams = @{}
        $queryParams['gids'] = '1'
        Invoke-PfbApiRequest -Method GET -Endpoint 'x' -QueryParams $queryParams
    }
}
'@
        @(Get-PfbFixtureQueryKey -Source $unguarded -Label 'unguarded').Count | Should -Be 0
    }

    It 'has no unreachable entry among the per-cmdlet non-selectors' {
        # Every one of the nine per-cmdlet entries must actually be written by a guarded cmdlet. A
        # dead entry reads as coverage and is not.
        #
        # Scoped to the nine on purpose: limit, sort and total_only come from
        # Add-PfbCommonQueryParams, not from any cmdlet body, so they are unreachable BY DESIGN
        # here.
        #
        # This is expected to red when a related issue lands, and that is the point. #142 may
        # remove -Flagged from Get-PfbAlert, and #127 removes Remove-PfbLocalGroup from the guarded
        # population. When it reds, PRUNE the list entry -- do not add the key to the exemption
        # below.
        $helperWritten = @('limit', 'sort', 'total_only')
        $perCmdlet = @($script:nonSelectorKeys | Where-Object { $_ -notin $helperWritten })
        @($perCmdlet).Count | Should -Be 9

        $written = @($script:keyRecords | ForEach-Object { $_.Key } | Select-Object -Unique)
        $unreachable = @($perCmdlet | Where-Object { $_ -notin $written })

        ($unreachable -join ', ') | Should -BeNullOrEmpty -Because "a listed non-selector no guarded cmdlet writes is a dead entry; prune it: $($unreachable -join ', ')"
    }
}
