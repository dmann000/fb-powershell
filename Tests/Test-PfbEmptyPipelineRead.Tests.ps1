#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule
}

Describe 'Test-PfbEmptyPipelineRead' {
    It 'returns true for a piped invocation whose final query is empty' {
        InModuleScope PureStorageFlashBladePowerShell {
            function Invoke-PredicateFixture {
                [CmdletBinding()]
                param([Parameter(ValueFromPipeline)][string]$Name)
                begin { $queryParams = @{} }
                process { if ($Name) { $queryParams['names'] = $Name } }
                end { Test-PfbEmptyPipelineRead -Caller $PSCmdlet -QueryParams $queryParams }
            }

            @() | Invoke-PredicateFixture | Should -BeTrue
        }
    }

    It 'returns false for a direct invocation whose final query is empty' {
        InModuleScope PureStorageFlashBladePowerShell {
            function Invoke-PredicateFixture {
                [CmdletBinding()]
                param([Parameter(ValueFromPipeline)][string]$Name)
                end { Test-PfbEmptyPipelineRead -Caller $PSCmdlet -QueryParams @{} }
            }

            Invoke-PredicateFixture | Should -BeFalse
        }
    }

    It 'returns false when a piped invocation has a surviving final query key' {
        InModuleScope PureStorageFlashBladePowerShell {
            function Invoke-PredicateFixture {
                [CmdletBinding()]
                param([Parameter(ValueFromPipeline)][string]$Name)
                end {
                    Test-PfbEmptyPipelineRead -Caller $PSCmdlet `
                        -QueryParams @{ filter = "name='kept'" }
                }
            }

            @() | Invoke-PredicateFixture | Should -BeFalse
        }
    }

    It 'treats a null query hashtable as empty without throwing under StrictMode' {
        InModuleScope PureStorageFlashBladePowerShell {
            # Measured: Set-StrictMode in the It's own scope does NOT cross into the module's
            # session state -- with it set only there, deleting the $null clause from
            # Private/Test-PfbEmptyPipelineRead.ps1 leaves all four tests green on both editions.
            # It has to be set HERE, inside InModuleScope, to reach the callee.
            Set-StrictMode -Version Latest
            function Invoke-PredicateFixture {
                [CmdletBinding()]
                param([Parameter(ValueFromPipeline)][string]$Name)
                end { Test-PfbEmptyPipelineRead -Caller $PSCmdlet -QueryParams $null }
            }

            @() | Invoke-PredicateFixture | Should -BeTrue
        }
    }

    It 'keys off ExpectingInput: one fixture, one empty query, opposite answers' {
        # The ExpectingInput half rested on a single direct-invocation case. This holds the
        # fixture and the final query identical and varies only the invocation form, so
        # deleting the ExpectingInput short-circuit flips the direct half and reds this test.
        InModuleScope PureStorageFlashBladePowerShell {
            function Invoke-PredicateFixture {
                [CmdletBinding()]
                param([Parameter(ValueFromPipeline)][string]$Name)
                begin { $queryParams = @{} }
                process { if ($Name) { $queryParams['names'] = $Name } }
                end { Test-PfbEmptyPipelineRead -Caller $PSCmdlet -QueryParams $queryParams }
            }

            Invoke-PredicateFixture | Should -BeFalse
            @() | Invoke-PredicateFixture | Should -BeTrue
        }
    }

    It 'suppresses a piped invocation whose only surviving key is a non-selector' {
        # The headline #126 case. Before this change `@() | Get-PfbFileSystem -Limit 10` issued an
        # unfiltered read of ten objects the caller never addressed.
        InModuleScope PureStorageFlashBladePowerShell {
            function Invoke-PredicateFixture {
                [CmdletBinding()]
                param([Parameter(ValueFromPipeline)][string]$Name, [int]$Limit)
                end {
                    Test-PfbEmptyPipelineRead -Caller $PSCmdlet -QueryParams @{ limit = 10 }
                }
            }

            @() | Invoke-PredicateFixture -Limit 10 -WarningAction SilentlyContinue | Should -BeTrue
        }
    }

    It 'suppresses when every surviving key is a non-selector, not just one' {
        InModuleScope PureStorageFlashBladePowerShell {
            function Invoke-PredicateFixture {
                [CmdletBinding()]
                param([Parameter(ValueFromPipeline)][string]$Name)
                end {
                    Test-PfbEmptyPipelineRead -Caller $PSCmdlet -QueryParams @{
                        limit = 10; sort = 'name'; destroyed = 'true'
                    }
                }
            }

            @() | Invoke-PredicateFixture -WarningAction SilentlyContinue | Should -BeTrue
        }
    }

    It 'issues when a selector survives alongside a non-selector' {
        # The mirror of the case above, and the assertion that stops this becoming "suppress every
        # piped call". A single selector rescues the request no matter how much scope rides along.
        InModuleScope PureStorageFlashBladePowerShell {
            function Invoke-PredicateFixture {
                [CmdletBinding()]
                param([Parameter(ValueFromPipeline)][string]$Name, [int]$Limit)
                end {
                    Test-PfbEmptyPipelineRead -Caller $PSCmdlet -QueryParams @{
                        limit = 10; names = 'fs1'
                    }
                }
            }

            @() | Invoke-PredicateFixture -Limit 10 | Should -BeFalse
        }
    }

    It 'treats a non-generic selector as a selector without listing it anywhere' {
        # This is the inversion paying for itself. An ALLOWLIST derived from
        # Add-PfbCommonQueryParams -- which hardcodes only the generic names/ids -- would not see
        # policy_names at all and would classify the module's most common selector shape as scope,
        # which is the direction that ISSUES the unfiltered read. Under the denylist policy_names
        # needs no entry and cannot be got wrong.
        InModuleScope PureStorageFlashBladePowerShell {
            function Invoke-PredicateFixture {
                [CmdletBinding()]
                param([Parameter(ValueFromPipeline)][string]$Name)
                end {
                    Test-PfbEmptyPipelineRead -Caller $PSCmdlet `
                        -QueryParams @{ policy_names = 'read-only-policy' }
                }
            }

            @() | Invoke-PredicateFixture | Should -BeFalse
        }
    }

    It 'issues on an unclassified key, which is the documented runtime default' {
        # Pinning the default so it is a decision rather than an accident. It is NOT defended as
        # safe -- Tests/PfbSelectorPolicyCompleteness.Tests.ps1 is what stops an unclassified key
        # reaching a release. If that gate is ever weakened, this test is the record of what the
        # runtime then does.
        InModuleScope PureStorageFlashBladePowerShell {
            function Invoke-PredicateFixture {
                [CmdletBinding()]
                param([Parameter(ValueFromPipeline)][string]$Name)
                end {
                    Test-PfbEmptyPipelineRead -Caller $PSCmdlet `
                        -QueryParams @{ some_future_projection_flag = 'true' }
                }
            }

            @() | Invoke-PredicateFixture | Should -BeFalse
        }
    }

    It 'never suppresses a direct call, whatever it binds' {
        # ExpectingInput still gates everything. A direct Get-PfbX -Limit 10 is a deliberate
        # unfiltered read and stays one -- that is the non-goal the spec states explicitly.
        InModuleScope PureStorageFlashBladePowerShell {
            function Invoke-PredicateFixture {
                [CmdletBinding()]
                param([Parameter(ValueFromPipeline)][string]$Name, [int]$Limit)
                end {
                    Test-PfbEmptyPipelineRead -Caller $PSCmdlet -QueryParams @{ limit = 10 }
                }
            }

            Invoke-PredicateFixture -Limit 10 | Should -BeFalse
        }
    }

    It 'emits the diagnostic it promises on each suppression path' {
        # The predicate is where the split is decided, so assert it here rather than trusting the
        # writer's own tests: no-keys suppression is verbose-only, discarding suppression warns.
        InModuleScope PureStorageFlashBladePowerShell {
            function Invoke-NoKeys {
                [CmdletBinding()]
                param([Parameter(ValueFromPipeline)][string]$Name)
                end { $null = Test-PfbEmptyPipelineRead -Caller $PSCmdlet -QueryParams @{} }
            }
            function Invoke-ScopeOnly {
                [CmdletBinding()]
                param([Parameter(ValueFromPipeline)][string]$Name, [int]$Limit)
                end { $null = Test-PfbEmptyPipelineRead -Caller $PSCmdlet -QueryParams @{ limit = 10 } }
            }

            $quiet = @(@() | Invoke-NoKeys 3>&1)
            @($quiet | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }).Count |
                Should -Be 0 -Because 'an empty pipeline with nothing bound is ordinary no-match operation'

            $loud = @(@() | Invoke-ScopeOnly -Limit 10 3>&1)
            @($loud | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }).Count |
                Should -Be 1 -Because 'the caller typed -Limit 10 and got nothing'
        }
    }

    It 'pins the whole no-key verbose message, which is the only unasserted diagnostic branch' {
        # Task 3 pinned the discarding-keys message end to end; the verbose-only no-keys message was
        # still unasserted anywhere. Stream 4 is verbose (stream 3 above is warning), and the
        # expected text is built from the fixture's own name so a rename cannot silently pass.
        InModuleScope PureStorageFlashBladePowerShell {
            function Invoke-NoKeysVerbose {
                [CmdletBinding()]
                param([Parameter(ValueFromPipeline)][string]$Name)
                end { $null = Test-PfbEmptyPipelineRead -Caller $PSCmdlet -QueryParams @{} }
            }

            $fixtureName = (Get-Command Invoke-NoKeysVerbose).Name
            $expected = "$fixtureName received an empty pipeline, so no object was selected. " +
                'No request was issued.'

            $records = @(@() | Invoke-NoKeysVerbose -Verbose 4>&1)
            $verbose = @($records |
                    Where-Object { $_ -is [System.Management.Automation.VerboseRecord] })
            $verbose.Count | Should -Be 1
            $verbose[0].Message | Should -Be $expected
        }
    }

    It 'issues on an uppercase non-selector key, because the list is matched ordinally' {
        # $script:PfbNonSelectorQueryKeys is built with StringComparer::Ordinal, so LIMIT is not
        # limit: it is unclassified, and an unclassified key reads as a SELECTOR. The request
        # therefore issues.
        #
        # This is deliberate and it is the safe direction. A case-insensitive comparer would make
        # the miss direction SUPPRESS -- a call that worked before #126 silently returning nothing
        # because of how its key was spelled. Ordinal's miss direction is to ISSUE, which is
        # exactly the pre-#126 behaviour of that call, so the worst case is a guard that does not
        # fire rather than a working pipeline that breaks.
        #
        # Nothing in the module writes a query key in any casing but lower snake_case, so this
        # pins a property rather than a live path. It was already pinned against the CI gate's
        # mirror HashSet; this pins it against the predicate that actually decides.
        InModuleScope PureStorageFlashBladePowerShell {
            function Invoke-PredicateFixture {
                [CmdletBinding()]
                param([Parameter(ValueFromPipeline)][string]$Name)
                end { Test-PfbEmptyPipelineRead -Caller $PSCmdlet -QueryParams @{ LIMIT = 10 } }
            }

            @() | Invoke-PredicateFixture | Should -BeFalse
        }
    }

    It 'classifies on key presence and never inspects the value, empty selector included' {
        # Second known gap, documented in the function's comment block. The predicate asks only
        # whether a key is on the non-selector list; @{ names = $null } and @{ names = '' } are
        # both "a selector is present" and both issue. An empty selector reaching the wire is
        # #121's exact harm.
        #
        # It is LATENT, not live: no guarded cmdlet writes an empty selector today.
        # Add-PfbCommonQueryParams gates names/ids on being non-empty, and the only unconditional
        # query writes in Public/ are in Get-PfbLog.ps1 and Remove-PfbFileSystemSession.ps1,
        # neither of which is guarded.
        #
        # This pins CURRENT behaviour so a future value check is a visible decision. Adding one
        # here would be a behaviour change beyond the spec.
        InModuleScope PureStorageFlashBladePowerShell {
            function Invoke-NullSelector {
                [CmdletBinding()]
                param([Parameter(ValueFromPipeline)][string]$Name)
                end { Test-PfbEmptyPipelineRead -Caller $PSCmdlet -QueryParams @{ names = $null } }
            }
            function Invoke-EmptySelector {
                [CmdletBinding()]
                param([Parameter(ValueFromPipeline)][string]$Name)
                end { Test-PfbEmptyPipelineRead -Caller $PSCmdlet -QueryParams @{ names = '' } }
            }

            @() | Invoke-NullSelector | Should -BeFalse
            @() | Invoke-EmptySelector | Should -BeFalse
        }
    }

    It 'throws under -WarningAction Stop where the same call returned data before #126' {
        # The compatibility edge of emitting a warning at all. A scope-only suppression writes a
        # warning, so a caller running -WarningAction Stop (or inheriting $WarningPreference =
        # 'Stop') now gets a terminating ActionPreferenceStopException where the pre-#126 call
        # returned rows.
        #
        # Accepted as OPT-IN: -WarningAction Stop is a caller explicitly asking to be stopped by
        # warnings, and this is a warning. Noted because the writer's own comment block rejects a
        # non-terminating error precisely to avoid breaking -ErrorAction Stop scripts, and the
        # warning has the same effect on the warning preference; see the matching paragraph in
        # Private/Write-PfbEmptyPipelineDiagnostic.ps1.
        InModuleScope PureStorageFlashBladePowerShell {
            function Invoke-ScopeOnlyStop {
                [CmdletBinding()]
                param([Parameter(ValueFromPipeline)][string]$Name, [int]$Limit)
                end {
                    $null = Test-PfbEmptyPipelineRead -Caller $PSCmdlet -QueryParams @{ limit = 10 }
                }
            }
            function Invoke-NoKeysStop {
                [CmdletBinding()]
                param([Parameter(ValueFromPipeline)][string]$Name)
                end { $null = Test-PfbEmptyPipelineRead -Caller $PSCmdlet -QueryParams @{} }
            }

            { @() | Invoke-ScopeOnlyStop -Limit 10 -WarningAction Stop } |
                Should -Throw -ExceptionType ([System.Management.Automation.ActionPreferenceStopException])

            # The control: the no-keys path is verbose-only, so it is unaffected by the warning
            # preference. Without this, the test above would also pass if suppression itself threw.
            { @() | Invoke-NoKeysStop -WarningAction Stop } | Should -Not -Throw
        }
    }
}
