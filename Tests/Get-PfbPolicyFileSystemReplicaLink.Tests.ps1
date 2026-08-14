#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1') -Force

    $script:fakeArray  = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
    $script:sourceFile = [System.IO.Path]::Combine($moduleRoot, 'Public', 'Policy', 'Get-PfbPolicyFileSystemReplicaLink.ps1')
}

Describe 'Get-PfbPolicyFileSystemReplicaLink - member selection is by ID only (#88)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    It 'publishes no MemberName parameter' {
        (Get-Command Get-PfbPolicyFileSystemReplicaLink).Parameters.Keys | Should -Not -Contain 'MemberName'
    }

    It 'hides no MemberName alias on another parameter' {
        $aliases = (Get-Command Get-PfbPolicyFileSystemReplicaLink).Parameters.Values | ForEach-Object { $_.Aliases }
        $aliases | Should -Not -Contain 'MemberName'
    }

    It 'fails at binding when -MemberName is supplied, and issues no request' {
        { Get-PfbPolicyFileSystemReplicaLink -MemberName 'fs01' -Array $script:fakeArray -ErrorAction Stop } |
            Should -Throw

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
    }

    It 'sends member_ids and never member_names' {
        Get-PfbPolicyFileSystemReplicaLink -PolicyId 'pid1' -MemberId 'm1', 'm2' -Array $script:fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'GET' -and $Endpoint -eq 'policies/file-system-replica-links' -and
            $QueryParams['policy_ids'] -eq 'pid1' -and
            $QueryParams['member_ids'] -eq 'm1,m2' -and
            -not $QueryParams.ContainsKey('member_names')
        }
    }
}

Describe 'Get-PfbPolicyFileSystemReplicaLink - documented remote selectors (#88)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    It 'publishes <Param> as [string[]] with ValidateNotNullOrEmpty' -ForEach @(
        @{ Param = 'RemoteName' }
        @{ Param = 'RemoteId' }
    ) {
        $p = (Get-Command Get-PfbPolicyFileSystemReplicaLink).Parameters[$Param]
        $p | Should -Not -BeNullOrEmpty
        $p.ParameterType.FullName | Should -Be 'System.String[]'
        $p.Attributes.TypeId.Name | Should -Contain 'ValidateNotNullOrEmptyAttribute'
    }

    It 'joins remote_ids with a comma and omits remote_names' {
        Get-PfbPolicyFileSystemReplicaLink -RemoteId 'ri1', 'ri2' -Array $script:fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['remote_ids'] -eq 'ri1,ri2' -and -not $QueryParams.ContainsKey('remote_names')
        }
    }

    It 'joins remote_names with a comma and omits remote_ids' {
        Get-PfbPolicyFileSystemReplicaLink -RemoteName 'r1', 'r2' -Array $script:fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['remote_names'] -eq 'r1,r2' -and -not $QueryParams.ContainsKey('remote_ids')
        }
    }

    It 'omits both remote keys when neither selector is supplied' {
        Get-PfbPolicyFileSystemReplicaLink -PolicyName 'p1' -Array $script:fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            -not $QueryParams.ContainsKey('remote_names') -and -not $QueryParams.ContainsKey('remote_ids')
        }
    }

    It 'refuses both remote selectors together, and issues no request' {
        { Get-PfbPolicyFileSystemReplicaLink -RemoteName 'r1' -RemoteId 'ri1' -Array $script:fakeArray -ErrorAction Stop } |
            Should -Throw '*mutually exclusive*'

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
    }
}

Describe 'Get-PfbPolicyFileSystemReplicaLink - endpoint declares no generic ids (#88)' {

    It 'publishes no <Param> parameter' -ForEach @(
        @{ Param = 'Id' }
        @{ Param = 'Name' }
    ) {
        (Get-Command Get-PfbPolicyFileSystemReplicaLink).Parameters.Keys | Should -Not -Contain $Param
    }
}

Describe 'Get-PfbPolicyFileSystemReplicaLink - help states endpoint rules, not change history (#88)' {

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
        $h = Get-Help Get-PfbPolicyFileSystemReplicaLink -Full -ErrorAction Stop
        $h.Description.Text | Should -Not -BeNullOrEmpty

        $documented = @($h.parameters.parameter.name)
        $published = (Get-Command Get-PfbPolicyFileSystemReplicaLink).Parameters.Keys |
            Where-Object {
                $_ -notin [System.Management.Automation.PSCmdlet]::CommonParameters -and
                $_ -notin [System.Management.Automation.PSCmdlet]::OptionalCommonParameters
            }

        foreach ($p in $published) { $documented | Should -Contain $p }
    }
}
