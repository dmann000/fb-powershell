#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'New-PfbObjectStoreAccountExport - POST wire contract (#101)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'identifying query parameters' {
        It 'emits member_names for -MemberName' {
            New-PfbObjectStoreAccountExport -MemberName 'acct1' -ServerName 'server1' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Endpoint -eq 'object-store-account-exports' -and
                $QueryParams['member_names'] -eq 'acct1' -and -not $QueryParams.ContainsKey('member_ids')
            }
        }

        It 'emits member_ids for -MemberId' {
            New-PfbObjectStoreAccountExport -MemberId 'member-id-1' -ServerName 'server1' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['member_ids'] -eq 'member-id-1' -and -not $QueryParams.ContainsKey('member_names')
            }
        }

        It 'emits policy_names for -PolicyName' {
            New-PfbObjectStoreAccountExport -MemberName 'acct1' -PolicyName 's3-policy' -ServerName 'server1' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['policy_names'] -eq 's3-policy' -and -not $QueryParams.ContainsKey('policy_ids')
            }
        }

        It 'emits policy_ids for -PolicyId' {
            New-PfbObjectStoreAccountExport -MemberName 'acct1' -PolicyId 'policy-id-1' -ServerName 'server1' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['policy_ids'] -eq 'policy-id-1' -and -not $QueryParams.ContainsKey('policy_names')
            }
        }

        It 'joins multi-valued member and policy lists with commas' {
            New-PfbObjectStoreAccountExport -MemberName 'acct1', 'acct2' -PolicyName 'p1', 'p2' -ServerName 'server1' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['member_names'] -eq 'acct1,acct2' -and $QueryParams['policy_names'] -eq 'p1,p2'
            }
        }

        It 'rejects -PolicyName combined with -PolicyId before any request fires' {
            { New-PfbObjectStoreAccountExport -MemberName 'acct1' -PolicyName 'p1' -PolicyId 'p-id-1' -ServerName 'server1' `
                -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*-PolicyName or -PolicyId*'

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
        }

        It 'never sends the generic names/ids query keys (regression guard for the dead key)' -ForEach @(
            @{ Splat = @{ MemberName = 'acct1'; ServerName = 'server1' } }
            @{ Splat = @{ MemberId   = 'member-id-1'; ServerId = 'server-id-1' } }
            @{ Splat = @{ MemberName = 'acct1'; PolicyName = 'p1'; ServerName = 'server1' } }
            @{ Splat = @{ MemberName = 'acct1'; Attributes = @{ server = @{ name = 'server1' } } } }
        ) {
            New-PfbObjectStoreAccountExport @Splat -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                -not $QueryParams.ContainsKey('names') -and -not $QueryParams.ContainsKey('ids')
            }
        }

        It 'no longer exposes a -Name parameter' {
            (Get-Command New-PfbObjectStoreAccountExport).Parameters.Keys | Should -Not -Contain 'Name'
        }
    }

    Context 'the required server body reference' {
        It 'builds server as a name reference for -ServerName' {
            New-PfbObjectStoreAccountExport -MemberName 'acct1' -ServerName 'server1' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['server'].name -eq 'server1' -and -not $Body['server'].ContainsKey('id')
            }
        }

        It 'builds server as an id reference for -ServerId' {
            New-PfbObjectStoreAccountExport -MemberName 'acct1' -ServerId 'server-id-1' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['server'].id -eq 'server-id-1' -and -not $Body['server'].ContainsKey('name')
            }
        }

        It 'never sends the readOnly resource_type field' {
            New-PfbObjectStoreAccountExport -MemberName 'acct1' -ServerName 'server1' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                -not $Body['server'].ContainsKey('resource_type')
            }
        }

        It 'throws before the request when no server identity is supplied' {
            { New-PfbObjectStoreAccountExport -MemberName 'acct1' -PolicyName 'p1' `
                -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*server identity is required*'

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
        }

        It 'throws before the request when both -ServerName and -ServerId are supplied' {
            { New-PfbObjectStoreAccountExport -MemberName 'acct1' -ServerName 'server1' -ServerId 'server-id-1' `
                -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*-ServerName or -ServerId*'

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
        }
    }

    Context 'export_enabled uses ContainsKey semantics, not truthiness' {
        It 'sends an explicit -ExportEnabled:$false' {
            New-PfbObjectStoreAccountExport -MemberName 'acct1' -ServerName 'server1' -ExportEnabled:$false `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('export_enabled') -and $Body['export_enabled'] -eq $false
            }
        }

        It 'sends an explicit -ExportEnabled:$true' {
            New-PfbObjectStoreAccountExport -MemberName 'acct1' -ServerName 'server1' -ExportEnabled:$true `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['export_enabled'] -eq $true
            }
        }

        It 'omits export_enabled entirely when -ExportEnabled is not supplied' {
            New-PfbObjectStoreAccountExport -MemberName 'acct1' -ServerName 'server1' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                -not $Body.ContainsKey('export_enabled')
            }
        }
    }

    Context '-Attributes escape hatch' {
        It 'sends the raw -Attributes body verbatim' {
            New-PfbObjectStoreAccountExport -MemberName 'acct1' -Attributes @{
                server = @{ name = 'server1' }; export_enabled = $false
            } -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['server'].name -eq 'server1' -and $Body['export_enabled'] -eq $false
            }
        }

        It 'rejects -Attributes combined with a typed body parameter at bind time' {
            { New-PfbObjectStoreAccountExport -MemberName 'acct1' -ServerName 'server1' -Attributes @{ export_enabled = $true } `
                -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'
        }

        It 'rejects -MemberName combined with -MemberId at bind time' {
            { New-PfbObjectStoreAccountExport -MemberName 'acct1' -MemberId 'member-id-1' -ServerName 'server1' `
                -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'
        }
    }

    Context 'ShouldProcess' {
        It 'fires no request under -WhatIf' {
            New-PfbObjectStoreAccountExport -MemberName 'acct1' -ServerName 'server1' `
                -WhatIf -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
        }
    }
}
