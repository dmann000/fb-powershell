#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Update-PfbDirectoryServiceRole - typed body + query parameters (#31)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'typed parameters build the body' {
        It 'sends group and group_base as body fields' {
            Update-PfbDirectoryServiceRole -Name 'ad-admins' -Group 'CN=FB-SuperAdmins,OU=Groups,DC=corp,DC=example,DC=com' `
                -GroupBase 'DC=corp,DC=example,DC=com' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Endpoint -eq 'directory-services/roles' -and
                $QueryParams['names'] -eq 'ad-admins' -and
                $Body['group'] -eq 'CN=FB-SuperAdmins,OU=Groups,DC=corp,DC=example,DC=com' -and
                $Body['group_base'] -eq 'DC=corp,DC=example,DC=com'
            }
        }

        It 'sends an EMPTY string for -Group "" rather than dropping the key' {
            Update-PfbDirectoryServiceRole -Name 'ad-admins' -Group '' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('group') -and $Body['group'] -eq ''
            }
        }

        It 'omits every body key when no typed body parameter is supplied' {
            Update-PfbDirectoryServiceRole -Name 'ad-admins' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.Count -eq 0
            }
        }

        It 'targets the role by id when -Id is used' {
            Update-PfbDirectoryServiceRole -Id 'role-1' -Group 'g' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['ids'] -eq 'role-1' -and -not $QueryParams.ContainsKey('names')
            }
        }
    }

    Context '-RoleIds/-RoleNames are not exposed (constraint 9 precedent: structurally dead field)' {
        It 'has no -RoleIds parameter' {
            (Get-Command Update-PfbDirectoryServiceRole).Parameters.Keys | Should -Not -Contain 'RoleIds'
        }

        It 'has no -RoleNames parameter' {
            (Get-Command Update-PfbDirectoryServiceRole).Parameters.Keys | Should -Not -Contain 'RoleNames'
        }
    }

    Context '-Attributes remains supported and is mutually exclusive' {
        It 'still sends a raw -Attributes body' {
            Update-PfbDirectoryServiceRole -Name 'ad-admins' -Attributes @{ group = 'raw-group' } `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['group'] -eq 'raw-group'
            }
        }

        It 'rejects -Attributes combined with a typed parameter at bind time' {
            { Update-PfbDirectoryServiceRole -Name 'ad-admins' -Group 'g' -Attributes @{ group = 'y' } `
                -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'
        }
    }

    Context 'deprecated fields are not exposed (constraint 9)' {
        It 'has no -Role parameter' {
            (Get-Command Update-PfbDirectoryServiceRole).Parameters.Keys | Should -Not -Contain 'Role'
        }
    }

    Context 'read-only fields are not exposed (constraint 11)' {
        It 'has no -ManagementAccessPolicies parameter' {
            (Get-Command Update-PfbDirectoryServiceRole).Parameters.Keys | Should -Not -Contain 'ManagementAccessPolicies'
        }
    }

    Context 'constraint compliance' {
        It 'puts no ValidateSet on -<Parameter> (constraint 3, no spec enum)' -ForEach @(
            @{ Parameter = 'Group' }
            @{ Parameter = 'GroupBase' }
        ) {
            $attrs = (Get-Command Update-PfbDirectoryServiceRole).Parameters[$Parameter].Attributes
            @($attrs | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).Count |
                Should -Be 0
        }

        It 'exposes every settable body field the endpoint accepts' {
            $keys = (Get-Command Update-PfbDirectoryServiceRole).Parameters.Keys
            foreach ($p in 'Group', 'GroupBase') {
                $keys | Should -Contain $p
            }
        }
    }
}
