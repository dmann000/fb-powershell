#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Covers the Fusion context gates in Private/Assert-PfbContextSupported.ps1.
#>

BeforeAll {
    Import-Module "$PSScriptRoot/../PureStorageFlashBladePowerShell.psd1" -Force
}

# InModuleScope inside each It (Describe-level fails at discovery here -- see Global
# Constraints). The fixtures are rebuilt per It as plain LOCALS rather than shared from a
# BeforeEach: $ctx needs the private New-PfbContext so it has to be inside module scope, and a
# `$script:` fixture inside InModuleScope would write to the MODULE's script scope and leak past
# the file. The repetition is deliberate and is the price of the block actually running.
Describe 'Assert-PfbContextCapability' {
    It 'allows an endpoint whose entry lists context_names' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $ctx = New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-B'))
            $map = [PSCustomObject]@{
                generatedFrom = @('2.0', '2.26')
                parameterComponentDefaults = [PSCustomObject]@{}
                endpoints = [PSCustomObject]@{
                    'GET /file-systems'   = [PSCustomObject]@{ parameters = [PSCustomObject]@{ context_names = '2.23'; allow_errors = '2.23' }; contextScope = [PSCustomObject]@{ scope = 'array'; provenance = 'default' } }
                    'GET /alert-watchers' = [PSCustomObject]@{ parameters = [PSCustomObject]@{ names = '2.0' };                                 contextScope = [PSCustomObject]@{ scope = 'array'; provenance = 'default' } }
                }
            }
            $fb = [PSCustomObject]@{ Endpoint = 'fb.example'; ApiVersion = '2.26' }
            { Assert-PfbContextCapability -Array $fb -Method 'GET' -Endpoint 'file-systems' -Context $ctx -CapabilityMap $map } |
                Should -Not -Throw
        }
    }
    It 'throws when the entry exists but lacks context_names (the likeliest staleness case)' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $ctx = New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-B'))
            $map = [PSCustomObject]@{
                generatedFrom = @('2.0', '2.26')
                parameterComponentDefaults = [PSCustomObject]@{}
                endpoints = [PSCustomObject]@{
                    'GET /file-systems'   = [PSCustomObject]@{ parameters = [PSCustomObject]@{ context_names = '2.23'; allow_errors = '2.23' }; contextScope = [PSCustomObject]@{ scope = 'array'; provenance = 'default' } }
                    'GET /alert-watchers' = [PSCustomObject]@{ parameters = [PSCustomObject]@{ names = '2.0' };                                 contextScope = [PSCustomObject]@{ scope = 'array'; provenance = 'default' } }
                }
            }
            $fb = [PSCustomObject]@{ Endpoint = 'fb.example'; ApiVersion = '2.26' }
            { Assert-PfbContextCapability -Array $fb -Method 'GET' -Endpoint 'alert-watchers' -Context $ctx -CapabilityMap $map } |
                Should -Throw -ExpectedMessage '*GET /alert-watchers*does not support*'
        }
    }
    It 'throws when there is no entry at all, within the scanned range' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $ctx = New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-B'))
            $map = [PSCustomObject]@{
                generatedFrom = @('2.0', '2.26')
                parameterComponentDefaults = [PSCustomObject]@{}
                endpoints = [PSCustomObject]@{
                    'GET /file-systems'   = [PSCustomObject]@{ parameters = [PSCustomObject]@{ context_names = '2.23'; allow_errors = '2.23' }; contextScope = [PSCustomObject]@{ scope = 'array'; provenance = 'default' } }
                    'GET /alert-watchers' = [PSCustomObject]@{ parameters = [PSCustomObject]@{ names = '2.0' };                                 contextScope = [PSCustomObject]@{ scope = 'array'; provenance = 'default' } }
                }
            }
            $fb = [PSCustomObject]@{ Endpoint = 'fb.example'; ApiVersion = '2.26' }
            { Assert-PfbContextCapability -Array $fb -Method 'GET' -Endpoint 'not-in-map' -Context $ctx -CapabilityMap $map } |
                Should -Throw -ExpectedMessage '*GET /not-in-map*'
        }
    }
    It 'stays permissive when the array is NEWER than the scanned range' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $ctx = New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-B'))
            $map = [PSCustomObject]@{
                generatedFrom = @('2.0', '2.26')
                parameterComponentDefaults = [PSCustomObject]@{}
                endpoints = [PSCustomObject]@{
                    'GET /file-systems'   = [PSCustomObject]@{ parameters = [PSCustomObject]@{ context_names = '2.23'; allow_errors = '2.23' }; contextScope = [PSCustomObject]@{ scope = 'array'; provenance = 'default' } }
                    'GET /alert-watchers' = [PSCustomObject]@{ parameters = [PSCustomObject]@{ names = '2.0' };                                 contextScope = [PSCustomObject]@{ scope = 'array'; provenance = 'default' } }
                }
            }
            # 2.40 is beyond generatedFrom's upper bound, so the map cannot be authoritative.
            $fb = [PSCustomObject]@{ Endpoint = 'fb.example'; ApiVersion = '2.40' }
            { Assert-PfbContextCapability -Array $fb -Method 'GET' -Endpoint 'not-in-map' -Context $ctx -CapabilityMap $map } |
                Should -Not -Throw
            { Assert-PfbContextCapability -Array $fb -Method 'GET' -Endpoint 'alert-watchers' -Context $ctx -CapabilityMap $map } |
                Should -Not -Throw
        }
    }
    It 'treats a local-array context as a context and still throws' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            # Deliberate divergence from the server, which short-circuits a local context
            # before validating. A cmdlet that works only SOME of the time depending on which
            # array the context names is a worse contract than one that fails consistently.
            $map = [PSCustomObject]@{
                generatedFrom = @('2.0', '2.26')
                parameterComponentDefaults = [PSCustomObject]@{}
                endpoints = [PSCustomObject]@{
                    'GET /file-systems'   = [PSCustomObject]@{ parameters = [PSCustomObject]@{ context_names = '2.23'; allow_errors = '2.23' }; contextScope = [PSCustomObject]@{ scope = 'array'; provenance = 'default' } }
                    'GET /alert-watchers' = [PSCustomObject]@{ parameters = [PSCustomObject]@{ names = '2.0' };                                 contextScope = [PSCustomObject]@{ scope = 'array'; provenance = 'default' } }
                }
            }
            $fb = [PSCustomObject]@{ Endpoint = 'fb.example'; ApiVersion = '2.26' }
            $local = New-PfbContext -Entries @((New-PfbContextEntry -Name 'fb.example'))
            { Assert-PfbContextCapability -Array $fb -Method 'GET' -Endpoint 'alert-watchers' -Context $local -CapabilityMap $map } |
                Should -Throw -ExpectedMessage '*does not support*'
        }
    }
    It 'applies the throw to GET as uniformly as to a mutation' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $ctx = New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-B'))
            $map = [PSCustomObject]@{
                generatedFrom = @('2.0', '2.26')
                parameterComponentDefaults = [PSCustomObject]@{}
                endpoints = [PSCustomObject]@{
                    'GET /file-systems'   = [PSCustomObject]@{ parameters = [PSCustomObject]@{ context_names = '2.23'; allow_errors = '2.23' }; contextScope = [PSCustomObject]@{ scope = 'array'; provenance = 'default' } }
                    'GET /alert-watchers' = [PSCustomObject]@{ parameters = [PSCustomObject]@{ names = '2.0' };                                 contextScope = [PSCustomObject]@{ scope = 'array'; provenance = 'default' } }
                }
            }
            $fb = [PSCustomObject]@{ Endpoint = 'fb.example'; ApiVersion = '2.26' }
            foreach ($m in 'GET', 'POST', 'PATCH', 'PUT', 'DELETE') {
                { Assert-PfbContextCapability -Array $fb -Method $m -Endpoint 'alert-watchers' -Context $ctx -CapabilityMap $map } |
                    Should -Throw -ExpectedMessage '*does not support*'
            }
        }
    }
}

# Same It-level InModuleScope rule as above: New-PfbContext, Get-PfbCapabilityMap and
# Assert-PfbContextCardinality are all private, so without module scope every It here raises
# CommandNotFoundException -- which would silently satisfy the throw test below.
Describe 'Assert-PfbContextCardinality' {
    It 'throws for a multi-value context on a non-capable endpoint, naming the narrowing fix' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $multi = New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-B'), (New-PfbContextEntry -Name 'FB-C'))
            $map = Get-PfbCapabilityMap
            { Assert-PfbContextCardinality -Method 'GET' -Endpoint 'presets/workload' -Context $multi -CapabilityMap $map } |
                Should -Throw -ExpectedMessage '*accepts only one context*'
        }
    }
    It 'allows a multi-value context on a capable endpoint' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $multi = New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-B'), (New-PfbContextEntry -Name 'FB-C'))
            $map = Get-PfbCapabilityMap
            { Assert-PfbContextCardinality -Method 'GET' -Endpoint 'file-systems' -Context $multi -CapabilityMap $map } |
                Should -Not -Throw
        }
    }
    It 'never throws for a single-value context, capable or not' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $single = New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-B'))
            $map = Get-PfbCapabilityMap
            { Assert-PfbContextCardinality -Method 'GET' -Endpoint 'presets/workload' -Context $single -CapabilityMap $map } |
                Should -Not -Throw
        }
    }
    # Fix round 1, Important 1. Resolve-PfbParameterComponent returns the map's DEFAULT component
    # for the 256 entries that do not declare context_names, so without a precondition the
    # cardinality rule reads $false for them and this gate advised "narrow the context to a single
    # name" for an endpoint that takes no context at all -- and it fired precisely where
    # Assert-PfbContextCapability deliberately abstains (array beyond the map's scanned range).
    It 'stays silent for an entry that declares no context_names, even beyond map coverage' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $multi = New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-B'), (New-PfbContextEntry -Name 'FB-C'))
            $map = [PSCustomObject]@{
                generatedFrom = @('2.0', '2.28')
                parameterComponentDefaults = [PSCustomObject]@{ context_names = 'Context_names' }
                endpoints = [PSCustomObject]@{
                    'GET /active-directory' = [PSCustomObject]@{ parameters = [PSCustomObject]@{ names = '2.0' } }
                }
            }
            { Assert-PfbContextCardinality -Method 'GET' -Endpoint 'active-directory' -Context $multi -CapabilityMap $map } |
                Should -Not -Throw
        }
    }
    It 'stays silent for an endpoint absent from the map, in either gate order' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $multi = New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-B'), (New-PfbContextEntry -Name 'FB-C'))
            $map = [PSCustomObject]@{
                generatedFrom = @('2.0', '2.28')
                parameterComponentDefaults = [PSCustomObject]@{ context_names = 'Context_names' }
                endpoints = [PSCustomObject]@{}
            }
            { Assert-PfbContextCardinality -Method 'GET' -Endpoint 'not-an-endpoint' -Context $multi -CapabilityMap $map } |
                Should -Not -Throw
        }
    }
}

Describe 'Test-PfbEndpointDeclaresContextNames' {
    It 'is true only when the parameters collection actually lists context_names' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $declares = [PSCustomObject]@{ parameters = [PSCustomObject]@{ context_names = '2.23'; allow_errors = '2.23' } }
            $lacks    = [PSCustomObject]@{ parameters = [PSCustomObject]@{ names = '2.0' } }
            $noParams = [PSCustomObject]@{ contextScope = [PSCustomObject]@{ scope = 'array' } }

            Test-PfbEndpointDeclaresContextNames -EndpointEntry $declares | Should -BeTrue
            Test-PfbEndpointDeclaresContextNames -EndpointEntry $lacks    | Should -BeFalse
            Test-PfbEndpointDeclaresContextNames -EndpointEntry $noParams | Should -BeFalse
            Test-PfbEndpointDeclaresContextNames -EndpointEntry $null     | Should -BeFalse
        }
    }
    It 'ignores a resolvable default component -- only the parameters collection is evidence' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            # The exact confusion behind Important 1: a component resolves for this entry, yet
            # the endpoint declares no context_names.
            $lacks = [PSCustomObject]@{ parameters = [PSCustomObject]@{ names = '2.0' } }
            $defaults = [PSCustomObject]@{ context_names = 'Context_names' }
            $component = Resolve-PfbParameterComponent -EndpointEntry $lacks `
                -ParameterName $script:PfbContextParameterName -ParameterComponentDefaults $defaults
            $component | Should -Be 'Context_names'   # a component IS resolved...
            Test-PfbEndpointDeclaresContextNames -EndpointEntry $lacks | Should -BeFalse   # ...and means nothing
        }
    }
}

# Task 10. Scaffolding rules, all four load-bearing:
#
# 1. InModuleScope goes INSIDE each It. Describe-level fails at discovery in this repo, so the
#    block silently never runs. Every function called below is private, so outside module scope
#    they all raise CommandNotFoundException.
# 2. The map is a plain LOCAL rebuilt per It, never `$script:map` from a BeforeEach: a `$script:`
#    assignment inside InModuleScope writes to the MODULE's script scope and leaks past this file.
#    Get-PfbCapabilityMap memoizes, so re-calling it is nearly free.
# 3. These tests deliberately run against the REAL shipped map rather than a fixture, because the
#    point is partly to pin the shipped contextScope data (see the map-literal test). That is the
#    opposite choice from the capability-gate tests above and it is intentional.
# 4. Every throw assertion pins a message substring taken from the actual `throw`. A bare
#    `Should -Throw` is satisfied by CommandNotFoundException, so it would pass in RED before the
#    function exists and keep passing however the real throw is worded.
Describe 'Assert-PfbContextKindMatchesScope' {
    It 'rejects a bare fleet name on an array-scoped endpoint' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $map = Get-PfbCapabilityMap
            $fleet = New-PfbContext -Entries @((New-PfbContextEntry -Name 'cc-test-fleet' -Kind 'Fleet'))
            { Assert-PfbContextKindMatchesScope -Method 'GET' -Endpoint 'file-systems' -Context $fleet -CapabilityMap $map } |
                Should -Throw -ExpectedMessage '*array-scoped*'
        }
    }
    # Titles below say "fleet-dot-arrays", not the angle-bracket form: Pester reads <...> in an It
    # name as a -ForEach data placeholder and expands it to $null when there is no data.
    It 'suggests fleet-dot-arrays in the array-scoped rejection' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $map = Get-PfbCapabilityMap
            $fleet = New-PfbContext -Entries @((New-PfbContextEntry -Name 'cc-test-fleet' -Kind 'Fleet'))
            { Assert-PfbContextKindMatchesScope -Method 'GET' -Endpoint 'file-systems' -Context $fleet -CapabilityMap $map } |
                Should -Throw -ExpectedMessage '*.arrays*'
        }
    }
    It 'allows an array name on an array-scoped endpoint' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $map = Get-PfbCapabilityMap
            $arr = New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-B'))
            { Assert-PfbContextKindMatchesScope -Method 'GET' -Endpoint 'file-systems' -Context $arr -CapabilityMap $map } |
                Should -Not -Throw
        }
    }
    It 'allows fleet-dot-arrays on an array-scoped endpoint' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $map = Get-PfbCapabilityMap
            $fanout = New-PfbContext -Entries @((New-PfbContextEntry -Name 'cc-test-fleet' -Kind 'Fleet' -Form 'AllArrays'))
            { Assert-PfbContextKindMatchesScope -Method 'GET' -Endpoint 'file-systems' -Context $fanout -CapabilityMap $map } |
                Should -Not -Throw
        }
    }
    It 'rejects an array name on a fleet-scoped WRITE, on every write verb' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $map = Get-PfbCapabilityMap
            $arr = New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-B'))
            foreach ($m in 'POST', 'PUT', 'PATCH', 'DELETE') {
                { Assert-PfbContextKindMatchesScope -Method $m -Endpoint 'presets/workload' -Context $arr -CapabilityMap $map } |
                    Should -Throw -ExpectedMessage '*requires a bare fleet context*'
            }
        }
    }
    It 'allows a bare fleet name on a fleet-scoped write' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $map = Get-PfbCapabilityMap
            $fleet = New-PfbContext -Entries @((New-PfbContextEntry -Name 'cc-test-fleet' -Kind 'Fleet'))
            { Assert-PfbContextKindMatchesScope -Method 'POST' -Endpoint 'presets/workload' -Context $fleet -CapabilityMap $map } |
                Should -Not -Throw
        }
    }
    It 'rejects fleet-dot-arrays on a fleet-scoped endpoint (code 13 on the wire)' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $map = Get-PfbCapabilityMap
            $fanout = New-PfbContext -Entries @((New-PfbContextEntry -Name 'cc-test-fleet' -Kind 'Fleet' -Form 'AllArrays'))
            { Assert-PfbContextKindMatchesScope -Method 'POST' -Endpoint 'presets/workload' -Context $fanout -CapabilityMap $map } |
                Should -Throw -ExpectedMessage '*requires a bare fleet context*'
        }
    }
    It 'rejects an array name on GET /presets/workload and allows the fleet name' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            # Ruling: fleet. GET behaves like the writes. Measured from a REMOTE member (so the
            # local short-circuit cannot mask it): a remote array name and <fleet>.arrays both
            # return code 13, and only the bare fleet name is accepted, on every verb.
            $map = Get-PfbCapabilityMap
            $arr   = New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-B'))
            $fleet = New-PfbContext -Entries @((New-PfbContextEntry -Name 'cc-test-fleet' -Kind 'Fleet'))
            { Assert-PfbContextKindMatchesScope -Method 'GET' -Endpoint 'presets/workload' -Context $arr   -CapabilityMap $map } |
                Should -Throw -ExpectedMessage '*requires a bare fleet context*'
            { Assert-PfbContextKindMatchesScope -Method 'GET' -Endpoint 'presets/workload' -Context $fleet -CapabilityMap $map } |
                Should -Not -Throw
        }
    }
    It 'throws for a LOCAL array name on GET /presets/workload too' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            # The server returns 200 here via the short-circuit. The module diverges on purpose:
            # a cmdlet that works only when the context happens to name the local array is a
            # worse contract than one that fails consistently.
            $map = Get-PfbCapabilityMap
            $local = New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-A'))
            { Assert-PfbContextKindMatchesScope -Method 'GET' -Endpoint 'presets/workload' -Context $local -CapabilityMap $map } |
                Should -Throw -ExpectedMessage '*requires a bare fleet context*'
        }
    }
    It "pins the map literal so a regeneration cannot silently flip this test's meaning" {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            # NOT because a scope flip would otherwise pass silently -- measured, it would not:
            # flipping GET /presets/workload to scope=array fails four sibling Its independently.
            # What this pins buys is LOCALISATION. Without it, a map regression surfaces as a
            # scatter of confusing throw/no-throw mismatches across this Describe; with it, one
            # obviously-named assertion says "the shipped map changed" and the rest is noise.
            $map = Get-PfbCapabilityMap
            $map.endpoints.'GET /presets/workload'.contextScope.scope | Should -Be 'fleet'
        }
    }
    It 'suppresses the check entirely for contextScope unknown' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            # 19 operations are 'unknown'. The gate must DEGRADE on absent metadata, not throw.
            $map = Get-PfbCapabilityMap
            $fleet = New-PfbContext -Entries @((New-PfbContextEntry -Name 'cc-test-fleet' -Kind 'Fleet'))
            $unknown = @($map.endpoints.PSObject.Properties |
                Where-Object { $_.Value.contextScope.scope -eq 'unknown' })
            @($unknown).Count | Should -BeGreaterThan 0 -Because 'this test and its Assert-PfbContextRequired twin index [0] of this list, and would fail on a null index if the shipped map had none'
            $parts = $unknown[0].Name -split ' ', 2
            { Assert-PfbContextKindMatchesScope -Method $parts[0] -Endpoint $parts[1].TrimStart('/') -Context $fleet -CapabilityMap $map } |
                Should -Not -Throw
        }
    }
    It 'rejects a TopologyGroup AllArrays context on a fleet-scoped endpoint' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $map = Get-PfbCapabilityMap
            $grp = New-PfbContext -Entries @((New-PfbContextEntry -Name 'zz-claude-tg-parent' -Kind 'TopologyGroup' -Form 'AllArrays'))
            { Assert-PfbContextKindMatchesScope -Method 'POST' -Endpoint 'presets/workload' -Context $grp -CapabilityMap $map } |
                Should -Throw -ExpectedMessage '*requires a bare fleet context*'
        }
    }
}

Describe 'Assert-PfbContextRequired' {
    # Same four scaffolding rules as above. Note this gate is called from the ELSE branch in
    # Invoke-PfbApiRequest, so unlike the three shape gates it legitimately sees BOTH the unset
    # and the explicitly-empty context. Do not add an empty-context bypass to it.
    It 'throws for a fleet-scoped mutation with no context, before the wire' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $map = Get-PfbCapabilityMap
            foreach ($m in 'POST', 'PUT', 'PATCH', 'DELETE') {
                { Assert-PfbContextRequired -Method $m -Endpoint 'presets/workload' -QueryParams $null -CapabilityMap $map } |
                    Should -Throw -ExpectedMessage '*Set-PfbContext*'
            }
        }
    }
    It 'names Invoke-PfbInContext as the per-call alternative' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $map = Get-PfbCapabilityMap
            { Assert-PfbContextRequired -Method 'POST' -Endpoint 'presets/workload' -QueryParams $null -CapabilityMap $map } |
                Should -Throw -ExpectedMessage '*Invoke-PfbInContext*'
        }
    }
    It 'does NOT throw for an unfiltered GET on a fleet-scoped endpoint' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            # The unfiltered read with no context WORKS -- it returns the locally replicated copy,
            # and it is the only preset operation that functions on main today. Throwing here
            # would break Get-PfbPresetWorkload.
            $map = Get-PfbCapabilityMap
            { Assert-PfbContextRequired -Method 'GET' -Endpoint 'presets/workload' -QueryParams $null -CapabilityMap $map } |
                Should -Not -Throw
            { Assert-PfbContextRequired -Method 'GET' -Endpoint 'presets/workload' -QueryParams @{ limit = 10 } -CapabilityMap $map } |
                Should -Not -Throw
        }
    }
    It 'DOES throw for a name-scoped GET on a fleet-scoped endpoint' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            # ?names= with no context returns code 6 "Preset does not exist." The local view is
            # list-only: enough to enumerate, not enough to resolve a name against. This is the
            # case a verb-shaped gate misses in the other direction.
            $map = Get-PfbCapabilityMap
            { Assert-PfbContextRequired -Method 'GET' -Endpoint 'presets/workload' -QueryParams @{ names = 'p1' } -CapabilityMap $map } |
                Should -Throw -ExpectedMessage '*Set-PfbContext*'
        }
    }
    It 'treats ?ids= the same as ?names=' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $map = Get-PfbCapabilityMap
            { Assert-PfbContextRequired -Method 'GET' -Endpoint 'presets/workload' -QueryParams @{ ids = 'abc' } -CapabilityMap $map } |
                Should -Throw -ExpectedMessage '*requires a fleet context*'
        }
    }
    # Fix round 2. Live-measured on FB-B/FB-C with NO context set: a name-scoped read on the three
    # fleet-scoped topology-group GETs returns 200, so the scope-derived rule was rejecting calls
    # the array answers happily. The rule is now an evidence-backed allowlist.
    #   GET /topology-groups?names=zz-claude-tg-parent                  -> 200, 1 item
    #   GET /topology-groups/members?topology_group_names=<that group>   -> 200, 2 items
    #   GET /topology-groups/arrays?topology_group_names=<that group>    -> 200, 2 items
    It 'does not throw for a name-scoped context-free GET on the topology-group endpoints' -ForEach @(
        @{ Ep = 'topology-groups' }
        @{ Ep = 'topology-groups/members' }
        @{ Ep = 'topology-groups/arrays' }
    ) {
        InModuleScope 'PureStorageFlashBladePowerShell' -Parameters @{ Ep = $Ep } {
            param($Ep)
            $map = Get-PfbCapabilityMap
            # Pin that these really are fleet-scoped, so the test cannot be satisfied by the scope
            # early-return instead of the allowlist -- that would make it prove nothing.
            $map.endpoints."GET /$Ep".contextScope.scope | Should -Be 'fleet'
            { Assert-PfbContextRequired -Method 'GET' -Endpoint $Ep -QueryParams @{ names = 'zz-claude-tg-parent' } -CapabilityMap $map } |
                Should -Not -Throw
            { Assert-PfbContextRequired -Method 'GET' -Endpoint $Ep -QueryParams @{ ids = 'abc' } -CapabilityMap $map } |
                Should -Not -Throw
        }
    }
    It 'pins the name-scoped allowlist to what was actually measured' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            # Makes "someone widened this without a measurement" a test failure in both directions.
            $script:PfbNameScopedContextRequiredEndpoints | Should -Contain 'GET /presets/workload'
            foreach ($ep in 'GET /topology-groups', 'GET /topology-groups/members', 'GET /topology-groups/arrays') {
                $script:PfbNameScopedContextRequiredEndpoints | Should -Not -Contain $ep -Because "a name-scoped context-free read returns 200 on $ep, so requiring a context there rejects a working call"
            }
        }
    }
    It 'does not throw for an array-scoped endpoint with no context, name-scoped or not' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $map = Get-PfbCapabilityMap
            { Assert-PfbContextRequired -Method 'GET'  -Endpoint 'file-systems' -QueryParams @{ names = 'fs1' } -CapabilityMap $map } | Should -Not -Throw
            { Assert-PfbContextRequired -Method 'POST' -Endpoint 'file-systems' -QueryParams $null            -CapabilityMap $map } | Should -Not -Throw
        }
    }
    It 'does not throw for an unknown-scope endpoint with no context, on either side of the GET split' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            # The scope early-return is what must be pinned here, so the two cases are chosen
            # DELIBERATELY rather than taken from [0] of the unknown list. An unfiltered GET
            # returns early on the verb branch as well, so it alone cannot detect a deleted scope
            # check; a non-GET, and a name-scoped GET, both reach the throw if the scope check
            # goes. Picking [0] and hoping it is a non-GET makes the kill power accidental.
            $map = Get-PfbCapabilityMap
            $unknown = @($map.endpoints.PSObject.Properties | Where-Object { $_.Value.contextScope.scope -eq 'unknown' })
            $nonGet = @($unknown | Where-Object { $_.Name -notlike 'GET *' })
            $get    = @($unknown | Where-Object { $_.Name -like 'GET *' })
            @($nonGet).Count | Should -BeGreaterThan 0 -Because 'a non-GET unknown-scope endpoint is what detects a deleted scope early-return'
            # The GET partition is asserted non-empty so the GET probe below exercises a real
            # endpoint rather than vacuously passing on a $null key. It does NOT contribute kill
            # power against a deleted scope early-return: the allowlist added in fix round 2
            # returns before the throw for every unknown-scope GET, so the non-GET partition above
            # is what detects that mutation. Measured, not assumed.
            @($get).Count    | Should -BeGreaterThan 0 -Because 'the GET probe below needs a real unknown-scope GET endpoint to be meaningful'

            $p = $nonGet[0].Name -split ' ', 2
            { Assert-PfbContextRequired -Method $p[0] -Endpoint $p[1].TrimStart('/') -QueryParams $null -CapabilityMap $map } |
                Should -Not -Throw

            $p = $get[0].Name -split ' ', 2
            { Assert-PfbContextRequired -Method $p[0] -Endpoint $p[1].TrimStart('/') -QueryParams @{ names = 'x' } -CapabilityMap $map } |
                Should -Not -Throw
        }
    }
}

Describe 'Assert-PfbContextAuthorizationModel' {
    It 'throws for a static-model admin setting a cross-array context' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $fb = [PSCustomObject]@{ Endpoint = 'fb.example'; Username = 'pureuser'; AuthorizationModel = 'static' }
            $ctx = New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-B'))
            { Assert-PfbContextAuthorizationModel -Array $fb -Context $ctx } |
                Should -Throw -ExpectedMessage '*dynamic-authorization-model*'
        }
    }
    It 'allows a dynamic-model admin' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $fb = [PSCustomObject]@{ Endpoint = 'fb.example'; Username = 'juemerson'; AuthorizationModel = 'dynamic' }
            $ctx = New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-B'))
            { Assert-PfbContextAuthorizationModel -Array $fb -Context $ctx } | Should -Not -Throw
        }
    }
    It 'FAILS OPEN when the model could not be determined' {
        # OAuth2 client with no username, or GET /admins 403 under a restrictive access policy.
        # The gate is diagnostic, never a security boundary -- blocking here would deny
        # legitimate sessions and protect nothing, since the wire still answers code 20.
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $fb = [PSCustomObject]@{ Endpoint = 'fb.example'; Username = $null; AuthorizationModel = $null }
            $ctx = New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-B'))
            { Assert-PfbContextAuthorizationModel -Array $fb -Context $ctx } | Should -Not -Throw
        }
    }
    It 'mentions that pureuser and other LOCAL accounts are all static' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $fb = [PSCustomObject]@{ Endpoint = 'fb.example'; Username = 'pureuser'; AuthorizationModel = 'static' }
            $ctx = New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-B'))
            { Assert-PfbContextAuthorizationModel -Array $fb -Context $ctx } |
                Should -Throw -ExpectedMessage '*local*'
        }
    }
    It 'names the offending context values in the message' {
        # This is what earns -Context its mandatory slot. It does not change WHETHER the gate
        # throws (there is no local-array exemption), but a caller who set several names needs to
        # see which ones were rejected, in their wire form.
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $fb = [PSCustomObject]@{ Endpoint = 'fb.example'; Username = 'pureuser'; AuthorizationModel = 'static' }
            $ctx = New-PfbContext -Entries @(
                (New-PfbContextEntry -Name 'FB-B'),
                (New-PfbContextEntry -Name 'fleet-prod' -Kind 'Fleet' -Form 'AllArrays')
            )
            { Assert-PfbContextAuthorizationModel -Array $fb -Context $ctx } |
                Should -Throw -ExpectedMessage '*FB-B, fleet-prod.arrays*'
        }
    }
    It 'throws for a static-model admin even when the context names only the connected array' {
        # No local-array exemption (maintainer ruling 2026-08-05). The connection object carries
        # no array NAME to compare against -- only Endpoint, an IP or hostname -- so the old
        # exemption could only ever have matched an invented fixture.
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $fb = [PSCustomObject]@{ Endpoint = 'fb.example'; Username = 'pureuser'; AuthorizationModel = 'static' }
            $ctx = New-PfbContext -Entries @((New-PfbContextEntry -Name 'fb.example'))
            { Assert-PfbContextAuthorizationModel -Array $fb -Context $ctx } |
                Should -Throw -ExpectedMessage '*dynamic-authorization-model*'
        }
    }
}
