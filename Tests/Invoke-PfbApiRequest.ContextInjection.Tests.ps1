#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Confirms Invoke-PfbApiRequest injects the resolved Fusion context as context_names at the
    single choke point, before the capability version gate runs, without polluting the
    caller's query-parameter hashtable.
#>

BeforeAll {
    Import-Module "$PSScriptRoot/../PureStorageFlashBladePowerShell.psd1" -Force
}

# Two scaffolding rules, both load-bearing:
#
# 1. InModuleScope goes inside each It. Describe-level fails at discovery in this repo, so
#    the block silently never runs. The fixture is rebuilt per It rather than in a shared
#    BeforeEach, because it calls the private New-PfbContext and so must be inside module
#    scope; the repetition is the price of the block actually executing.
#
# 2. Captures use a List and .Add(), never `$script:x = ...` from inside a Mock body. A mock
#    body can READ the test's variables, but an assignment inside it does not propagate back
#    out -- and `$script:` inside InModuleScope writes to the MODULE's script scope, which is
#    leaked state that outlives the file. Mutating a list the test already holds is
#    scope-safe either way. `$script:PfbContextParameterName` inside a mock body is fine and
#    intended: that IS a real module constant, and we are in module scope to read it.
Describe 'context injection in Invoke-PfbApiRequest' {
    It 'injects context_names BEFORE Assert-PfbApiCapability sees the query params' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            # This is the ordering bug's only real detector. A test that supplies
            # context_names in -QueryParams itself cannot detect it -- an early live test
            # "confirmed" the gate that way and exercised a path the shipped code never takes.
            $fb = [PSCustomObject]@{
                PSTypeName = 'PureStorage.FlashBlade.Connection'
                Endpoint = 'fb.example'; ApiVersion = '2.26'; AuthToken = 't'; AuthMethod = 'ApiToken'
                DefaultContext = (New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-B')))
                ContextOverride = $null; AdminLocality = $null
            }
            $seen = [System.Collections.Generic.List[object]]::new()
            Mock -CommandName Assert-PfbApiCapability -MockWith {
                $seen.Add($QueryParams[$script:PfbContextParameterName])
            }
            Mock -CommandName Invoke-RestMethod -MockWith { [PSCustomObject]@{ items = @() } }
            Invoke-PfbApiRequest -Array $fb -Method 'GET' -Endpoint 'file-systems' | Out-Null
            @($seen).Count | Should -Be 1        # the gate ran exactly once...
            $seen[0]       | Should -Be 'FB-B'   # ...and context_names was already there
        }
    }
    It 'renders the .arrays form on the wire' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $fb = [PSCustomObject]@{
                PSTypeName = 'PureStorage.FlashBlade.Connection'
                Endpoint = 'fb.example'; ApiVersion = '2.26'; AuthToken = 't'; AuthMethod = 'ApiToken'
                DefaultContext = (New-PfbContext -Entries @((New-PfbContextEntry -Name 'cc-test-fleet' -Kind 'Fleet' -Form 'AllArrays')))
                ContextOverride = $null; AdminLocality = $null
            }
            $uris = [System.Collections.Generic.List[string]]::new()
            Mock -CommandName Assert-PfbApiCapability -MockWith {}
            Mock -CommandName Invoke-RestMethod -MockWith { $uris.Add($Uri); [PSCustomObject]@{ items = @() } }
            Invoke-PfbApiRequest -Array $fb -Method 'GET' -Endpoint 'file-systems' | Out-Null
            $uris[0] | Should -BeLike '*context_names=cc-test-fleet.arrays*'
        }
    }
    It 'keeps context_names on page 2 and beyond' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $fb = [PSCustomObject]@{
                PSTypeName = 'PureStorage.FlashBlade.Connection'
                Endpoint = 'fb.example'; ApiVersion = '2.26'; AuthToken = 't'; AuthMethod = 'ApiToken'
                DefaultContext = (New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-B')))
                ContextOverride = $null; AdminLocality = $null
            }
            $uris = [System.Collections.Generic.List[string]]::new()
            Mock -CommandName Assert-PfbApiCapability -MockWith {}
            Mock -CommandName Invoke-RestMethod -MockWith {
                $uris.Add($Uri)
                if ($uris.Count -eq 1) { [PSCustomObject]@{ items = @(1); continuation_token = 'tok'; total_item_count = 2 } }
                else                   { [PSCustomObject]@{ items = @(2); continuation_token = $null; total_item_count = 2 } }
            }
            Invoke-PfbApiRequest -Array $fb -Method 'GET' -Endpoint 'arrays/space' -AutoPaginate | Out-Null
            @($uris).Count | Should -Be 2
            $uris[1] | Should -BeLike '*context_names=FB-B*'
        }
    }
    It 'injects nothing when no context is set' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $fb = [PSCustomObject]@{
                PSTypeName = 'PureStorage.FlashBlade.Connection'
                Endpoint = 'fb.example'; ApiVersion = '2.26'; AuthToken = 't'; AuthMethod = 'ApiToken'
                DefaultContext = $null; ContextOverride = $null; AdminLocality = $null
            }
            $uris = [System.Collections.Generic.List[string]]::new()
            Mock -CommandName Assert-PfbApiCapability -MockWith {}
            Mock -CommandName Invoke-RestMethod -MockWith { $uris.Add($Uri); [PSCustomObject]@{ items = @() } }
            Invoke-PfbApiRequest -Array $fb -Method 'GET' -Endpoint 'file-systems' | Out-Null
            $uris[0] | Should -Not -BeLike '*context_names*'
        }
    }
    It 'injects nothing for an explicit empty context' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            # Explicit no-context: a context object EXISTS but carries no entries. It must
            # inject nothing AND must not fall through to the DefaultContext below it.
            $fb = [PSCustomObject]@{
                PSTypeName = 'PureStorage.FlashBlade.Connection'
                Endpoint = 'fb.example'; ApiVersion = '2.26'; AuthToken = 't'; AuthMethod = 'ApiToken'
                DefaultContext = (New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-B')))
                ContextOverride = (New-PfbContext -Entries @()); AdminLocality = $null
            }
            $uris = [System.Collections.Generic.List[string]]::new()
            # The URI alone CANNOT pin this: both downstream sinks (ConvertTo-PfbQueryString and
            # Assert-PfbApiCapability's query-param loop) discard empty-string values, so an
            # injected context_names = '' is invisible in the URI. Mutating the guard to bare
            # `if ($resolvedContext)` therefore left the whole suite green. So capture what the
            # gate ACTUALLY receives: on correct code the key must not be present at all.
            #
            # $QueryParams is legitimately still $null here (the caller passed none), and
            # ContainsKey on $null throws -- so test presence with an explicit null check rather
            # than letting the throw stand in for the assertion, which would hide a regression.
            $keyPresent = [System.Collections.Generic.List[bool]]::new()
            Mock -CommandName Assert-PfbApiCapability -MockWith {
                $keyPresent.Add($null -ne $QueryParams -and $QueryParams.ContainsKey($script:PfbContextParameterName))
            }
            Mock -CommandName Invoke-RestMethod -MockWith { $uris.Add($Uri); [PSCustomObject]@{ items = @() } }
            Invoke-PfbApiRequest -Array $fb -Method 'GET' -Endpoint 'alert-watchers' | Out-Null
            @($keyPresent).Count | Should -Be 1      # the gate ran exactly once...
            $keyPresent[0] | Should -BeFalse         # ...and saw no context_names key at all
            $uris[0] | Should -Not -BeLike '*context_names*'
        }
    }
    It 'does not pollute the caller hashtable with context_names' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $fb = [PSCustomObject]@{
                PSTypeName = 'PureStorage.FlashBlade.Connection'
                Endpoint = 'fb.example'; ApiVersion = '2.26'; AuthToken = 't'; AuthMethod = 'ApiToken'
                DefaultContext = (New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-B')))
                ContextOverride = $null; AdminLocality = $null
            }
            $callerParams = @{ limit = 5 }
            Mock -CommandName Assert-PfbApiCapability -MockWith {}
            Mock -CommandName Invoke-RestMethod -MockWith { [PSCustomObject]@{ items = @() } }
            Invoke-PfbApiRequest -Array $fb -Method 'GET' -Endpoint 'file-systems' -QueryParams $callerParams | Out-Null
            $callerParams.ContainsKey($script:PfbContextParameterName) | Should -BeFalse
        }
    }
}

# Fix round 1, Important 2. Both context gates were entirely unpinned at the call site: deleting
# either call from Invoke-PfbApiRequest left every relevant test green, so both gates could be
# unwired from the request path unnoticed. Tasks 10 and 11 add two more gates to this same site,
# so the wiring gets its own detector now.
Describe 'context gate wiring in Invoke-PfbApiRequest' {
    It 'calls all four shape gates in order, capability before cardinality before kindMatchesScope before adminLocality' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $fb = [PSCustomObject]@{
                PSTypeName = 'PureStorage.FlashBlade.Connection'
                Endpoint = 'fb.example'; ApiVersion = '2.26'; AuthToken = 't'; AuthMethod = 'ApiToken'
                DefaultContext = (New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-B')))
                ContextOverride = $null; AdminLocality = $null
            }
            # A List with .Add() -- an assignment inside a Mock body does not propagate out, and
            # `$script:` inside InModuleScope would write to the MODULE's script scope.
            $calls = [System.Collections.Generic.List[object]]::new()
            Mock -CommandName Assert-PfbContextCapability  -MockWith { $calls.Add('capability') }
            Mock -CommandName Assert-PfbContextCardinality -MockWith { $calls.Add('cardinality') }
            Mock -CommandName Assert-PfbContextKindMatchesScope -MockWith { $calls.Add('kindMatchesScope') }
            Mock -CommandName Assert-PfbContextAdminLocality -MockWith { $calls.Add('adminLocality') }
            Mock -CommandName Assert-PfbApiCapability -MockWith {}
            Mock -CommandName Invoke-RestMethod -MockWith { [PSCustomObject]@{ items = @() } }

            Invoke-PfbApiRequest -Array $fb -Method 'GET' -Endpoint 'file-systems' | Out-Null

            @($calls).Count | Should -Be 4 -Because 'all four shape gates must fire from the request path; a lower count means one call was deleted or never wired'
            $calls[0] | Should -Be 'capability'  -Because 'the capability gate must rule on "endpoint takes no context at all" first'
            $calls[1] | Should -Be 'cardinality'
            $calls[2] | Should -Be 'kindMatchesScope' -Because 'it runs after cardinality: a wrong-KIND context aimed at an endpoint that takes no context at all should hear about capability first, not about scope'
            $calls[3] | Should -Be 'adminLocality' -Because 'the admin-locality gate is diagnostic and endpoint-independent, so the three endpoint-specific gates rule first'
        }
    }
    # The It above records only the context gates, so it holds regardless of where the VERSION
    # gate sits among them -- it cannot detect the admin-locality gate drifting back above
    # Assert-PfbApiCapability. This one adds the version gate to the recording and pins the whole
    # sequence. The ruling it encodes was measured in Task 10: a gate that injects nothing and
    # consults no endpoint must run BELOW the version gate, or a static admin on a REST 2.20 array
    # calling an endpoint that needs 2.23 is told to go obtain an LDAP admin and only afterwards
    # learns the real blocker was firmware. Assert-PfbContextCapability defers "recorded but array
    # too old" to Assert-PfbApiCapability by design, so gates 1-3 do not catch that case.
    It 'runs the version gate after the three injecting gates but BEFORE the admin-locality gate' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $fb = [PSCustomObject]@{
                PSTypeName = 'PureStorage.FlashBlade.Connection'
                Endpoint = 'fb.example'; ApiVersion = '2.26'; AuthToken = 't'; AuthMethod = 'ApiToken'
                DefaultContext = (New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-B')))
                ContextOverride = $null; AdminLocality = $null
            }
            $calls = [System.Collections.Generic.List[object]]::new()
            Mock -CommandName Assert-PfbContextCapability  -MockWith { $calls.Add('capability') }
            Mock -CommandName Assert-PfbContextCardinality -MockWith { $calls.Add('cardinality') }
            Mock -CommandName Assert-PfbContextKindMatchesScope -MockWith { $calls.Add('kindMatchesScope') }
            Mock -CommandName Assert-PfbContextAdminLocality -MockWith { $calls.Add('adminLocality') }
            # Recording, not silent: its POSITION is the thing under test here.
            Mock -CommandName Assert-PfbApiCapability -MockWith { $calls.Add('versionGate') }
            Mock -CommandName Invoke-RestMethod -MockWith { [PSCustomObject]@{ items = @() } }

            Invoke-PfbApiRequest -Array $fb -Method 'GET' -Endpoint 'file-systems' | Out-Null

            @($calls) -join ',' | Should -Be 'capability,cardinality,kindMatchesScope,versionGate,adminLocality' -Because 'the three injecting gates must precede the version gate (it has to see the injected context_names), and the endpoint-independent admin-locality gate must follow it so a firmware blocker wins over an admin-locality one'
        }
    }
    It 'passes each gate the resolved context and the shared capability map' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $fb = [PSCustomObject]@{
                PSTypeName = 'PureStorage.FlashBlade.Connection'
                Endpoint = 'fb.example'; ApiVersion = '2.26'; AuthToken = 't'; AuthMethod = 'ApiToken'
                DefaultContext = (New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-B')))
                ContextOverride = $null; AdminLocality = $null
            }
            $seen = [System.Collections.Generic.List[object]]::new()
            Mock -CommandName Assert-PfbContextCapability -MockWith {
                $seen.Add([PSCustomObject]@{ Gate = 'capability'; Names = @($Context.Entries.Name) -join ','; Endpoint = $Endpoint; HasMap = ($null -ne $CapabilityMap) })
            }
            Mock -CommandName Assert-PfbContextCardinality -MockWith {
                $seen.Add([PSCustomObject]@{ Gate = 'cardinality'; Names = @($Context.Entries.Name) -join ','; Endpoint = $Endpoint; HasMap = ($null -ne $CapabilityMap) })
            }
            Mock -CommandName Assert-PfbContextKindMatchesScope -MockWith {
                $seen.Add([PSCustomObject]@{ Gate = 'kindMatchesScope'; Names = @($Context.Entries.Name) -join ','; Endpoint = $Endpoint; HasMap = ($null -ne $CapabilityMap) })
            }
            # The admin-locality gate has a DIFFERENT signature from the other three: it
            # takes -Array (which only the capability gate also takes) and neither -Endpoint nor
            # -CapabilityMap, because the admin's model is a property of the session, not of the
            # endpoint. Record what it actually receives rather than forcing it into their shape.
            $authSeen = [System.Collections.Generic.List[object]]::new()
            Mock -CommandName Assert-PfbContextAdminLocality -MockWith {
                $authSeen.Add([PSCustomObject]@{ Names = @($Context.Entries.Name) -join ','; ArrayEndpoint = $Array.Endpoint })
            }
            Mock -CommandName Assert-PfbApiCapability -MockWith {}
            Mock -CommandName Invoke-RestMethod -MockWith { [PSCustomObject]@{ items = @() } }

            Invoke-PfbApiRequest -Array $fb -Method 'GET' -Endpoint 'file-systems' | Out-Null

            @($seen).Count | Should -Be 3
            foreach ($record in $seen) {
                $record.Names    | Should -Be 'FB-B'         -Because "$($record.Gate) must see the RESOLVED context, not a raw parameter"
                $record.Endpoint | Should -Be 'file-systems'
                $record.HasMap   | Should -BeTrue            -Because "$($record.Gate) must receive the capability map, or it silently no-ops"
            }
            @($authSeen).Count       | Should -Be 1
            $authSeen[0].Names         | Should -Be 'FB-B'       -Because 'the admin-locality gate must see the RESOLVED context too'
            $authSeen[0].ArrayEndpoint | Should -Be 'fb.example' -Because 'it must receive the CONNECTION, which is where AdminLocality lives; without -Array it can only ever no-op'
        }
    }
    It 'calls none of the four shape gates when no context is set' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $fb = [PSCustomObject]@{
                PSTypeName = 'PureStorage.FlashBlade.Connection'
                Endpoint = 'fb.example'; ApiVersion = '2.26'; AuthToken = 't'; AuthMethod = 'ApiToken'
                DefaultContext = $null; ContextOverride = $null; AdminLocality = $null
            }
            $calls = [System.Collections.Generic.List[object]]::new()
            Mock -CommandName Assert-PfbContextCapability  -MockWith { $calls.Add('capability') }
            Mock -CommandName Assert-PfbContextCardinality -MockWith { $calls.Add('cardinality') }
            Mock -CommandName Assert-PfbContextKindMatchesScope -MockWith { $calls.Add('kindMatchesScope') }
            Mock -CommandName Assert-PfbContextAdminLocality -MockWith { $calls.Add('adminLocality') }
            Mock -CommandName Assert-PfbApiCapability -MockWith {}
            Mock -CommandName Invoke-RestMethod -MockWith { [PSCustomObject]@{ items = @() } }

            Invoke-PfbApiRequest -Array $fb -Method 'GET' -Endpoint 'file-systems' | Out-Null

            @($calls).Count | Should -Be 0
        }
    }
    # An un-mocked companion to the wiring tests above: every one of those mocks the gate, so they
    # pin that it is CALLED and say nothing about its effect through this function. This one also
    # fails if the call is ever moved outside the $hasContext branch.
    It 'actually throws for a local admin with a context, gate un-mocked' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $fb = [PSCustomObject]@{
                PSTypeName = 'PureStorage.FlashBlade.Connection'
                Endpoint = 'fb.example'; ApiVersion = '2.26'; AuthToken = 't'; AuthMethod = 'ApiToken'
                Username = 'pureuser'
                DefaultContext = (New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-B')))
                ContextOverride = $null; AdminLocality = 'local'
            }
            Mock -CommandName Assert-PfbApiCapability -MockWith {}
            Mock -CommandName Invoke-RestMethod -MockWith { throw 'the request must never be attempted' }

            { Invoke-PfbApiRequest -Array $fb -Method 'GET' -Endpoint 'file-systems' } |
                Should -Throw -ExpectedMessage '*remotely authenticated*'
        }
    }
    # The It above counts only the four SHAPE gates, so it passes whether or not the
    # required-context gate is wired at all -- it looks like coverage of the else branch and is
    # not. This is the detector for that call site: its own List, its own count.
    It 'calls the required-context gate exactly once, with the caller query params and the shared map, when no context is set' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $fb = [PSCustomObject]@{
                PSTypeName = 'PureStorage.FlashBlade.Connection'
                Endpoint = 'fb.example'; ApiVersion = '2.26'; AuthToken = 't'; AuthMethod = 'ApiToken'
                DefaultContext = $null; ContextOverride = $null; AdminLocality = $null
            }
            $required = [System.Collections.Generic.List[object]]::new()
            Mock -CommandName Assert-PfbContextRequired -MockWith {
                $required.Add([PSCustomObject]@{
                    Method   = $Method
                    Endpoint = $Endpoint
                    Limit    = if ($null -ne $QueryParams -and $QueryParams.ContainsKey('limit')) { $QueryParams['limit'] } else { $null }
                    HasMap   = ($null -ne $CapabilityMap)
                })
            }
            Mock -CommandName Assert-PfbApiCapability -MockWith {}
            Mock -CommandName Invoke-RestMethod -MockWith { [PSCustomObject]@{ items = @() } }

            Invoke-PfbApiRequest -Array $fb -Method 'GET' -Endpoint 'file-systems' -QueryParams @{ limit = 5 } | Out-Null

            @($required).Count   | Should -Be 1 -Because 'the else branch must gate the context-free call; a count of 0 means the call was deleted or never wired'
            $required[0].Method  | Should -Be 'GET'
            $required[0].Endpoint | Should -Be 'file-systems'
            $required[0].Limit   | Should -Be 5    -Because 'it must see the CALLER query params, which carry the names=/ids= selectors it discriminates on'
            $required[0].HasMap  | Should -BeTrue  -Because 'without the map it reads every scope as unknown and silently no-ops'
        }
    }
    # Found by mutation during fix round 1: weakening the "-not $hasContext" guard to always-run
    # left this whole Describe green. The only tests that caught it were the two PUT-body
    # serialisation Its in Tests/Invoke-PfbApiRequest.Tests.ps1 -- incidental coverage in a file
    # about something else, which would evaporate the moment those fixtures change. The negation
    # matters: run unconditionally, and a fleet-scoped call that HAS a perfectly good fleet
    # context is told "requires a fleet context, but none is set". Pin it deliberately.
    It 'does NOT call the required-context gate when a context IS set' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $fb = [PSCustomObject]@{
                PSTypeName = 'PureStorage.FlashBlade.Connection'
                Endpoint = 'fb.example'; ApiVersion = '2.26'; AuthToken = 't'; AuthMethod = 'ApiToken'
                DefaultContext = (New-PfbContext -Entries @((New-PfbContextEntry -Name 'cc-test-fleet' -Kind 'Fleet')))
                ContextOverride = $null; AdminLocality = $null
            }
            $required = [System.Collections.Generic.List[object]]::new()
            Mock -CommandName Assert-PfbContextRequired -MockWith { $required.Add($Endpoint) }
            Mock -CommandName Assert-PfbApiCapability -MockWith {}
            Mock -CommandName Invoke-RestMethod -MockWith { [PSCustomObject]@{ items = @() } }

            # Fleet-scoped endpoint with a valid bare-fleet context: the request must go through.
            Invoke-PfbApiRequest -Array $fb -Method 'PUT' -Endpoint 'presets/workload' -Body @{ name = 'p1' } | Out-Null

            @($required).Count | Should -Be 0 -Because 'a satisfied context must not be reported as missing'
        }
    }
    # Fix round 1, Important 1. The required-context gate used to run BEFORE the version gate, so
    # an array too old for the endpoint was told to "Set one with Set-PfbContext" -- advice it
    # cannot follow, because an array below the endpoint's minVersion has no fleets to name. This
    # It pins the corrected precedence and fails if the call moves back above the version gate.
    #
    # Assert-PfbApiCapability is deliberately NOT mocked here: the assertion is about which of two
    # REAL gates wins, so mocking either away would make the test vacuous.
    It 'lets the version gate win over the required-context gate on a too-old array' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            # DELETE /presets/workload is fleet-scoped (so the required-context gate WOULD fire)
            # and has minVersion 2.23, above this array's 2.20 (so the version gate fires too).
            $fb = [PSCustomObject]@{
                PSTypeName = 'PureStorage.FlashBlade.Connection'
                Endpoint = 'fb.example'; ApiVersion = '2.20'; AuthToken = 't'; AuthMethod = 'ApiToken'
                DefaultContext = $null; ContextOverride = $null; AdminLocality = $null
            }
            Mock -CommandName Invoke-RestMethod -MockWith { throw 'the request must never be attempted' }

            # '*Upgrade the array*' is unique to Assert-PfbApiCapability's throw and absent from
            # the required-context throw, so this substring alone discriminates the two gates.
            { Invoke-PfbApiRequest -Array $fb -Method 'DELETE' -Endpoint 'presets/workload' } |
                Should -Throw -ExpectedMessage '*Upgrade the array*'
            { Invoke-PfbApiRequest -Array $fb -Method 'DELETE' -Endpoint 'presets/workload' } |
                Should -Throw -ExpectedMessage '*requires REST 2.23*'
        }
    }
    It 'calls the required-context gate for an explicit empty context too' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            # An explicit @() is the caller saying "locally", which on a fleet-scoped mutation is
            # exactly as broken as omitting the context -- so it must reach the gate, not bypass it.
            $fb = [PSCustomObject]@{
                PSTypeName = 'PureStorage.FlashBlade.Connection'
                Endpoint = 'fb.example'; ApiVersion = '2.26'; AuthToken = 't'; AuthMethod = 'ApiToken'
                DefaultContext = (New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-B')))
                ContextOverride = (New-PfbContext -Entries @()); AdminLocality = $null
            }
            $required = [System.Collections.Generic.List[object]]::new()
            Mock -CommandName Assert-PfbContextRequired -MockWith { $required.Add($Endpoint) }
            Mock -CommandName Assert-PfbApiCapability -MockWith {}
            Mock -CommandName Invoke-RestMethod -MockWith { [PSCustomObject]@{ items = @() } }

            Invoke-PfbApiRequest -Array $fb -Method 'GET' -Endpoint 'file-systems' | Out-Null

            @($required).Count | Should -Be 1
            $required[0] | Should -Be 'file-systems'
        }
    }
    Context 'error annotation' {
        It 'names the active context value in a code 42 failure' {
            InModuleScope 'PureStorageFlashBladePowerShell' {
                $ctx = New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-Q'))
                $msg = Add-PfbContextErrorAnnotation -Message 'FlashBlade API error: Cannot find array in fleet' `
                    -Context $ctx -Method 'GET' -Endpoint 'file-systems' -CapabilityMap (Get-PfbCapabilityMap)
                $msg | Should -BeLike '*FB-Q*'
            }
        }
        It 'names the cmdlets that set a context, so a stale session default is diagnosable' {
            InModuleScope 'PureStorageFlashBladePowerShell' {
                $ctx = New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-Q'))
                $msg = Add-PfbContextErrorAnnotation -Message 'FlashBlade API error: Cannot find array in fleet' `
                    -Context $ctx -Method 'GET' -Endpoint 'file-systems' -CapabilityMap (Get-PfbCapabilityMap)
                $msg | Should -BeLike '*Set-PfbContext*'
            }
        }
        It 'leaves an unrelated error message alone' {
            InModuleScope 'PureStorageFlashBladePowerShell' {
                $ctx = New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-B'))
                $msg = Add-PfbContextErrorAnnotation -Message 'FlashBlade API error: File system already exists' `
                    -Context $ctx -Method 'POST' -Endpoint 'file-systems' -CapabilityMap (Get-PfbCapabilityMap)
                $msg | Should -Be 'FlashBlade API error: File system already exists'
            }
        }
        It 'does not annotate when no context was active' {
            InModuleScope 'PureStorageFlashBladePowerShell' {
                Add-PfbContextErrorAnnotation -Message 'FlashBlade API error: Cannot find array in fleet' `
                    -Context $null -Method 'GET' -Endpoint 'file-systems' -CapabilityMap (Get-PfbCapabilityMap) |
                    Should -Be 'FlashBlade API error: Cannot find array in fleet'
            }
        }
        It 'does not annotate an EXPLICIT no-context (empty Entries), not just an unset one' {
            # Tri-state, per Global Constraints: $null is unset, an empty Entries collection is an
            # explicit "no context". Both must skip annotation, and the $null test above says nothing
            # about the empty case -- the implementation's guard is a two-clause -or, so a mutation
            # deleting the second clause survives without this test.
            InModuleScope 'PureStorageFlashBladePowerShell' {
                $ctx = New-PfbContext -Entries @()
                @($ctx.Entries).Count | Should -Be 0
                Add-PfbContextErrorAnnotation -Message 'FlashBlade API error: Cannot find array in fleet' `
                    -Context $ctx -Method 'GET' -Endpoint 'file-systems' -CapabilityMap (Get-PfbCapabilityMap) |
                    Should -Be 'FlashBlade API error: Cannot find array in fleet'
            }
        }
        # Step 3a. Task 11's proactive admin-locality gate cannot fire for an -ApiToken session
        # (no Username to look up) or for a session that only ever uses Invoke-PfbInContext, so for
        # those the wire's bare code 20 "Operation not permitted" is the ONLY signal the user gets.
        It 'explains a code 20 permission failure as a likely LOCAL admin' {
            InModuleScope 'PureStorageFlashBladePowerShell' {
                $ctx = New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-Q'))
                $msg = Add-PfbContextErrorAnnotation -Message 'FlashBlade API error (HTTP 400): Operation not permitted' `
                    -Context $ctx -Method 'GET' -Endpoint 'file-systems' -CapabilityMap (Get-PfbCapabilityMap)
                $msg | Should -BeLike '*may be a local account*'
                $msg | Should -BeLike '*FB-Q*'
            }
        }
        # The scope advice is the feature's actual value, and every assertion above is satisfied by
        # the surrounding sentence alone -- so without these two, swapping the switch's branch
        # strings or deleting $requirement entirely survives the whole file. Each It below picks an
        # endpoint whose REAL contextScope in Data/PfbCapabilityMap.json selects the branch it
        # names: GET /file-systems is scope 'array' (provenance 'default') and GET /presets/workload
        # is scope 'fleet' (provenance 'declared'). Verified against the checked-in map, not assumed.
        It 'names the FLEET requirement on a fleet-scoped endpoint' {
            InModuleScope 'PureStorageFlashBladePowerShell' {
                $map = Get-PfbCapabilityMap
                # Guard the premise: if this endpoint stops being fleet-scoped the test would
                # silently start exercising the array branch instead.
                (Get-PfbEndpointContextScope -Method 'GET' -Endpoint 'presets/workload' -CapabilityMap $map) |
                    Should -Be 'fleet'
                $ctx = New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-Q'))
                $msg = Add-PfbContextErrorAnnotation -Message 'FlashBlade API error: Cannot find array in fleet' `
                    -Context $ctx -Method 'GET' -Endpoint 'presets/workload' -CapabilityMap $map
                $msg | Should -BeLike '*requires a bare fleet context*'
                $msg | Should -BeLike '*GET /presets/workload*'
                # The array branch's wording must NOT appear, or a swap of the two strings passes.
                $msg | Should -Not -BeLike '*is array-scoped*'
            }
        }
        It 'names the ARRAY-scoped guidance on an array-scoped endpoint' {
            InModuleScope 'PureStorageFlashBladePowerShell' {
                $map = Get-PfbCapabilityMap
                (Get-PfbEndpointContextScope -Method 'GET' -Endpoint 'file-systems' -CapabilityMap $map) |
                    Should -Be 'array'
                $ctx = New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-Q'))
                $msg = Add-PfbContextErrorAnnotation -Message 'FlashBlade API error: Cannot find array in fleet' `
                    -Context $ctx -Method 'GET' -Endpoint 'file-systems' -CapabilityMap $map
                $msg | Should -BeLike '*is array-scoped*'
                $msg | Should -BeLike "*use a member array name*"
                $msg | Should -BeLike "*.arrays*"
                $msg | Should -Not -BeLike '*requires a bare fleet context*'
            }
        }
        It 'leaves a code 20 permission failure alone when no context is active' {
            InModuleScope 'PureStorageFlashBladePowerShell' {
                Add-PfbContextErrorAnnotation -Message 'FlashBlade API error (HTTP 400): Operation not permitted' `
                    -Context $null -Method 'GET' -Endpoint 'file-systems' -CapabilityMap (Get-PfbCapabilityMap) |
                    Should -Be 'FlashBlade API error (HTTP 400): Operation not permitted'
            }
        }
    }
    # Deliberately a SEPARATE Context from the scope-advice assertions above. Those pin WHICH SCOPE
    # ADVICE appears; these pin WHICH REMEDY appears. Folding both into one It would leave a future
    # reader unable to tell which of the two behaviours a failure refers to.
    Context 'remedy advice is branch-specific' {
        It 'does NOT offer the context cmdlets to a likely local admin' {
            InModuleScope 'PureStorageFlashBladePowerShell' {
                # A LOCAL admin cannot fix a code 20 by changing, clearing or
                # overriding the context -- no context VALUE works for that account. This negative
                # assertion is the load-bearing one: without it, a future edit that re-merges the
                # two closing clauses passes silently.
                $ctx = New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-Q'))
                $msg = Add-PfbContextErrorAnnotation -Message 'FlashBlade API error (HTTP 400): Operation not permitted' `
                    -Context $ctx -Method 'GET' -Endpoint 'file-systems' -CapabilityMap (Get-PfbCapabilityMap)
                $msg | Should -Not -BeLike '*Set-PfbContext*'
                $msg | Should -Not -BeLike '*Clear-PfbContext*'
                $msg | Should -Not -BeLike '*Invoke-PfbInContext*'
                $msg | Should -BeLike '*remotely authenticated (LDAP/SAML) admin*'
                # Naming the value is diagnostic, not advice, so it must still be there.
                $msg | Should -BeLike '*FB-Q*'
            }
        }
        It 'still offers the context cmdlets for a targeting failure, where the context IS the fix' {
            InModuleScope 'PureStorageFlashBladePowerShell' {
                $ctx = New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-Q'))
                $msg = Add-PfbContextErrorAnnotation -Message 'FlashBlade API error: Cannot find array in fleet' `
                    -Context $ctx -Method 'GET' -Endpoint 'file-systems' -CapabilityMap (Get-PfbCapabilityMap)
                $msg | Should -BeLike '*Set-PfbContext*'
                $msg | Should -BeLike '*Clear-PfbContext*'
                $msg | Should -BeLike '*Invoke-PfbInContext*'
                $msg | Should -Not -BeLike '*Reconnect as a dynamic-model*'
            }
        }
    }
    # Step 4a. Unit tests of Add-PfbContextErrorAnnotation prove nothing about the CALL SITE, so
    # these two mock at the Invoke-RestMethod boundary and let the real request path run. There are
    # two throw sites in the catch and both must annotate.
    Context 'error annotation is actually wired into the request path' {
        It 'annotates a context-targeting failure on the plain throw site' {
            InModuleScope 'PureStorageFlashBladePowerShell' {
                $fb = [PSCustomObject]@{
                    PSTypeName = 'PureStorage.FlashBlade.Connection'
                    Endpoint = 'fb.example'; ApiVersion = '2.26'; AuthToken = 't'; AuthMethod = 'ApiToken'
                    ApiToken = $null
                    DefaultContext = (New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-Q')))
                    ContextOverride = $null; AdminLocality = $null
                }
                # No Response member on the exception, so the status is $null: the reconnect gate
                # cannot fire and the failure takes the else branch.
                Mock -CommandName Invoke-RestMethod -MockWith { throw 'Cannot find array in fleet' }

                { Invoke-PfbApiRequest -Array $fb -Method 'GET' -Endpoint 'file-systems' } |
                    Should -Throw -ExpectedMessage '*FB-Q*'
                { Invoke-PfbApiRequest -Array $fb -Method 'GET' -Endpoint 'file-systems' } |
                    Should -Throw -ExpectedMessage '*Clear-PfbContext*'
            }
        }
        It 'annotates on the reconnect-failed throw site too (403 with the reconnect unavailable)' {
            InModuleScope 'PureStorageFlashBladePowerShell' {
                $fb = [PSCustomObject]@{
                    PSTypeName = 'PureStorage.FlashBlade.Connection'
                    Endpoint = 'fb.example'; ApiVersion = '2.26'; AuthToken = 't'; AuthMethod = 'ApiToken'
                    ApiToken = 'T-fake-token'
                    DefaultContext = (New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-Q')))
                    ContextOverride = $null; AdminLocality = $null
                }
                # A 403 on a reconnectable session enters the reconnect block; the re-login then
                # fails, so the throw comes from inside that block rather than the else branch.
                Mock -CommandName Invoke-RestMethod -MockWith {
                    $ex = New-Object System.Exception('Operation not permitted')
                    $response = [PSCustomObject]@{ StatusCode = [System.Net.HttpStatusCode]403 }
                    Add-Member -InputObject $ex -MemberType NoteProperty -Name Response -Value $response -Force
                    throw $ex
                }
                Mock -CommandName Connect-PfbArrayInternal -MockWith { throw 'reconnect unavailable' }

                { Invoke-PfbApiRequest -Array $fb -Method 'GET' -Endpoint 'file-systems' } |
                    Should -Throw -ExpectedMessage '*FB-Q*'
                { Invoke-PfbApiRequest -Array $fb -Method 'GET' -Endpoint 'file-systems' } |
                    Should -Throw -ExpectedMessage '*(HTTP 403)*'
            }
        }
    }
}
