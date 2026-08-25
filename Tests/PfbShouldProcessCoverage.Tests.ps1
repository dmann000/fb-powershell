#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

# ShouldProcess coverage sweep. Public/ is a 544-cmdlet generated-and-hand-edited population and a
# population that size decays silently: a new state-changing cmdlet arrives without
# SupportsShouldProcess, or with a declaration nothing ever calls, and no existing test notices
# because every test in Tests/ is scoped to one cmdlet.
#
# These are AST tripwires, not behaviour tests -- same shape as
# Tests/PfbEmptyPipelineGuardCoverage.Tests.ps1, and for the same reason: a mechanical gate runs on
# every change for free and cannot rationalise a finding away.
#
# The load-bearing assertion is the ConfirmImpact one. ConfirmImpact only triggers an automatic
# prompt when it meets or exceeds $ConfirmPreference, which defaults to 'High'. A Remove-* cmdlet
# declaring 'Medium' therefore deletes without ever prompting -- the declaration reads as
# protective while doing nothing at all.
#
# Nothing here imports the module. Parsing only, so no module state is created or leaked.

BeforeAll {
    $script:moduleRoot = Split-Path -Parent $PSScriptRoot
    $script:publicRoot = Join-Path $script:moduleRoot 'Public'

    # DUPLICATED, deliberately, from Tests/PfbEmptyPipelineGuardCoverage.Tests.ps1. Extracting a
    # single shared copy to tools/lib/ is the right end state and is a deliberate follow-up, not an
    # oversight: that file is a CI-critical gate and refactoring it was out of scope for the change
    # that added this one. If you edit one copy, edit both.
    #
    # Walk a node's parent chain up to (and excluding) $Stop, reporting whether any INNER SCOPE sits
    # in between. Two AST shapes introduce one: a ScriptBlockExpressionAst (the familiar
    # `... | ForEach-Object { }` case) and a nested FunctionDefinitionAst. A NamedBlockAst
    # (begin/process/end) and a StatementBlockAst (an if body, a foreach body) are NEITHER -- they
    # share the cmdlet's scope, so a `return` in one returns from the cmdlet.
    #
    # Matching a FunctionDefinitionAst cannot flag a cmdlet's own definition: the only call site
    # stops at $Function itself and the loop tests its condition before its body, so the cmdlet's
    # own FunctionDefinitionAst is never reached.
    function Test-PfbNestedInInnerScope {
        param(
            [System.Management.Automation.Language.Ast]$Node,
            [System.Management.Automation.Language.Ast]$Stop
        )

        $cursor = $Node.Parent
        while ($null -ne $cursor -and -not [object]::ReferenceEquals($cursor, $Stop)) {
            if ($cursor -is [System.Management.Automation.Language.ScriptBlockExpressionAst] -or
                $cursor -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
                return $true
            }
            $cursor = $cursor.Parent
        }
        return $false
    }

    # The [CmdletBinding(...)] attribute of a function, or $null.
    #
    # It hangs off the PARAM BLOCK, not off the FunctionDefinitionAst -- a function with no param()
    # block cannot carry one at all, which is why this returns $null rather than throwing.
    function Get-PfbCmdletBindingAttribute {
        param(
            [System.Management.Automation.Language.FunctionDefinitionAst]$Function
        )

        $paramBlock = $Function.Body.ParamBlock
        if ($null -eq $paramBlock) { return $null }

        foreach ($attribute in $paramBlock.Attributes) {
            if ($attribute -isnot [System.Management.Automation.Language.AttributeAst]) { continue }
            # Both spellings are legal PowerShell; the shipped tree uses the short one throughout,
            # but accepting only the short one would make a legal hand edit invisible to this gate.
            if ($attribute.TypeName.Name -in @('CmdletBinding', 'CmdletBindingAttribute')) {
                return $attribute
            }
        }
        return $null
    }

    # Reduce one cmdlet to the facts the assertions below need.
    function Get-PfbShouldProcessRecord {
        param(
            [System.Management.Automation.Language.FunctionDefinitionAst]$Function,
            [string]$File
        )

        $supportsShouldProcess = $false
        $confirmImpact = $null

        $binding = Get-PfbCmdletBindingAttribute -Function $Function
        if ($null -ne $binding) {
            foreach ($named in $binding.NamedArguments) {
                if ($named.ArgumentName -eq 'SupportsShouldProcess') {
                    # `SupportsShouldProcess` with no `= $true` omits the expression entirely; that
                    # is the form the whole tree uses, so treating ExpressionOmitted as $false would
                    # read the population as having zero declarations and pass everything vacuously.
                    if ($named.ExpressionOmitted) { $supportsShouldProcess = $true }
                    elseif ($named.Argument.Extent.Text -eq '$true') { $supportsShouldProcess = $true }
                }
                elseif ($named.ArgumentName -eq 'ConfirmImpact') {
                    if (-not $named.ExpressionOmitted -and
                        $named.Argument -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                        $confirmImpact = $named.Argument.Value
                    }
                    else {
                        # A non-literal ConfirmImpact (a variable, an expression) is not something
                        # this gate can evaluate. Record it verbatim so the assertion reds and a
                        # human looks, rather than silently reading as "not High".
                        $confirmImpact = $named.Argument.Extent.Text
                    }
                }
            }
        }

        # $PSCmdlet.ShouldProcess(...) / .ShouldContinue(...). Member is an ExpressionAst, so a
        # dynamic member name ($PSCmdlet.$verb(...)) is a MemberExpression rather than a string
        # constant -- guard the cast instead of stringifying, or a dynamic call would compare equal
        # to nothing and be silently uncounted.
        $calls = @($Function.FindAll({
                    param($node)
                    if ($node -isnot [System.Management.Automation.Language.InvokeMemberExpressionAst]) { return $false }
                    if ($node.Member -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) { return $false }
                    return ($node.Member.Value -in @('ShouldProcess', 'ShouldContinue'))
                }, $true))

        $nestedCalls = @($calls | Where-Object {
                Test-PfbNestedInInnerScope -Node $_ -Stop $Function
            })

        [PSCustomObject]@{
            File                  = $File
            Function              = $Function.Name
            Verb                  = ($Function.Name -split '-', 2)[0]
            Line                  = $Function.Extent.StartLineNumber
            SupportsShouldProcess = $supportsShouldProcess
            ConfirmImpact         = $confirmImpact
            ShouldProcessCalls    = $calls.Count
            NestedCalls           = $nestedCalls.Count
            NestedCallLines       = @($nestedCalls | ForEach-Object { $_.Extent.StartLineNumber })
        }
    }

    # One record per cmdlet. FindAll(..., $false) takes only DEPTH-0 function definitions, so a
    # nested helper function inside a cmdlet is never mistaken for a cmdlet of its own -- and the
    # first of those is the cmdlet, matching the file-per-cmdlet layout Public/ uses throughout.
    $script:cmdlets = @(
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
                    }, $false))
            if ($functions.Count -eq 0) { continue }

            Get-PfbShouldProcessRecord -Function $functions[0] -File $relative
        }
    )

    # The verbs that change ARRAY state. Deliberately a small explicit list rather than
    # "everything that is not Get/Test": a new verb should have to be considered here rather than
    # silently inheriting a requirement that may not fit it.
    $script:stateChangingVerbs = @('New', 'Remove', 'Update', 'Set', 'Add', 'Clear')

    # The read-only verbs. Declaring SupportsShouldProcess on one of these advertises a mutation
    # that does not exist -- -WhatIf output claiming a Get- cmdlet would change something.
    $script:readOnlyVerbs = @('Get', 'Test')

    # A LITERAL list, never a name-shaped regex. A pattern like '*Context*' or '*Credential*' would
    # silently absorb a future cmdlet that genuinely does need a guard, which is precisely the decay
    # this file exists to catch.
    #
    # Every entry here changes only LOCAL SESSION state or is a read-only diagnostic. None of them
    # sends a mutating request, so -WhatIf/-Confirm would be noise rather than protection.
    $script:shouldProcessExempt = @(
        'Set-PfbCredential'      # local credential store; no array call
        'Clear-PfbCredential'    # local credential store; no array call
        'Set-PfbContext'         # local context state on a copied connection object; no array call
        'Clear-PfbContext'       # local context state on a copied connection object; no array call

        # The three below carry the Invoke verb, which is NOT in $script:stateChangingVerbs, so
        # they are inert today. Listed anyway so that the reasoning survives: if Invoke is ever
        # added to the verb list, these three must not become failures by accident.
        'Invoke-PfbInContext'    # scoping wrapper; mutates nothing itself, the wrapped call does
        'Invoke-PfbNetworkPing'  # read-only diagnostic
        'Invoke-PfbNetworkTrace' # read-only diagnostic
    )

    # PENDING MAINTAINER DECISION -- NOT a settled exemption.
    #
    # Remove-PfbWorkloadTag is the only Remove-* in the module declaring ConfirmImpact = 'Medium'
    # rather than 'High'. At Medium it deletes without ever prompting, because the default
    # $ConfirmPreference is High. That is either:
    #   (a) a real defect -- the cmdlet should be 'High' like its 111 siblings; or
    #   (b) deliberate -- a workload TAG is metadata, cheaply recreated, and unlike the other
    #       Remove-* cmdlets its loss destroys no data.
    #
    # Which of those is true is the maintainer's call, not this test's, and it MUST be settled
    # before this file merges. It is parked here, in its own list with its own name, rather than
    # buried in $script:confirmImpactExempt, so that resolving it is a visible one-line edit:
    # either move it into the settled list with a reason, or fix the cmdlet and delete this list.
    $script:confirmImpactPendingDecision = @(
        'Remove-PfbWorkloadTag'
    )

    # Settled exemptions from the Remove-*-is-High rule. Empty today, and it should stay that way
    # unless a specific cmdlet earns an entry with a written reason.
    $script:confirmImpactExempt = @()
}

Describe 'ShouldProcess coverage' {

    It 'scans a population large enough for the other assertions to mean something' {
        # THE ANTI-VACUOUS FLOOR. Every assertion below is of the form "the set of offenders is
        # empty". If the Public/ glob returned nothing, or the depth-0 function walk regressed,
        # every one of them would pass while checking exactly zero cmdlets and the gate would
        # report green. These floors are the only thing standing between that and a false pass.
        #
        # Floors, not pins. The population grows -- pinning 544 turns every legitimate new cmdlet
        # into an unrelated red build, which is how a gate gets disabled. Measured on main
        # 2026-08-24: 544 cmdlets, 311 declaring SupportsShouldProcess, 112 Remove-*.
        #
        # The derived floors matter as much as the total: a total-only floor passes intact while a
        # regression in the CmdletBinding walk drives every SupportsShouldProcess to $false, which
        # would empty the two assertions that depend on it.
        $script:cmdlets.Count | Should -BeGreaterOrEqual 500

        $declaring = @($script:cmdlets | Where-Object SupportsShouldProcess)
        $declaring.Count |
            Should -BeGreaterOrEqual 280 -Because 'a regression in the CmdletBinding/NamedArguments walk empties the "declaration is used" and "impact is High" assertions without emptying the total'

        $removes = @($script:cmdlets | Where-Object { $_.Verb -eq 'Remove' })
        $removes.Count |
            Should -BeGreaterOrEqual 100 -Because 'the ConfirmImpact assertion is scoped to Remove-*, so it needs its own floor'
    }

    It 'declares SupportsShouldProcess on every state-changing cmdlet' {
        $offenders = @($script:cmdlets | Where-Object {
                $_.Verb -in $script:stateChangingVerbs -and
                -not $_.SupportsShouldProcess -and
                $_.Function -notin $script:shouldProcessExempt
            })
        $detail = @($offenders | ForEach-Object { "$($_.File): $($_.Function)" }) -join "`n"
        $detail | Should -BeNullOrEmpty -Because "a state-changing cmdlet without SupportsShouldProcess silently ignores -WhatIf and -Confirm; offenders:`n$detail"
    }

    It 'actually calls ShouldProcess wherever it declares SupportsShouldProcess' {
        # A declaration with no call is worse than no declaration: -WhatIf binds successfully, the
        # caller believes nothing happened, and the request went out anyway. Measured 0 violations
        # on main -- this is a tripwire protecting a clean state, not a fix for a live defect.
        $offenders = @($script:cmdlets | Where-Object {
                $_.SupportsShouldProcess -and $_.ShouldProcessCalls -eq 0
            })
        $detail = @($offenders | ForEach-Object { "$($_.File): $($_.Function)" }) -join "`n"
        $detail | Should -BeNullOrEmpty -Because "SupportsShouldProcess without a ShouldProcess call makes -WhatIf silently perform the operation; offenders:`n$detail"
    }

    It 'keeps every ShouldProcess call out of an inner scope' {
        # Same hazard the empty-pipeline sweep documents. The shipped shape is
        # `if ($PSCmdlet.ShouldProcess(...)) { Invoke-PfbApiRequest ... }` as a direct statement of
        # the cmdlet block. Inside a ForEach-Object scriptblock or a nested function the guard's
        # control flow applies to THAT scope, so `return`-style declines leak and the request still
        # goes out.
        #
        # This flags ANY nested call, not merely "no unnested call exists". That is stricter than
        # the harm strictly requires -- a genuine per-item confirmation loop written as
        # `$items | ForEach-Object { if ($PSCmdlet.ShouldProcess($_)) { ... } }` is sound and would
        # be flagged. The module has no such cmdlet today (measured 0), the convention here is a
        # single top-level guard, and the allowlist below is the intended escape valve if one is
        # ever written deliberately. Explicit and empty on purpose.
        $allowedNestedShouldProcess = @()

        $offenders = @($script:cmdlets | Where-Object {
                $_.NestedCalls -gt 0 -and $_.Function -notin $allowedNestedShouldProcess
            })
        $detail = @($offenders | ForEach-Object {
                "$($_.File):$($_.NestedCallLines -join ',') $($_.Function)"
            }) -join "`n"
        $detail | Should -BeNullOrEmpty -Because "a ShouldProcess call inside a scriptblock or nested function guards that scope, not the cmdlet; offenders:`n$detail"
    }

    It 'declares no SupportsShouldProcess on a read-only verb' {
        # The inverse tripwire. -WhatIf on a Get- cmdlet claiming it would change something is a
        # lie about the cmdlet's behaviour, and it is the shape a copy-pasted CmdletBinding line
        # produces. Measured 0 violations on main.
        $readOnly = @($script:cmdlets | Where-Object { $_.Verb -in $script:readOnlyVerbs })
        $readOnly.Count |
            Should -BeGreaterOrEqual 200 -Because 'the read-only population must be non-trivial or this assertion checks nothing'

        $offenders = @($readOnly | Where-Object { $_.SupportsShouldProcess })
        $detail = @($offenders | ForEach-Object { "$($_.File): $($_.Function)" }) -join "`n"
        $detail | Should -BeNullOrEmpty -Because "a read-only verb declaring SupportsShouldProcess advertises a mutation it does not perform; offenders:`n$detail"
    }

    It 'declares ConfirmImpact = High on every Remove- cmdlet' {
        # THE LOAD-BEARING ONE. ConfirmImpact prompts automatically only when it meets or exceeds
        # $ConfirmPreference, whose default is 'High'. A Remove-* at 'Medium' or 'Low' therefore
        # never prompts: the declaration reads as protective in review while doing nothing at
        # runtime. The failure is invisible in mocked tests (a mock never reaches ShouldProcess) and
        # invisible interactively for the cmdlets that DO prompt, so a sweep is the only place it
        # can be caught.
        #
        # $script:confirmImpactPendingDecision is NOT a settled exemption -- see its definition.
        $offenders = @($script:cmdlets | Where-Object {
                $_.Verb -eq 'Remove' -and
                $_.ConfirmImpact -ne 'High' -and
                $_.Function -notin $script:confirmImpactExempt -and
                $_.Function -notin $script:confirmImpactPendingDecision
            })
        $detail = @($offenders | ForEach-Object {
                "$($_.File): $($_.Function) [ConfirmImpact = $($_.ConfirmImpact)]"
            }) -join "`n"
        $detail | Should -BeNullOrEmpty -Because "a Remove- cmdlet below ConfirmImpact 'High' deletes without ever prompting, because `$ConfirmPreference defaults to High; offenders:`n$detail"

        # Keep the pending-decision list honest in both directions. If somebody resolves
        # Remove-PfbWorkloadTag by raising it to High but forgets to empty this list, the entry
        # becomes a silent standing exemption for a cmdlet that no longer needs one -- and the next
        # Remove-* to regress to Medium under that same name would pass. So assert every parked
        # name is still genuinely non-High.
        foreach ($name in $script:confirmImpactPendingDecision) {
            $record = @($script:cmdlets | Where-Object { $_.Function -eq $name })
            $record.Count | Should -Be 1 -Because "the pending-decision entry '$name' must still name a real cmdlet"
            $record[0].ConfirmImpact |
                Should -Not -Be 'High' -Because "'$name' is now High, so its pending-decision entry is stale and must be deleted"
        }
    }

    It 'does not flag a deliberate ConfirmImpact escalation outside Remove-' {
        # Spec requirement, asserted rather than merely commented. Escalating a non-destructive but
        # dangerous cmdlet to 'High' is correct and must never be treated as a finding. Asserting it
        # positively is what stops the assertion above from later being "tidied" into
        # "everything declaring SupportsShouldProcess must be High", which would red these two and
        # invite the wrong fix.
        $escalated = @($script:cmdlets | Where-Object {
                $_.Verb -ne 'Remove' -and $_.ConfirmImpact -eq 'High'
            })
        $escalated.Count | Should -BeGreaterThan 0

        foreach ($name in @('New-PfbArrayFactoryResetToken', 'New-PfbRapidDataLockingRotation')) {
            @($escalated | Where-Object { $_.Function -eq $name }).Count |
                Should -Be 1 -Because "'$name' is a deliberate non-Remove escalation to High and must remain unflagged"
        }
    }

    It 'has a working inner-scope-nesting detector' {
        # The one one-way predicate in this file, and the same protection the empty-pipeline sweep
        # gives its copy. Every other detector here fails safe -- a broken CmdletBinding walk drives
        # SupportsShouldProcess to $false and reds the floor, a broken call finder reds the
        # "declaration is used" assertion. But if Test-PfbNestedInInnerScope regressed to always
        # returning $false, the inner-scope assertion would pass vacuously and no floor would
        # notice, because its offender set is empty on main either way.
        #
        # So assert the predicate against a fixture with a known answer in each direction, and
        # assert the record-building path end-to-end on the same fixture.
        $fixture = @'
function Remove-PfbFixture {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([Parameter()] [string]$Name)
    if ($PSCmdlet.ShouldProcess('target', 'direct')) { $null = 1 }
    1..2 | ForEach-Object { $PSCmdlet.ShouldProcess('target', 'in-scriptblock') }
    function Invoke-Inner {
        $PSCmdlet.ShouldContinue('target', 'in-nested-function')
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
                    $node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
                    $node.Member -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
                    $node.Member.Value -in @('ShouldProcess', 'ShouldContinue')
                }, $true))
        $calls.Count | Should -Be 3 -Because 'ShouldContinue must be recognised alongside ShouldProcess'

        $answers = @($calls | ForEach-Object {
                Test-PfbNestedInInnerScope -Node $_ -Stop $fixtureFunction
            })
        $answers[0] | Should -BeFalse -Because 'the first call is a direct statement of the cmdlet block'
        $answers[1] | Should -BeTrue -Because 'the second call is inside a ForEach-Object scriptblock'
        $answers[2] | Should -BeTrue -Because 'the third call is inside a nested function definition'

        $record = Get-PfbShouldProcessRecord -Function $fixtureFunction -File 'fixture'
        $record.SupportsShouldProcess |
            Should -BeTrue -Because 'the attribute walk must read the expression-omitted form the whole tree uses'
        $record.ConfirmImpact | Should -Be 'High'
        $record.ShouldProcessCalls | Should -Be 3
        $record.NestedCalls | Should -Be 2
        $record.Verb | Should -Be 'Remove'
    }

    It 'recognises the negative shapes it is meant to flag' {
        # The mirror of the It above: prove each assertion's PREDICATE fires on a cmdlet that has
        # the defect, not just that no cmdlet in Public/ has it. Without this, an extraction bug
        # that made SupportsShouldProcess never $true, or ConfirmImpact always 'High', would leave
        # every offender set empty and every assertion green.
        $negatives = [ordered]@{
            'no-shouldprocess-declaration' = @'
function Remove-PfbFixture {
    [CmdletBinding()]
    param([Parameter()] [string]$Name)
    Invoke-PfbApiRequest -Method DELETE -Endpoint 'x'
}
'@
            'declared-never-called'        = @'
function Remove-PfbFixture {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([Parameter()] [string]$Name)
    Invoke-PfbApiRequest -Method DELETE -Endpoint 'x'
}
'@
            'impact-medium'                = @'
function Remove-PfbFixture {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param([Parameter()] [string]$Name)
    if ($PSCmdlet.ShouldProcess('x')) { Invoke-PfbApiRequest -Method DELETE -Endpoint 'x' }
}
'@
            'impact-absent'                = @'
function Remove-PfbFixture {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter()] [string]$Name)
    if ($PSCmdlet.ShouldProcess('x')) { Invoke-PfbApiRequest -Method DELETE -Endpoint 'x' }
}
'@
            'readonly-declares'            = @'
function Get-PfbFixture {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter()] [string]$Name)
    if ($PSCmdlet.ShouldProcess('x')) { Invoke-PfbApiRequest -Method GET -Endpoint 'x' }
}
'@
        }

        $records = [ordered]@{}
        foreach ($label in $negatives.Keys) {
            $ast = [System.Management.Automation.Language.Parser]::ParseInput(
                $negatives[$label], [ref]$null, [ref]$null)
            $fn = $ast.Find({
                    param($node)
                    $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
                }, $true)
            $records[$label] = Get-PfbShouldProcessRecord -Function $fn -File $label
        }

        # Assertion 1's predicate.
        $records['no-shouldprocess-declaration'].SupportsShouldProcess | Should -BeFalse
        $records['no-shouldprocess-declaration'].Verb | Should -BeIn $script:stateChangingVerbs

        # Assertion 2's predicate: declared, zero calls.
        $records['declared-never-called'].SupportsShouldProcess | Should -BeTrue
        $records['declared-never-called'].ShouldProcessCalls | Should -Be 0

        # Assertion 5's predicate, in both the wrong-value and the omitted-value shapes. The
        # omitted shape matters on its own: a missing ConfirmImpact defaults to Medium at runtime,
        # so `$null -ne 'High'` has to count as an offender.
        $records['impact-medium'].ConfirmImpact | Should -Be 'Medium'
        $records['impact-absent'].ConfirmImpact | Should -BeNullOrEmpty
        $records['impact-absent'].ConfirmImpact | Should -Not -Be 'High'

        # Assertion 4's predicate.
        $records['readonly-declares'].Verb | Should -BeIn $script:readOnlyVerbs
        $records['readonly-declares'].SupportsShouldProcess | Should -BeTrue
    }
}
