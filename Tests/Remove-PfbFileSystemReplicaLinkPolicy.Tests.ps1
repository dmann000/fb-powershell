#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule

    $script:fakeArray  = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
    $script:sourceFile = [System.IO.Path]::Combine($moduleRoot, 'Public', 'Replication', 'Remove-PfbFileSystemReplicaLinkPolicy.ps1')
}

Describe 'Remove-PfbFileSystemReplicaLinkPolicy - member selection is by ID only (#88)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    It 'publishes no MemberName parameter' {
        (Get-Command Remove-PfbFileSystemReplicaLinkPolicy).Parameters.Keys | Should -Not -Contain 'MemberName'
    }

    It 'hides no MemberName alias on another parameter' {
        $aliases = (Get-Command Remove-PfbFileSystemReplicaLinkPolicy).Parameters.Values | ForEach-Object { $_.Aliases }
        $aliases | Should -Not -Contain 'MemberName'
    }

    It 'fails at binding when -MemberName is supplied, and deletes nothing' {
        { Remove-PfbFileSystemReplicaLinkPolicy -PolicyName 'p1' -MemberName 'fs01' -Confirm:$false -Array $script:fakeArray -ErrorAction Stop } |
            Should -Throw

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
    }

    It 'sends policy + member + remote qualifier on the wire' {
        Remove-PfbFileSystemReplicaLinkPolicy -PolicyName 'p1' -MemberId 'm1' -RemoteName 'r1' `
            -Confirm:$false -Array $script:fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'DELETE' -and $Endpoint -eq 'file-system-replica-links/policies' -and
            $QueryParams['policy_names'] -eq 'p1' -and
            $QueryParams['member_ids'] -eq 'm1' -and
            $QueryParams['remote_names'] -eq 'r1' -and
            -not $QueryParams.ContainsKey('member_names')
        }
    }

    It 'sends remote_ids when -RemoteId qualifies the removal' {
        Remove-PfbFileSystemReplicaLinkPolicy -PolicyId 'pid1' -MemberId 'm1' -RemoteId 'ri1' `
            -Confirm:$false -Array $script:fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['policy_ids'] -eq 'pid1' -and
            $QueryParams['member_ids'] -eq 'm1' -and
            $QueryParams['remote_ids'] -eq 'ri1' -and
            -not $QueryParams.ContainsKey('remote_names')
        }
    }
}

Describe 'Remove-PfbFileSystemReplicaLinkPolicy - fails closed before any destructive request (#88)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    It 'refuses a policy-wide removal with no member, and deletes nothing' {
        { Remove-PfbFileSystemReplicaLinkPolicy -PolicyName 'p1' -Confirm:$false -Array $script:fakeArray -ErrorAction Stop } |
            Should -Throw '*A replica link member must be identified: supply -MemberId*'

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
    }

    It 'refuses an unscoped removal with no policy, and deletes nothing' {
        { Remove-PfbFileSystemReplicaLinkPolicy -MemberId 'm1' -Confirm:$false -Array $script:fakeArray -ErrorAction Stop } |
            Should -Throw '*A policy must be identified: supply -PolicyName or -PolicyId.*'

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
    }

    It 'refuses a remote-only removal with no policy, and deletes nothing' {
        { Remove-PfbFileSystemReplicaLinkPolicy -RemoteName 'r1' -Confirm:$false -Array $script:fakeArray -ErrorAction Stop } |
            Should -Throw '*A policy must be identified: supply -PolicyName or -PolicyId.*'

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
    }

    It 'refuses both policy selectors together, and deletes nothing' {
        { Remove-PfbFileSystemReplicaLinkPolicy -PolicyName 'p1' -PolicyId 'pid1' -MemberId 'm1' -Confirm:$false -Array $script:fakeArray -ErrorAction Stop } |
            Should -Throw '*mutually exclusive*'

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
    }

    It 'refuses both remote selectors together, and deletes nothing' {
        { Remove-PfbFileSystemReplicaLinkPolicy -PolicyName 'p1' -MemberId 'm1' -RemoteName 'r1' -RemoteId 'ri1' -Confirm:$false -Array $script:fakeArray -ErrorAction Stop } |
            Should -Throw '*mutually exclusive*'

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
    }
}

Describe 'Remove-PfbFileSystemReplicaLinkPolicy - endpoint declares no generic ids (#88)' {

    It 'publishes no <Param> parameter' -ForEach @(
        @{ Param = 'Id' }
        @{ Param = 'Name' }
    ) {
        (Get-Command Remove-PfbFileSystemReplicaLinkPolicy).Parameters.Keys | Should -Not -Contain $Param
    }
}

Describe 'Remove-PfbFileSystemReplicaLinkPolicy - help claims only what the endpoint declares (#88)' {

    It 'makes no conditional-removal claim about server behaviour' {
        $lower = (Get-Content -Path $script:sourceFile -Raw).ToLowerInvariant()

        foreach ($phrase in @('only if', 'no-op', 'noop')) {
            $lower.Contains($phrase) | Should -BeFalse -Because "'$phrase' asserts unverified server behaviour"
        }
    }

    It 'describes the remote selectors as declared query parameters' {
        $text = Get-Content -Path $script:sourceFile -Raw
        $text.Contains('declared `remote_names` query') -or $text.Contains('declared `remote_ids` query') |
            Should -BeTrue
    }

    # .Contains() rather than -like: PowerShell wildcard patterns treat a backtick as an
    # escape character, and this file is full of backtick-quoted wire keys.
    It 'carries no change-history narrative in its help' {
        $lower = (Get-Content -Path $script:sourceFile -Raw).ToLowerInvariant()

        foreach ($phrase in @(
                'the former',
                'retained here deliberately',
                'lost theirs',
                'has been removed',
                'previously',
                'no longer',
                'siblings'
            )) {
            $lower.Contains($phrase) | Should -BeFalse -Because "'$phrase' is release-note content in Get-Help output"
        }
    }

    It 'states the member-selection rule in the present tense' {
        (Get-Content -Path $script:sourceFile -Raw).Contains('This endpoint selects members by ID only') |
            Should -BeTrue
    }

    It 'documents every published parameter' {
        $h = Get-Help Remove-PfbFileSystemReplicaLinkPolicy -Full -ErrorAction Stop
        $h.Description.Text | Should -Not -BeNullOrEmpty

        $documented = @($h.parameters.parameter.name)
        $published = (Get-Command Remove-PfbFileSystemReplicaLinkPolicy).Parameters.Keys |
            Where-Object {
                $_ -notin [System.Management.Automation.PSCmdlet]::CommonParameters -and
                $_ -notin [System.Management.Automation.PSCmdlet]::OptionalCommonParameters
            }

        foreach ($p in $published) { $documented | Should -Contain $p }
    }
}
