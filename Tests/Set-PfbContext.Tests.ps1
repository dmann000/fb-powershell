#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule
}

Describe 'Set-PfbContext' {
    BeforeEach {
        # Username IS declared. It was absent, and that absence was silently load-bearing: the
        # resolver early-returns without a username, so `It 'makes no network call'` below passed
        # by fixture accident rather than because the cmdlet made no call. A fixture that has to
        # omit a real property to keep a test green is documenting the wrong thing.
        $script:fb = [PSCustomObject]@{
            PSTypeName = 'PureStorage.FlashBlade.Connection'
            Endpoint = 'fb.example'; ApiVersion = '2.26'; Username = 'jdoe'
            DefaultContext = $null; ContextOverride = $null; AdminLocality = $null
        }
    }
    It 'returns a new connection and leaves the original untouched' {
        $new = Set-PfbContext -Array $script:fb -Context 'FB-B'
        $new.DefaultContext.Entries[0].Name | Should -Be 'FB-B'
        # Not -BeNullOrEmpty: it cannot tell $null (unset) from an entry list with zero entries
        # (explicit no-context), and that distinction is the whole tri-state. Banned project-wide.
        $null -eq $script:fb.DefaultContext | Should -BeTrue
        [object]::ReferenceEquals($new, $script:fb) | Should -BeFalse
    }
    It 'emits exactly ONE connection for N piped members, scoped to the union' {
        $result = @('FB-B', 'FB-C') | Set-PfbContext -Array $script:fb
        @($result).Count                      | Should -Be 1
        @($result.DefaultContext.Entries).Count | Should -Be 2
        $result.DefaultContext.Entries.Name   | Should -Be @('FB-B', 'FB-C')
    }
    It 'binds MemberName by property name, so Get-PfbFleetMember pipes straight in' {
        $piped = @(
            [PSCustomObject]@{ MemberName = 'FB-B' },
            [PSCustomObject]@{ MemberName = 'FB-C' }
        )
        $result = $piped | Set-PfbContext -Array $script:fb
        $result.DefaultContext.Entries.Name | Should -Be @('FB-B', 'FB-C')
    }
    It 'binds Name by property name, for the eventual Get-PfbTopologyGroup contract (#38)' {
        $result = [PSCustomObject]@{ Name = 'region-1' } | Set-PfbContext -Array $script:fb -Kind 'TopologyGroup' -AllArrays
        $result.DefaultContext.Entries[0].Name | Should -Be 'region-1'
        $result.DefaultContext.Entries[0].Form | Should -Be 'AllArrays'
    }
    It 'rejects Array + -AllArrays' {
        { Set-PfbContext -Array $script:fb -Context 'FB-B' -AllArrays } |
            Should -Throw -ExpectedMessage '*an array has no members*'
    }
    It 'rejects TopologyGroup without -AllArrays' {
        { Set-PfbContext -Array $script:fb -Context 'region-1' -Kind 'TopologyGroup' } |
            Should -Throw -ExpectedMessage '*<name>.arrays*'
    }
    It 'throws its own error for a missing -Context rather than prompting' {
        # NOT [Parameter(Mandatory)] + Should -Throw: that hangs on the interactive prompt
        # under -NonInteractive.
        { Set-PfbContext -Array $script:fb } | Should -Throw -ExpectedMessage '*-Context*'
    }
    # Was 'makes no network call', which is no longer true and had stopped being a real test: with
    # the fixture's Username absent the resolver early-returned, so the -Times 0 assertions held
    # for a reason that had nothing to do with the cmdlet's behaviour. Now stated as what is
    # actually guaranteed -- the CONTEXT is never resolved on the wire -- and pinned against a
    # username-bearing fixture, so exactly one admin read is expected and nothing more.
    It 'reads the admin locality exactly once and never resolves the context name on the wire' {
        Mock -CommandName Invoke-PfbApiRequest -ModuleName 'PureStorageFlashBladePowerShell' -MockWith {
            @([PSCustomObject]@{ name = 'jdoe'; is_local = $false })
        }
        Mock -CommandName Invoke-RestMethod -ModuleName 'PureStorageFlashBladePowerShell' -MockWith {
            throw 'Set-PfbContext must not call Invoke-RestMethod directly'
        }

        Set-PfbContext -Array $script:fb -Context 'no-such-array-at-all' | Out-Null

        # Exactly one request, and it is the admin read -- NOT a lookup of the context name. A
        # deliberately non-existent name is used: if this cmdlet ever validated it on the wire,
        # that call would be a second invocation here.
        Should -Invoke -CommandName Invoke-PfbApiRequest -ModuleName 'PureStorageFlashBladePowerShell' -Times 1 -Exactly
        Should -Invoke -CommandName Invoke-PfbApiRequest -ModuleName 'PureStorageFlashBladePowerShell' `
            -ParameterFilter { $Endpoint -eq 'admins' } -Times 1 -Exactly `
            -Because 'the only permitted call is the admin-locality probe'
        Should -Invoke -CommandName Invoke-RestMethod -ModuleName 'PureStorageFlashBladePowerShell' -Times 0
    }
    # A SEPARATE call site from Invoke-PfbApiRequest's request path -- the wiring test over there
    # says nothing about this one, and vice versa.
    It 'calls the admin-locality gate with the target connection and the composed context' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            # AdminLocality starts $null, which is now the COMMON state: since the
            # 2026-08-05 ruling a bare connect resolves nothing. Set-PfbContext must resolve it
            # itself, so the gate seeing 'remote' below is evidence it did.
            $fb = [PSCustomObject]@{
                PSTypeName = 'PureStorage.FlashBlade.Connection'
                Endpoint = 'fb.example'; ApiVersion = '2.26'; Username = 'jdoe'
                DefaultContext = $null; ContextOverride = $null; AdminLocality = $null
            }
            Mock -CommandName Resolve-PfbAdminLocality -MockWith { 'remote' }
            $seen = [System.Collections.Generic.List[object]]::new()
            Mock -CommandName Assert-PfbContextAdminLocality -MockWith {
                $seen.Add([PSCustomObject]@{ Locality = $Array.AdminLocality; Names = @($Context.Entries.Name) -join ',' })
            }

            Set-PfbContext -Array $fb -Context 'FB-B' | Out-Null

            @($seen).Count | Should -Be 1 -Because "Set-PfbContext's end{} must call the gate; a count of 0 means the call was deleted or never wired"
            $seen[0].Locality | Should -Be 'remote' -Because 'Set-PfbContext must resolve the locality itself and hand the gate a connection carrying it; $null here means the resolution was deleted or never wired'
            $seen[0].Names | Should -Be 'FB-B'
        }
    }
    # THE detector for Set-PfbContext's own resolution site, independent of the gate wiring above.
    It 'resolves the admin locality itself, exactly once, without mutating the caller' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $fb = [PSCustomObject]@{
                PSTypeName = 'PureStorage.FlashBlade.Connection'
                Endpoint = 'fb.example'; ApiVersion = '2.26'; Username = 'jdoe'
                DefaultContext = $null; ContextOverride = $null; AdminLocality = $null
            }
            Mock -CommandName Resolve-PfbAdminLocality -MockWith { 'remote' }

            $new = Set-PfbContext -Array $fb -Context 'FB-B'

            Should -Invoke -CommandName Resolve-PfbAdminLocality -Times 1 -Exactly
            $new.AdminLocality | Should -Be 'remote'
            # Copy-on-write covers the locality too: it is written onto the copy, never onto the
            # object the caller still holds.
            $null -eq $fb.AdminLocality | Should -BeTrue -Because 'the locality is written onto the copy, not the caller connection'
        }
    }
    It 'refuses to set a context for a local admin' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $fb = [PSCustomObject]@{
                PSTypeName = 'PureStorage.FlashBlade.Connection'
                Endpoint = 'fb.example'; ApiVersion = '2.26'; Username = 'pureuser'
                DefaultContext = $null; ContextOverride = $null; AdminLocality = $null
            }
            Mock -CommandName Resolve-PfbAdminLocality -MockWith { 'local' }
            { Set-PfbContext -Array $fb -Context 'FB-B' } |
                Should -Throw -ExpectedMessage '*remotely authenticated*'
        }
    }
    It 'repoints the module caches at the copy' {
        InModuleScope 'PureStorageFlashBladePowerShell' {
            $originalArrays = $script:PfbArrays; $originalDefault = $script:PfbDefaultArray
            try {
                # AdminLocality is declared because the real connection object declares it
                # (Connect-PfbArray.ps1:477) and Set-PfbContext now WRITES it. Omitting it made
                # this fixture pass while the property was only ever read; a write to a property a
                # PSCustomObject does not have is a hard error, so the omission was latent
                # infidelity rather than a harmless shortcut.
                $fb = [PSCustomObject]@{ PSTypeName = 'PureStorage.FlashBlade.Connection'; Endpoint = 'fb.example'; DefaultContext = $null; ContextOverride = $null; AdminLocality = $null }
                $script:PfbArrays = @{ 'fb.example' = $fb }; $script:PfbDefaultArray = $fb
                $new = Set-PfbContext -Array $fb -Context 'FB-B'
                [object]::ReferenceEquals($script:PfbDefaultArray, $new) | Should -BeTrue
            }
            finally { & { param($a, $d) $script:PfbArrays = $a; $script:PfbDefaultArray = $d } $originalArrays $originalDefault }
        }
    }
}
