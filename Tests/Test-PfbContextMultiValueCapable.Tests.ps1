#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Direct tests for the Fusion context cardinality rule in
    Private/Test-PfbContextMultiValueCapable.ps1.
.DESCRIPTION
    The predicate shipped in #73 with no dedicated test file -- its coverage was indirect via
    PfbContextRuleTools.Tests.ps1. Phase 1 makes it a runtime gate, so it owes direct tests.
#>

BeforeAll {
    Import-Module "$PSScriptRoot/../PureStorageFlashBladePowerShell.psd1" -Force
}

# InModuleScope inside each It, never around the Describe body (Describe-level fails at
# discovery here and the block silently never runs -- see Global Constraints). Each It below is
# already self-contained, so this is a pure re-scoping with no fixture changes.
Describe 'Test-PfbContextMultiValueCapable' {
    It 'is capable only with BOTH the multi-value component and allow_errors' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            Test-PfbContextMultiValueCapable -Method 'GET' -ContextComponent 'Context_names_get' -DeclaresAllowErrors $true  | Should -BeTrue
            Test-PfbContextMultiValueCapable -Method 'GET' -ContextComponent 'Context_names_get' -DeclaresAllowErrors $false | Should -BeFalse
            Test-PfbContextMultiValueCapable -Method 'GET' -ContextComponent 'Context_names'     -DeclaresAllowErrors $true  | Should -BeFalse
        }
    }
    It 'does not use the HTTP verb when a component signal exists -- the verb rule is FALSIFIED' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            # Four fleet-scoped GETs reject any two-name context with code 15. A GET is not
            # multi-value-capable by virtue of being a GET. Do not reintroduce the verb rule.
            Test-PfbContextMultiValueCapable -Method 'GET'  -ContextComponent 'Context_names_get' -DeclaresAllowErrors $false | Should -BeFalse
            Test-PfbContextMultiValueCapable -Method 'POST' -ContextComponent 'Context_names_get' -DeclaresAllowErrors $true  | Should -BeTrue
        }
    }
    It 'falls back to the verb ONLY with no component signal at all' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            Test-PfbContextMultiValueCapable -Method 'GET' -ContextComponent $null -DeclaresAllowErrors $false | Should -BeTrue
        }
    }
    It 'throws rather than assuming $false for a verb it has no verdict for' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            { Test-PfbContextMultiValueCapable -Method 'HEAD' -ContextComponent $null -DeclaresAllowErrors $false } |
                Should -Throw -ExpectedMessage '*no context-cardinality verdict*'
        }
    }
    It 'agrees with the committed map on all four fleet-scoped GETs (code 15 on the wire)' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $map = Get-PfbCapabilityMap
            foreach ($key in 'GET /presets/workload', 'GET /topology-groups', 'GET /topology-groups/arrays', 'GET /topology-groups/members') {
                $entry = $map.endpoints.$key
                $component = Resolve-PfbParameterComponent -EndpointEntry $entry -ParameterName $script:PfbContextParameterName -ParameterComponentDefaults $map.parameterComponentDefaults
                $declares = @($entry.parameters.PSObject.Properties.Name) -contains $script:PfbAllowErrorsParameterName
                Test-PfbContextMultiValueCapable -Method 'GET' -ContextComponent $component -DeclaresAllowErrors $declares |
                    Should -BeFalse -Because "$key returns 400 code 15 on any two-name context"
            }
        }
    }
}

Describe 'Cardinality rule single-home invariant' {
    # The brief's filter was `-notmatch '^\s*#'`, which also keeps the four prose mentions
    # inside this function's <# .DESCRIPTION #> block (they are inside a block comment, not
    # line comments), so it can never reach 1. What the spec risk table actually cares about is
    # that exactly one place in Private/ COMPARES against the component literal -- pinned here
    # by matching the comparison itself, plus a whole-file sweep proving no other file in
    # Private/ mentions the literal outside a line comment.
    It 'has exactly one Context_names_get comparison in Private/' {
        $all = Select-String -Path (Join-Path $PSScriptRoot '../Private/*.ps1') -Pattern 'Context_names_get'

        $comparisons = @($all | Where-Object { $_.Line -match "-eq\s+'Context_names_get'" })
        $comparisons.Count | Should -Be 1
        (Split-Path $comparisons[0].Path -Leaf) | Should -Be 'Test-PfbContextMultiValueCapable.ps1'

        $strayFiles = @($all |
            Where-Object { $_.Line -notmatch '^\s*#' } |
            Where-Object { (Split-Path $_.Path -Leaf) -ne 'Test-PfbContextMultiValueCapable.ps1' })
        $strayFiles.Count | Should -Be 0
    }
}
