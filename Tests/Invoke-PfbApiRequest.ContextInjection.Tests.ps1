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
                ContextOverride = $null; AuthorizationModel = $null
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
                ContextOverride = $null; AuthorizationModel = $null
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
                ContextOverride = $null; AuthorizationModel = $null
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
                DefaultContext = $null; ContextOverride = $null; AuthorizationModel = $null
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
                ContextOverride = (New-PfbContext -Entries @()); AuthorizationModel = $null
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
                ContextOverride = $null; AuthorizationModel = $null
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
    It 'calls all three shape gates in order, capability before cardinality before kindMatchesScope' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $fb = [PSCustomObject]@{
                PSTypeName = 'PureStorage.FlashBlade.Connection'
                Endpoint = 'fb.example'; ApiVersion = '2.26'; AuthToken = 't'; AuthMethod = 'ApiToken'
                DefaultContext = (New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-B')))
                ContextOverride = $null; AuthorizationModel = $null
            }
            # A List with .Add() -- an assignment inside a Mock body does not propagate out, and
            # `$script:` inside InModuleScope would write to the MODULE's script scope.
            $calls = [System.Collections.Generic.List[object]]::new()
            Mock -CommandName Assert-PfbContextCapability  -MockWith { $calls.Add('capability') }
            Mock -CommandName Assert-PfbContextCardinality -MockWith { $calls.Add('cardinality') }
            Mock -CommandName Assert-PfbContextKindMatchesScope -MockWith { $calls.Add('kindMatchesScope') }
            Mock -CommandName Assert-PfbApiCapability -MockWith {}
            Mock -CommandName Invoke-RestMethod -MockWith { [PSCustomObject]@{ items = @() } }

            Invoke-PfbApiRequest -Array $fb -Method 'GET' -Endpoint 'file-systems' | Out-Null

            @($calls).Count | Should -Be 3 -Because 'all three shape gates must fire from the request path; a lower count means one call was deleted or never wired'
            $calls[0] | Should -Be 'capability'  -Because 'the capability gate must rule on "endpoint takes no context at all" first'
            $calls[1] | Should -Be 'cardinality'
            $calls[2] | Should -Be 'kindMatchesScope' -Because 'it runs after cardinality: a wrong-KIND context aimed at an endpoint that takes no context at all should hear about capability first, not about scope'
        }
    }
    It 'passes each gate the resolved context and the shared capability map' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $fb = [PSCustomObject]@{
                PSTypeName = 'PureStorage.FlashBlade.Connection'
                Endpoint = 'fb.example'; ApiVersion = '2.26'; AuthToken = 't'; AuthMethod = 'ApiToken'
                DefaultContext = (New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-B')))
                ContextOverride = $null; AuthorizationModel = $null
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
            Mock -CommandName Assert-PfbApiCapability -MockWith {}
            Mock -CommandName Invoke-RestMethod -MockWith { [PSCustomObject]@{ items = @() } }

            Invoke-PfbApiRequest -Array $fb -Method 'GET' -Endpoint 'file-systems' | Out-Null

            @($seen).Count | Should -Be 3
            foreach ($record in $seen) {
                $record.Names    | Should -Be 'FB-B'         -Because "$($record.Gate) must see the RESOLVED context, not a raw parameter"
                $record.Endpoint | Should -Be 'file-systems'
                $record.HasMap   | Should -BeTrue            -Because "$($record.Gate) must receive the capability map, or it silently no-ops"
            }
        }
    }
    It 'calls none of the three shape gates when no context is set' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $fb = [PSCustomObject]@{
                PSTypeName = 'PureStorage.FlashBlade.Connection'
                Endpoint = 'fb.example'; ApiVersion = '2.26'; AuthToken = 't'; AuthMethod = 'ApiToken'
                DefaultContext = $null; ContextOverride = $null; AuthorizationModel = $null
            }
            $calls = [System.Collections.Generic.List[object]]::new()
            Mock -CommandName Assert-PfbContextCapability  -MockWith { $calls.Add('capability') }
            Mock -CommandName Assert-PfbContextCardinality -MockWith { $calls.Add('cardinality') }
            Mock -CommandName Assert-PfbContextKindMatchesScope -MockWith { $calls.Add('kindMatchesScope') }
            Mock -CommandName Assert-PfbApiCapability -MockWith {}
            Mock -CommandName Invoke-RestMethod -MockWith { [PSCustomObject]@{ items = @() } }

            Invoke-PfbApiRequest -Array $fb -Method 'GET' -Endpoint 'file-systems' | Out-Null

            @($calls).Count | Should -Be 0
        }
    }
    # The It above counts only the three SHAPE gates, so it passes whether or not the
    # required-context gate is wired at all -- it looks like coverage of the else branch and is
    # not. This is the detector for that call site: its own List, its own count.
    It 'calls the required-context gate exactly once, with the caller query params and the shared map, when no context is set' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $fb = [PSCustomObject]@{
                PSTypeName = 'PureStorage.FlashBlade.Connection'
                Endpoint = 'fb.example'; ApiVersion = '2.26'; AuthToken = 't'; AuthMethod = 'ApiToken'
                DefaultContext = $null; ContextOverride = $null; AuthorizationModel = $null
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
    It 'calls the required-context gate for an explicit empty context too' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            # An explicit @() is the caller saying "locally", which on a fleet-scoped mutation is
            # exactly as broken as omitting the context -- so it must reach the gate, not bypass it.
            $fb = [PSCustomObject]@{
                PSTypeName = 'PureStorage.FlashBlade.Connection'
                Endpoint = 'fb.example'; ApiVersion = '2.26'; AuthToken = 't'; AuthMethod = 'ApiToken'
                DefaultContext = (New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-B')))
                ContextOverride = (New-PfbContext -Entries @()); AuthorizationModel = $null
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
}
