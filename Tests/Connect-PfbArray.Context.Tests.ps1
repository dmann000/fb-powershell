#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    Import-Module "$PSScriptRoot/../PureStorageFlashBladePowerShell.psd1" -Force
}

Describe 'connection context state' {
    It 'copies without mutating the original and preserves the type name' {
        InModuleScope PureStorageFlashBladePowerShell {
            $fake = [PSCustomObject]@{
                PSTypeName         = 'PureStorage.FlashBlade.Connection'
                Endpoint           = 'fb.example'
                ApiVersion         = '2.26'
                DefaultContext     = $null
                ContextOverride    = $null
                AdminLocality      = $null
            }
            $copy = Copy-PfbConnection -Array $fake
            $copy.DefaultContext = New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-B'))
            $null -eq $fake.DefaultContext | Should -BeTrue
            $copy.PSObject.TypeNames | Should -Contain 'PureStorage.FlashBlade.Connection'
            [object]::ReferenceEquals($copy, $fake) | Should -BeFalse
        }
    }

    It 'repoints both caches at the copy' {
        InModuleScope PureStorageFlashBladePowerShell {
            $fake = [PSCustomObject]@{
                PSTypeName = 'PureStorage.FlashBlade.Connection'
                Endpoint   = 'fb.example'
                ApiVersion = '2.26'
            }
            $originalArrays = $script:PfbArrays
            $originalDefault = $script:PfbDefaultArray
            try {
                $script:PfbArrays = @{ 'fb.example' = $fake }
                $script:PfbDefaultArray = $fake
                $copy = Copy-PfbConnection -Array $fake
                Update-PfbConnectionCache -Array $copy
                [object]::ReferenceEquals($script:PfbArrays['fb.example'], $copy) | Should -BeTrue
                [object]::ReferenceEquals($script:PfbDefaultArray, $copy) | Should -BeTrue
            }
            finally {
                # param()-passed restore: .GetNewClosure() against a module scope fails under
                # StrictMode and silently leaks state.
                & { param($a, $d) $script:PfbArrays = $a; $script:PfbDefaultArray = $d } $originalArrays $originalDefault
            }
        }
    }

    It 'leaves a different endpoint in the cache alone' {
        InModuleScope PureStorageFlashBladePowerShell {
            $fake = [PSCustomObject]@{
                PSTypeName = 'PureStorage.FlashBlade.Connection'
                Endpoint   = 'fb.example'
                ApiVersion = '2.26'
            }
            $originalArrays = $script:PfbArrays
            $originalDefault = $script:PfbDefaultArray
            try {
                $other = [PSCustomObject]@{ PSTypeName = 'PureStorage.FlashBlade.Connection'; Endpoint = 'other.example' }
                $script:PfbArrays = @{ 'other.example' = $other }
                $script:PfbDefaultArray = $other
                Update-PfbConnectionCache -Array (Copy-PfbConnection -Array $fake)
                [object]::ReferenceEquals($script:PfbDefaultArray, $other) | Should -BeTrue
                $script:PfbArrays.ContainsKey('fb.example') | Should -BeFalse
            }
            finally {
                & { param($a, $d) $script:PfbArrays = $a; $script:PfbDefaultArray = $d } $originalArrays $originalDefault
            }
        }
    }

    It 'does not repoint any cache from Copy-PfbConnection itself' {
        InModuleScope PureStorageFlashBladePowerShell {
            $fake = [PSCustomObject]@{
                PSTypeName = 'PureStorage.FlashBlade.Connection'
                Endpoint   = 'fb.example'
                ApiVersion = '2.26'
            }
            $originalArrays = $script:PfbArrays
            $originalDefault = $script:PfbDefaultArray
            try {
                $script:PfbArrays = @{ 'fb.example' = $fake }
                $script:PfbDefaultArray = $fake
                Copy-PfbConnection -Array $fake | Out-Null
                [object]::ReferenceEquals($script:PfbArrays['fb.example'], $fake) | Should -BeTrue
                [object]::ReferenceEquals($script:PfbDefaultArray, $fake) | Should -BeTrue
            }
            finally {
                & { param($a, $d) $script:PfbArrays = $a; $script:PfbDefaultArray = $d } $originalArrays $originalDefault
            }
        }
    }
}

Describe 'Connect-PfbArray context properties' {
    It 'declares the three context parameters' {
        $cmd = Get-Command Connect-PfbArray
        foreach ($p in 'Context', 'Kind', 'AllArrays') { $cmd.Parameters.Keys | Should -Contain $p }
    }

    It 'constrains -Kind to the three valid context kinds' {
        $cmd = Get-Command Connect-PfbArray
        $validate = $cmd.Parameters['Kind'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
        $validate | Should -Not -BeNullOrEmpty
        $validate.ValidValues | Should -Be @('Array', 'Fleet', 'TopologyGroup')
    }

}

Describe 'Connect-PfbArray -Context behaviour' {
    # Fully mocked connect -- no array involved. Same harness as
    # Tests/Connect-PfbArray.CapabilityMapStaleness.Tests.ps1, which proves a real connection
    # object can be produced from mocks alone.
    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-WebRequest {
            [PSCustomObject]@{ Headers = @{ 'x-auth-token' = 'tok' } }
        }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
            [PSCustomObject]@{ versions = @('2.26') }
        } -ParameterFilter { $Uri -like '*api_version*' }
        Mock -ModuleName PureStorageFlashBladePowerShell Get-PfbCapabilityMap {
            [PSCustomObject]@{ schemaVersion = 2; generatedFrom = @('2.0', '2.26') }
        }

        # A successful mocked connect repoints $script:PfbDefaultArray and
        # $script:PfbArrays['fb.test'] at a fake connection. Without a restore, that state
        # outlives this file and is available to poison any later one, so it is captured here
        # and restored in AfterEach for every test in this block.
        #
        # `@{} + $script:PfbArrays` is a shallow COPY, not the reference: Connect-PfbArray
        # mutates that hashtable in place ($script:PfbArrays[$Endpoint] = ...), so reassigning
        # the identical object in AfterEach would be a no-op and the 'fb.test' key would still
        # leak. $script:PfbDefaultArray is a plain reassignment, so capturing the reference is
        # correct there.
        $script:originalState = InModuleScope PureStorageFlashBladePowerShell {
            @{ Arrays = @{} + $script:PfbArrays; Default = $script:PfbDefaultArray }
        }
    }

    AfterEach {
        # param()-passed restore: .GetNewClosure() against a module scope fails under StrictMode
        # and silently leaks state.
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ state = $script:originalState } {
            & { param($a, $d) $script:PfbArrays = $a; $script:PfbDefaultArray = $d } $state.Arrays $state.Default
        }
    }

    It 'exposes the three context state properties on the connection object' {
        $conn = Connect-PfbArray -Endpoint 'fb.test' -ApiToken 'T-fake'
        foreach ($prop in 'DefaultContext', 'ContextOverride', 'AdminLocality') {
            $conn.PSObject.Properties.Name | Should -Contain $prop
        }
    }

    # THE detector for Connect-PfbArray.ps1's `$connection.AdminLocality = Resolve-...` line.
    # Deleting that one line disables the whole admin-locality feature without breaking any
    # gate call site, and nothing pinned it: the two pre-existing AdminLocality assertions in
    # this file check that the PROPERTY EXISTS (declared in the object literal, so it passes
    # either way) and that it is $null (which passes either way too, because those harnesses
    # connect with -ApiToken and so Username is never populated). That gap is why the inert-gate
    # defect shipped.
    #
    # Must use a username-bearing parameter set: -ApiToken never populates Username, so the
    # resolver early-returns and this test would pass vacuously against a deleted line. And must
    # supply -Context: since the 2026-08-05 ruling the resolution happens ONLY on that path.
    It 'populates AdminLocality from the connected admin when -Context is supplied' {
        $cred = [System.Management.Automation.PSCredential]::new(
            'jdoe', (ConvertTo-SecureString 'pw' -AsPlainText -Force))
        # Boundary mocks, matched with -match so `?` is a literal and not the -like single-char
        # wildcard: '*/admins?*' would also match the api-tokens URI's '/admins/'.
        # is_local=$false (remote), not local: a local admin plus a connect-time context now
        # throws (see the test below), so a local fixture here would assert an unreachable state.
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
            [PSCustomObject]@{
                items = @([PSCustomObject]@{ name = 'jdoe'; is_local = $false })
                total_item_count = 1
            }
        } -ParameterFilter { $Uri -match '/admins\?' }
        # The best-effort API-token read/mint on the credential path. Answered with an empty list
        # so it neither reaches the network nor supplies a token.
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
            [PSCustomObject]@{ items = @() }
        } -ParameterFilter { $Uri -match '/admins/api-tokens' }

        $conn = Connect-PfbArray -Endpoint 'fb.test' -Credential $cred -Context 'FB-B'

        $conn.AdminLocality | Should -Be 'remote' -Because 'Connect-PfbArray must assign the resolver result onto the connection; a $null here means the capture line was never wired'
        @($conn.DefaultContext.Entries).Count | Should -Be 1
    }

    # THE detector for the whole point of the 2026-08-05 ruling: a session that never touches
    # Fusion must not pay for a GET /admins round trip. Nothing else in the suite can see this --
    # every other test either supplies a context or connects with -ApiToken (no Username), so the
    # resolution would be invisible to them whether it is conditional or unconditional.
    It 'makes NO admin call on a bare connect, even with a username-bearing credential' {
        $cred = [System.Management.Automation.PSCredential]::new(
            'jdoe', (ConvertTo-SecureString 'pw' -AsPlainText -Force))
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
            throw 'GET /admins must not be called on a bare connect'
        } -ParameterFilter { $Uri -match '/admins\?' }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
            [PSCustomObject]@{ items = @() }
        } -ParameterFilter { $Uri -match '/admins/api-tokens' }

        $conn = Connect-PfbArray -Endpoint 'fb.test' -Credential $cred

        # -Times 0 is the real assertion. The throwing mock body above is NOT sufficient on its
        # own: Resolve-PfbAdminLocality catches everything and returns $null, so the throw
        # would be swallowed and this test would pass with the call still being made.
        Should -Invoke -ModuleName PureStorageFlashBladePowerShell -CommandName Invoke-RestMethod `
            -ParameterFilter { $Uri -match '/admins\?' } -Times 0 `
            -Because 'a connect with no -Context must not resolve the admin locality at all'
        $null -eq $conn.AdminLocality | Should -BeTrue
    }

    # The tri-state case and the model-resolving case were covered by DISJOINT sets of tests, and
    # the defect lived in their intersection: the only -Context @() test connects with -ApiToken,
    # so there was no Username, the resolver early-returned, and the gate failed open. A
    # username-bearing @() connect is that missing intersection.
    It 'treats -Context @() as no context: no admin probe, no gate, no throw' {
        $cred = [System.Management.Automation.PSCredential]::new(
            'pureuser', (ConvertTo-SecureString 'pw' -AsPlainText -Force))
        # A LOCAL admin: were the gate to run it would throw -- and with @() it would interpolate
        # an empty value into the message ("the context '' would return ...").
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
            [PSCustomObject]@{
                items = @([PSCustomObject]@{ name = 'pureuser'; is_local = $true })
                total_item_count = 1
            }
        } -ParameterFilter { $Uri -match '/admins\?' }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
            [PSCustomObject]@{ items = @() }
        } -ParameterFilter { $Uri -match '/admins/api-tokens' }

        $conn = Connect-PfbArray -Endpoint 'fb.test' -Credential $cred -Context @()

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell -CommandName Invoke-RestMethod `
            -ParameterFilter { $Uri -match '/admins\?' } -Times 0 `
            -Because 'an explicit no-context connect names nothing, so there is nothing to pre-validate and no reason to pay for a probe'
        # And the tri-state must survive: @() is DefaultContext-set-with-zero-entries, not unset.
        $null -ne $conn.DefaultContext | Should -BeTrue
        @($conn.DefaultContext.Entries).Count | Should -Be 0
    }

    It 'resolves the admin locality exactly once per connect' {
        # Pins the cost as "one lookup per connect, not one per request".
        InModuleScope PureStorageFlashBladePowerShell {
            Mock -CommandName Resolve-PfbAdminLocality -MockWith { 'remote' }
            $conn = Connect-PfbArray -Endpoint 'fb.test' -ApiToken 'T-fake' -Context 'FB-B'
            $conn.AdminLocality | Should -Be 'remote'
            Should -Invoke -CommandName Resolve-PfbAdminLocality -Times 1 -Exactly
        }
    }

    It 'rejects a connect-time context for a local admin, releases the session, and installs nothing in the caches' {
        # The connect-time context path is now gated -- it is where resolution happens, so it is
        # where the gate can rule. The cache half of this assertion is the one that matters: the
        # caches used to be repointed BEFORE this block, so a rejected context left a connection
        # the cmdlet never returned installed as $script:PfbDefaultArray.
        #
        # The logout assertion is the SOLE detector for the release: the throw-message and cache
        # assertions all still hold with the entire try/catch deleted, so without this line the
        # release would be untested while looking covered.
        InModuleScope PureStorageFlashBladePowerShell {
            Mock -CommandName Resolve-PfbAdminLocality -MockWith { 'local' }
            Mock -CommandName Invoke-RestMethod -MockWith {} -ParameterFilter { $Uri -match '/api/logout' }
            $sentinel = [PSCustomObject]@{ PSTypeName = 'PureStorage.FlashBlade.Connection'; Endpoint = 'sentinel' }
            $script:PfbArrays = @{ 'sentinel' = $sentinel }
            $script:PfbDefaultArray = $sentinel

            { Connect-PfbArray -Endpoint 'fb.test' -ApiToken 'T-fake' -Context 'FB-B' } |
                Should -Throw -ExpectedMessage '*remotely authenticated*'

            Should -Invoke -CommandName Invoke-RestMethod -ParameterFilter { $Uri -match '/api/logout' } -Times 1 -Exactly `
                -Because 'this is the cmdlet first throw after a successful login, so the session it minted must be released rather than abandoned'
            # Same call, but additionally requiring a timeout: without one, an endpoint that accepts
            # TCP and never answers would stall a cmdlet that has already decided to fail.
            Should -Invoke -CommandName Invoke-RestMethod `
                -ParameterFilter { $Uri -match '/api/logout' -and $TimeoutSec -gt 0 } -Times 1 -Exactly `
                -Because 'the logout must carry the connection timeout, since the caller is already waiting on an error'

            [object]::ReferenceEquals($script:PfbDefaultArray, $sentinel) | Should -BeTrue -Because 'a rejected connect must not become the default array'
            $script:PfbArrays.ContainsKey('fb.test') | Should -BeFalse
        }
    }

    It 'rejects -Context $null at the binder, naming -Context, not a downstream parameter' {
        # Without [ValidateNotNull()] on -Context, $null flows into
        # ConvertTo-PfbContextEntryList -Name $null and is rejected there, blaming -Name -- a
        # parameter the caller never typed. Asserting on the parameter NAME is what makes this
        # discriminating: unvalidated the message is "Cannot bind argument to parameter 'Name'";
        # validated it is "Cannot validate argument on parameter 'Context'". Measured, not
        # assumed. -Context is optional, so Should -Throw cannot trigger a prompt here.
        { Connect-PfbArray -Endpoint 'fb.test' -ApiToken 'T-fake' -Context $null } |
            Should -Throw -ExpectedMessage "*parameter 'Context'*"
    }

    It 'treats -Context @() as an explicit no-context: DefaultContext set, zero entries' {
        # The headline tri-state at the connect layer -- @() is NOT the same state as unset, and
        # it carries its own meaning ("run this one call locally") at the Invoke-PfbInContext
        # layer. Works because ConvertTo-PfbContextEntryList's -Name carries
        # [AllowEmptyCollection()]. Doubles as the regression guard proving -Context's
        # [ValidateNotNull()] deliberately still admits @(): ValidateNotNullOrEmpty there would
        # collapse the tri-state.
        $conn = Connect-PfbArray -Endpoint 'fb.test' -ApiToken 'T-fake' -Context @()
        $null -ne $conn.DefaultContext | Should -BeTrue
        @($conn.DefaultContext.Entries).Count | Should -Be 0
    }

    It 'leaves DefaultContext at $null -- not an empty list -- when no -Context is supplied' {
        $conn = Connect-PfbArray -Endpoint 'fb.test' -ApiToken 'T-fake'
        # -BeNullOrEmpty cannot tell $null (unset) from @() (explicit no-context); that
        # distinction is the whole point of the tri-state, so test the reference directly.
        # Guard against passing vacuously: without this, a Connect-PfbArray that returned
        # nothing at all would satisfy every assertion below.
        $null -ne $conn | Should -BeTrue
        $null -eq $conn.DefaultContext | Should -BeTrue
        $null -eq $conn.ContextOverride | Should -BeTrue
        $null -eq $conn.AdminLocality | Should -BeTrue
    }

    It 'stores a single Array/Object entry for -Context with no -Kind or -AllArrays' {
        $conn = Connect-PfbArray -Endpoint 'fb.test' -ApiToken 'T-fake' -Context 'FB-B'
        $null -eq $conn.DefaultContext | Should -BeFalse
        @($conn.DefaultContext.Entries).Count | Should -Be 1
        $conn.DefaultContext.Entries[0].Name | Should -Be 'FB-B'
        $conn.DefaultContext.Entries[0].Kind | Should -Be 'Array'
        $conn.DefaultContext.Entries[0].Form | Should -Be 'Object'
    }

    It 'maps -AllArrays to the AllArrays form' {
        $conn = Connect-PfbArray -Endpoint 'fb.test' -ApiToken 'T-fake' -Context 'flt' -Kind Fleet -AllArrays
        @($conn.DefaultContext.Entries).Count | Should -Be 1
        $conn.DefaultContext.Entries[0].Kind | Should -Be 'Fleet'
        $conn.DefaultContext.Entries[0].Form | Should -Be 'AllArrays'
    }

    It 'rejects an invalid Kind/Form composition' {
        # -Context/-Kind/-AllArrays are all optional, so Should -Throw cannot trigger a
        # mandatory-parameter prompt here.
        { Connect-PfbArray -Endpoint 'fb.test' -ApiToken 'T-fake' -Context 'g' -Kind TopologyGroup } |
            Should -Throw -ExpectedMessage '*<name>.arrays*'
    }

    It 'does not repoint either cache when the composition is invalid' {
        # Validation must happen BEFORE authentication and before the caches are repointed.
        # Otherwise the caller gets an error while every later context-less cmdlet silently
        # succeeds against an array with none of the targeting they asked for.
        InModuleScope PureStorageFlashBladePowerShell {
            $originalArrays = $script:PfbArrays
            $originalDefault = $script:PfbDefaultArray
            try {
                $sentinel = [PSCustomObject]@{ PSTypeName = 'PureStorage.FlashBlade.Connection'; Endpoint = 'sentinel' }
                $script:PfbArrays = @{ 'sentinel' = $sentinel }
                $script:PfbDefaultArray = $sentinel

                { Connect-PfbArray -Endpoint 'fb.test' -ApiToken 'T-fake' -Context 'g' -Kind TopologyGroup } | Should -Throw

                [object]::ReferenceEquals($script:PfbDefaultArray, $sentinel) | Should -BeTrue
                $script:PfbArrays.ContainsKey('fb.test') | Should -BeFalse
            }
            finally {
                & { param($a, $d) $script:PfbArrays = $a; $script:PfbDefaultArray = $d } $originalArrays $originalDefault
            }
        }
    }

    It 'has left no fb.test entry in the module connection cache' {
        # Ordered last on purpose: every preceding test in this block has already run its
        # AfterEach, so this asserts the restore actually worked rather than merely ran. It is
        # the guard for the reference-vs-copy trap -- Connect-PfbArray mutates $script:PfbArrays
        # in place, so capturing a reference makes the AfterEach reassignment a no-op and this
        # assertion then fails with the key still present.
        InModuleScope PureStorageFlashBladePowerShell {
            $script:PfbArrays.ContainsKey('fb.test') | Should -BeFalse
        }
    }
}

Describe 'Resolve-PfbAdminLocality' {
    It 'leaves AdminLocality null when the admin lookup fails' {
        # DefaultContext/ContextOverride must be DECLARED on the fixture. The resolver takes
        # $Array.PSObject.Copy() and then assigns both to $null; assigning an absent property on a
        # PSCustomObject is a hard error, so without them the probe strip crashes into the
        # resolver's own catch and returns $null BEFORE the mocked 403 is ever reached -- the right
        # value for entirely the wrong reason. The Should -Invoke below is what distinguishes the
        # two, and it is the load-bearing line here: the two $null assertions hold either way.
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $fixture = { [PSCustomObject]@{ Endpoint = 'fb.example'; Username = 'u'; DefaultContext = $null; ContextOverride = $null } }
            Mock -CommandName Invoke-PfbApiRequest -MockWith { throw 'HTTP 403' }
            { Resolve-PfbAdminLocality -Array (& $fixture) } | Should -Not -Throw
            $null -eq (Resolve-PfbAdminLocality -Array (& $fixture)) | Should -BeTrue
            Should -Invoke -CommandName Invoke-PfbApiRequest -Times 2 -Exactly `
                -Because 'the 403 catch is the path under test; a count below the number of resolver calls means the probe strip crashed first and the $null came from a different failure entirely'
        }
    }
    # Mocked at the Invoke-RestMethod boundary, NOT at Invoke-PfbApiRequest. A mock of the thing
    # under test cannot prove its own return contract: an earlier revision mocked
    # Invoke-PfbApiRequest returning [PSCustomObject]@{ items = @(...) } -- the WIRE envelope,
    # which Invoke-PfbApiRequest can never actually return, because it unwraps items itself and
    # hands back an object[] of admin objects. The resolver read .items off that array, got $null
    # on every real array, and the whole gate was inert in production behind a green suite.
    # Letting the real Invoke-PfbApiRequest do the unwrap is what makes this a contract test.
    It 'reads is_local for the connecting username through the real items unwrap' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $fb = [PSCustomObject]@{
                PSTypeName = 'PureStorage.FlashBlade.Connection'
                Endpoint = 'fb.example'; ApiVersion = '2.26'; AuthToken = 't'; AuthMethod = 'ApiToken'
                Username = 'juemerson'
                DefaultContext = $null; ContextOverride = $null; AdminLocality = $null
            }
            Mock -CommandName Invoke-RestMethod -MockWith {
                [PSCustomObject]@{
                    items = @([PSCustomObject]@{ name = 'juemerson'; is_local = $false })
                    total_item_count = 1
                }
            }

            Resolve-PfbAdminLocality -Array $fb | Should -Be 'remote'
        }
    }
    It 'resolves a local admin to local' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            Mock -CommandName Invoke-PfbApiRequest -MockWith { @([PSCustomObject]@{ name = 'u'; is_local = $true }) }
            Resolve-PfbAdminLocality -Array ([PSCustomObject]@{ Endpoint = 'fb'; Username = 'u'; DefaultContext = $null; ContextOverride = $null }) |
                Should -Be 'local'
        }
    }
    It 'resolves a STATIC REMOTE admin to remote' {
        # The case that falsified the old design. A static-remote admin is is_local=$false with
        # authorization_model='static', and the array SERVES its context calls. If this returns
        # 'local', the gate blocks a working session -- the exact defect this task exists to fix.
        # Standing regression guard: do NOT switch the resolver back to authorization_model.
        InModuleScope 'PureStorageFlashBladePowerShell' {
            Mock -CommandName Invoke-PfbApiRequest -MockWith {
                @([PSCustomObject]@{ name = 'u'; is_local = $false; authorization_model = 'static' })
            }
            Resolve-PfbAdminLocality -Array ([PSCustomObject]@{ Endpoint = 'fb'; Username = 'u'; DefaultContext = $null; ContextOverride = $null }) |
                Should -Be 'remote'
        }
    }
    It 'returns null when the row carries no is_local property' {
        # $null -ne, never truthiness: absent must yield the indeterminate $null, not 'remote'.
        InModuleScope 'PureStorageFlashBladePowerShell' {
            Mock -CommandName Invoke-PfbApiRequest -MockWith { @([PSCustomObject]@{ name = 'u' }) }
            $null -eq (Resolve-PfbAdminLocality -Array ([PSCustomObject]@{ Endpoint = 'fb'; Username = 'u'; DefaultContext = $null; ContextOverride = $null })) |
                Should -BeTrue
        }
    }
    It 'ignores an admin row whose name does not match the connecting username' {
        # A wrong-row read is worse than no read: is_local=$true off a peer's row would hard-throw
        # a legitimate LDAP session out of Set-PfbContext. names= is a documented exact-match
        # filter, so this is defence in depth rather than an observed server behaviour.
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $fb = [PSCustomObject]@{
                PSTypeName = 'PureStorage.FlashBlade.Connection'
                Endpoint = 'fb.example'; ApiVersion = '2.26'; AuthToken = 't'; AuthMethod = 'ApiToken'
                Username = 'juemerson'
                DefaultContext = $null; ContextOverride = $null; AdminLocality = $null
            }
            Mock -CommandName Invoke-RestMethod -MockWith {
                [PSCustomObject]@{
                    items = @([PSCustomObject]@{ name = 'pureuser'; is_local = $true })
                    total_item_count = 1
                }
            }

            $null -eq (Resolve-PfbAdminLocality -Array $fb) | Should -BeTrue
        }
    }
    It 'returns null without a network call when the connection has no username' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            Mock -CommandName Invoke-PfbApiRequest -MockWith { throw 'must not be called' }
            $null -eq (Resolve-PfbAdminLocality -Array ([PSCustomObject]@{ Endpoint = 'fb.example'; Username = $null })) | Should -BeTrue
            Should -Invoke -CommandName Invoke-PfbApiRequest -Times 0
        }
    }
    # A BOUNDARY assertion on the outgoing URI, so it cannot pass vacuously. The probe asks who the
    # CONNECTED admin is; routing it through an existing context asks a DIFFERENT array. Set-PfbContext
    # made this reachable -- its $copy inherits the connection's existing context -- and GET /admins
    # declares context_names (scope: array), so none of the three shape gates stops it.
    It 'strips the context from its own probe, so an existing DefaultContext is not injected' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $fb = [PSCustomObject]@{
                PSTypeName = 'PureStorage.FlashBlade.Connection'
                Endpoint = 'fb.example'; ApiVersion = '2.26'; AuthToken = 't'; AuthMethod = 'ApiToken'
                Username = 'juemerson'
                # A bare Fleet context: the case that made the kind/scope gate throw INSIDE the
                # resolver, whose catch then silently downgraded a known 'remote' to $null.
                DefaultContext = (New-PfbContext -Entries @((New-PfbContextEntry -Name 'fleet-prod' -Kind 'Fleet')))
                ContextOverride = $null; AdminLocality = $null
            }
            $uris = [System.Collections.Generic.List[object]]::new()
            Mock -CommandName Invoke-RestMethod -MockWith {
                $uris.Add($Uri)
                [PSCustomObject]@{
                    items = @([PSCustomObject]@{ name = 'juemerson'; is_local = $false })
                    total_item_count = 1
                }
            }

            $locality = Resolve-PfbAdminLocality -Array $fb

            @($uris).Count | Should -Be 1
            $uris[0] | Should -Not -Match 'context_names' -Because 'the identity probe must never be context-scoped, or it is answered by another array'
            # The downgrade guard: without the strip this returns $null, because the kind gate
            # throws inside the resolver and the catch swallows it.
            $locality | Should -Be 'remote' -Because 'an existing context must not be able to downgrade a known locality to indeterminate'
            # And the caller's connection is untouched -- the strip works on a copy.
            @($fb.DefaultContext.Entries).Count | Should -Be 1
        }
    }
    It 'strips a ContextOverride from its own probe too, not just DefaultContext' {
        # Resolve-PfbRequestContext reads ContextOverride FIRST, so nulling only DefaultContext
        # would leave the defect fully open inside an Invoke-PfbInContext block.
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $fb = [PSCustomObject]@{
                PSTypeName = 'PureStorage.FlashBlade.Connection'
                Endpoint = 'fb.example'; ApiVersion = '2.26'; AuthToken = 't'; AuthMethod = 'ApiToken'
                Username = 'juemerson'
                DefaultContext = $null
                ContextOverride = (New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-B')))
                AdminLocality = $null
            }
            $uris = [System.Collections.Generic.List[object]]::new()
            Mock -CommandName Invoke-RestMethod -MockWith {
                $uris.Add($Uri)
                [PSCustomObject]@{
                    items = @([PSCustomObject]@{ name = 'juemerson'; is_local = $false })
                    total_item_count = 1
                }
            }

            Resolve-PfbAdminLocality -Array $fb | Should -Be 'remote'

            @($uris).Count | Should -Be 1
            $uris[0] | Should -Not -Match 'context_names' -Because 'an Array-kind override would route the identity probe to a remote array, and it is read before DefaultContext'
        }
    }
}
