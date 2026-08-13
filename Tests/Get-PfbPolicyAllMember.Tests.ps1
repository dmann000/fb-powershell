#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    Import-Module "$PSScriptRoot/../PureStorageFlashBladePowerShell.psd1" -Force
    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }

    $script:sourceFile = [System.IO.Path]::Combine(
        (Split-Path -Parent $PSScriptRoot), 'Public', 'Policy', 'Get-PfbPolicyAllMember.ps1')
}

Describe 'Get-PfbPolicyAllMember' {
    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    It '-MemberType offers tab-completion for all five known spec-documented values (not a hard ValidateSet, since the spec value set has grown over time)' {
        $attr = (Get-Command Get-PfbPolicyAllMember).Parameters['MemberType'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ArgumentCompleterAttribute] }
        $attr | Should -Not -BeNullOrEmpty

        $validateSetAttr = (Get-Command Get-PfbPolicyAllMember).Parameters['MemberType'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
        $validateSetAttr | Should -BeNullOrEmpty

        $completions = & $attr.ScriptBlock 'Get-PfbPolicyAllMember' 'MemberType' '' $null @{}
        ($completions | Sort-Object) | Should -Be (@(
            'file-systems', 'file-system-snapshots', 'file-system-replica-links',
            'object-store-users', 'object-store-accounts'
        ) | Sort-Object)
    }

    It 'does NOT reject a value outside the known completion list (non-exhaustive, no hard validation)' {
        { Get-PfbPolicyAllMember -MemberType 'some-future-member-type' -Array $fakeArray } | Should -Not -Throw
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $QueryParams['member_types'] -eq 'some-future-member-type'
        }
    }

    It 'passes valid -MemberType values through to the query string, comma-joined' {
        Get-PfbPolicyAllMember -MemberType 'file-systems', 'object-store-accounts' -Array $fakeArray
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'GET' -and $Endpoint -eq 'policies-all/members' -and $QueryParams['member_types'] -eq 'file-systems,object-store-accounts'
        }
    }

    It 'omits -MemberType from the query string when not specified' {
        Get-PfbPolicyAllMember -Array $fakeArray
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            -not $QueryParams.ContainsKey('member_types')
        }
    }
}

Describe 'Get-PfbPolicyAllMember - member and remote selectors (#88)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    It 'keeps -MemberName, because policies-all/members declares member_names' {
        (Get-Command Get-PfbPolicyAllMember).Parameters.Keys | Should -Contain 'MemberName'

        Get-PfbPolicyAllMember -MemberName 'fs1', 'fs2' -Array $script:fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'GET' -and $Endpoint -eq 'policies-all/members' -and
            $QueryParams['member_names'] -eq 'fs1,fs2'
        }
    }

    It 'publishes <Param> as [string[]] with ValidateNotNullOrEmpty' -ForEach @(
        @{ Param = 'RemoteName' }
        @{ Param = 'RemoteId' }
    ) {
        $p = (Get-Command Get-PfbPolicyAllMember).Parameters[$Param]
        $p | Should -Not -BeNullOrEmpty
        $p.ParameterType.FullName | Should -Be 'System.String[]'
        $p.Attributes.TypeId.Name | Should -Contain 'ValidateNotNullOrEmptyAttribute'
    }

    It 'joins remote_names with a comma and omits remote_ids' {
        Get-PfbPolicyAllMember -RemoteName 'r1', 'r2' -Array $script:fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'GET' -and $Endpoint -eq 'policies-all/members' -and
            $QueryParams['remote_names'] -eq 'r1,r2' -and
            -not $QueryParams.ContainsKey('remote_ids')
        }
    }

    It 'joins remote_ids with a comma and omits remote_names' {
        Get-PfbPolicyAllMember -RemoteId 'ri1', 'ri2' -Array $script:fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['remote_ids'] -eq 'ri1,ri2' -and
            -not $QueryParams.ContainsKey('remote_names')
        }
    }

    It 'omits both remote keys when neither is supplied' {
        Get-PfbPolicyAllMember -PolicyName 'p1' -Array $script:fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            -not $QueryParams.ContainsKey('remote_names') -and
            -not $QueryParams.ContainsKey('remote_ids')
        }
    }

    It 'refuses both remote selectors together, and issues no request' {
        { Get-PfbPolicyAllMember -RemoteName 'r1' -RemoteId 'ri1' -Array $script:fakeArray -ErrorAction Stop } |
            Should -Throw '*mutually exclusive*'

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
    }

    It 'still emits member_names and member_ids alongside the remote selectors' {
        Get-PfbPolicyAllMember -MemberName 'fs1' -MemberId 'mid1' -RemoteName 'r1' -Array $script:fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['member_names'] -eq 'fs1' -and
            $QueryParams['member_ids'] -eq 'mid1' -and
            $QueryParams['remote_names'] -eq 'r1'
        }
    }

    It 'publishes no <Param> parameter - policies-all/members declares no generic ids' -ForEach @(
        @{ Param = 'Id' }
        @{ Param = 'Name' }
    ) {
        (Get-Command Get-PfbPolicyAllMember).Parameters.Keys | Should -Not -Contain $Param
    }
}

Describe 'Get-PfbPolicyAllMember - help states endpoint rules, not change history (#88)' {

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

    It 'documents every published parameter' {
        $h = Get-Help Get-PfbPolicyAllMember -Full -ErrorAction Stop
        $h.Description.Text | Should -Not -BeNullOrEmpty

        $documented = @($h.parameters.parameter.name)
        $published = (Get-Command Get-PfbPolicyAllMember).Parameters.Keys |
            Where-Object {
                $_ -notin [System.Management.Automation.PSCmdlet]::CommonParameters -and
                $_ -notin [System.Management.Automation.PSCmdlet]::OptionalCommonParameters
            }

        foreach ($p in $published) { $documented | Should -Contain $p }
    }
}
