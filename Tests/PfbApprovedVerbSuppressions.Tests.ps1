#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Pins the PSUseApprovedVerbs population at exactly three known functions, and pins
    the shape of the SuppressMessageAttribute that silences them.
.DESCRIPTION
    Three internal helpers in tools/ use the unapproved verb Sort-:

        tools/Build-PfbDeadKeyReport.ps1        Sort-PfbDeadKeyRecords
        tools/lib/PfbPipelineSelectorTools.ps1  Sort-PfbSelectorRecord
        tools/lib/PfbPipelineSelectorTools.ps1  Sort-PfbSelectorString

    They are suppressed rather than renamed. Nothing exports them -- they appear in
    neither the manifest nor the .psm1, and have no reference in Public/ or Private/
    -- while renaming would touch ~27 call sites across five files, two of which
    generate committed derived artifacts, so a missed call site would surface later
    as artifact churn rather than as a clean failure at rename time.

    WHY THE ASSERTIONS ARE EQUALITIES, IN BOTH DIRECTIONS. A suppression that is
    only checked for "no more than N" cannot fail: it accepts a new unapproved verb
    as long as it is suppressed too. Checked only for "at least N", it cannot notice
    that someone renamed one of the three and left a suppression behind that now
    proves nothing. So the count is pinned at exactly 3 and the names are pinned
    exactly, and a legitimate change to either is expected to edit this test.

    WHY THE ATTRIBUTE SHAPE IS ASSERTED SEPARATELY. SuppressMessageAttribute has no
    one-argument constructor. PSScriptAnalyzer accepts ('PSUseApprovedVerbs') from
    the AST and reports the finding as suppressed, but PowerShell throws
    `Cannot find an overload for ".ctor" and the argument count: "1"` when it
    constructs the attribute. An analyzer run therefore cannot tell the working form
    from the broken one: only running it can. Hence the second argument is pinned to
    the empty string, and there is a test that actually exercises each form.

    AND IT THROWS ON INVOCATION, NOT ON DEFINITION -- measured here, not assumed.
    Dot-sourcing a file containing the one-argument form succeeds silently; the
    exception arrives the first time the function is CALLED. So a broken suppression
    in tools/ would survive module load, survive any test that only imports the file,
    and fail in the middle of a build-tool run. The probes below therefore invoke the
    function; a probe that only defined it would pass on both forms and prove
    nothing.

    This file deliberately does not require PSScriptAnalyzer. The live count is
    gated in CI by the analyze job in .github/workflows/cross-platform-tests.yml;
    what is checked here is the population and the attribute shape, from the AST,
    on both editions.
#>

# The three are a fact this test pins, not an input it discovers. It lives in
# BeforeDiscovery because -ForEach is evaluated during Pester's DISCOVERY phase,
# before any BeforeAll has run: defined in BeforeAll it is $null at that point and
# the whole file dies with "Value can not be null or empty array (Parameter
# 'ForEach')" -- a container failure, which reports as 3 passed rather than as the
# 9 tests silently never generated.
BeforeDiscovery {
    $script:expectedUnapproved = @(
        'Sort-PfbDeadKeyRecords'
        'Sort-PfbSelectorRecord'
        'Sort-PfbSelectorString'
    )
}

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot

    $script:approvedVerbs = @(Get-Verb | ForEach-Object { $_.Verb })

    # Every function definition in the source tree, with the file it came from.
    # scripts/ and tools/ are in scope as well as the shipped folders: a bad verb in
    # a build tool is what these three are, so excluding tooling would make the
    # population trivially correct.
    $script:allFunctions = @(
        foreach ($dir in 'Public', 'Private', 'tools', 'scripts') {
            $dirPath = Join-Path $repoRoot $dir
            if (-not (Test-Path -LiteralPath $dirPath)) { continue }
            foreach ($file in Get-ChildItem -LiteralPath $dirPath -Filter '*.ps1' -Recurse -File) {
                $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                    $file.FullName, [ref]$null, [ref]$null)
                foreach ($fn in $ast.FindAll(
                        { $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
                    [pscustomobject]@{
                        Name = $fn.Name
                        File = $file.FullName
                        Ast  = $fn
                    }
                }
            }
        }
    )
}

Describe 'PSUseApprovedVerbs population' {

    It 'found functions to examine at all' {
        # Control. Every assertion below is over $allFunctions, and an empty
        # collection satisfies "the unapproved set is exactly these three" only by
        # accident of an off-by-everything -- a moved directory or a parse failure
        # would otherwise read as a clean pass.
        $allFunctions.Count | Should -BeGreaterThan 100
    }

    It 'has exactly the three known unapproved-verb functions, and no others' {
        $unapproved = @(
            $allFunctions |
                Where-Object { $_.Name -like '*-*' } |
                Where-Object { ($_.Name -split '-', 2)[0] -notin $approvedVerbs } |
                ForEach-Object { $_.Name } |
                Sort-Object -Unique
        )

        # Equality, not containment: this fails on a NEW bad verb and on the silent
        # disappearance of an old one.
        $unapproved | Should -Be ($expectedUnapproved | Sort-Object -Unique)
    }

    It 'pins the count at three' {
        $expectedUnapproved.Count | Should -Be 3
    }
}

Describe 'The suppression attribute on each of the three' {

    It 'carries a SuppressMessageAttribute for PSUseApprovedVerbs: <_>' -ForEach $script:expectedUnapproved {
        $fn = @($allFunctions | Where-Object Name -EQ $_)
        $fn.Count | Should -Be 1 -Because "$_ should be defined exactly once"

        $attrs = @(
            $fn[0].Ast.Body.ParamBlock.Attributes |
                Where-Object { $_.TypeName.FullName -like '*SuppressMessageAttribute' }
        )
        $suppression = @(
            $attrs | Where-Object {
                $_.PositionalArguments.Count -ge 1 -and
                $_.PositionalArguments[0].Value -eq 'PSUseApprovedVerbs'
            }
        )
        $suppression.Count | Should -Be 1
    }

    It 'passes exactly two positional arguments, the second empty: <_>' -ForEach $script:expectedUnapproved {
        $fn = @($allFunctions | Where-Object Name -EQ $_)
        $suppression = @(
            $fn[0].Ast.Body.ParamBlock.Attributes |
                Where-Object { $_.TypeName.FullName -like '*SuppressMessageAttribute' } |
                Where-Object { $_.PositionalArguments[0].Value -eq 'PSUseApprovedVerbs' }
        )[0]

        # Two, not one. PSScriptAnalyzer reports the one-argument form as suppressed
        # because it only ever walks the AST; PowerShell throws when it constructs
        # the attribute. See the next Describe.
        $suppression.PositionalArguments.Count | Should -Be 2
        $suppression.PositionalArguments[1].Value | Should -Be ''
    }

    It 'gives a justification: <_>' -ForEach $script:expectedUnapproved {
        $fn = @($allFunctions | Where-Object Name -EQ $_)
        $suppression = @(
            $fn[0].Ast.Body.ParamBlock.Attributes |
                Where-Object { $_.TypeName.FullName -like '*SuppressMessageAttribute' } |
                Where-Object { $_.PositionalArguments[0].Value -eq 'PSUseApprovedVerbs' }
        )[0]

        $named = @($suppression.NamedArguments | Where-Object ArgumentName -EQ 'Justification')
        $named.Count | Should -Be 1
        $named[0].Argument.Value | Should -Not -BeNullOrEmpty
    }
}

Describe 'The attribute form actually constructs' {
    # This is the point of the file. An analyzer never constructs the attribute, so
    # an analysis-only check cannot distinguish a working suppression from one that
    # throws the moment the file is dot-sourced.

    It 'the two-argument form used in tools/ runs' {
        . ([scriptblock]::Create(@'
function Sort-PfbAttributeShapeProbe {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '',
        Justification = 'probe')]
    [CmdletBinding()]
    param()
    'ran'
}
'@))
        { Sort-PfbAttributeShapeProbe } | Should -Not -Throw
        Sort-PfbAttributeShapeProbe | Should -Be 'ran'
    }

    It 'the one-argument form the analyzer accepts throws when called' {
        # Control for the assertion above: if this ever stops throwing, the two-arg
        # requirement has become a preference and the comment explaining it is stale.
        . ([scriptblock]::Create(@'
function Sort-PfbAttributeShapeProbeBroken {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs')]
    [CmdletBinding()]
    param()
    'ran'
}
'@))
        # Defining it is NOT enough -- that succeeds. The failure is at the call.
        { Sort-PfbAttributeShapeProbeBroken } |
            Should -Throw -ExpectedMessage '*argument count*'
    }
}
