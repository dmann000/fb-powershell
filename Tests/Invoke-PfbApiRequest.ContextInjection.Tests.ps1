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
            Mock -CommandName Assert-PfbApiCapability -MockWith {}
            Mock -CommandName Invoke-RestMethod -MockWith { $uris.Add($Uri); [PSCustomObject]@{ items = @() } }
            Invoke-PfbApiRequest -Array $fb -Method 'GET' -Endpoint 'alert-watchers' | Out-Null
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
