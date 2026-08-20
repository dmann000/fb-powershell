#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule
    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.26'; AuthToken = 'x' }
}

Describe 'File-system export + local directory-services cmdlets' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'New-PfbFileSystemExport (creation contract)' {
        It 'posts member_names + policy_names query and export body, NOT a bogus names param' {
            New-PfbFileSystemExport -FileSystem 'fs1' -Policy 'nfs-default' -ExportName '/fs1' -Server 'server1' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and
                $Endpoint -eq 'file-system-exports' -and
                $QueryParams['member_names'] -eq 'fs1' -and
                $QueryParams['policy_names'] -eq 'nfs-default' -and
                -not $QueryParams.ContainsKey('names') -and
                $Body['export_name'] -eq '/fs1' -and
                $Body['server'].name -eq 'server1'
            }
        }
    }

    Context 'New-PfbLocalDirectoryService' {
        It 'posts to local/directory-services with names query' {
            New-PfbLocalDirectoryService -Name 'mydomain' -Domain 'mydomain' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and
                $Endpoint -eq 'directory-services/local/directory-services' -and
                $QueryParams['names'] -eq 'mydomain' -and
                $Body['domain'] -eq 'mydomain'
            }
        }
    }

    Context 'New-PfbLocalGroupMember (map external directory users into a local group)' {
        It 'posts members body { members = [ { member = { name } } ] } with group_names query' {
            New-PfbLocalGroupMember -Group 'mydomain\share-admins' -Member 'CORP\jdoe' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and
                $Endpoint -eq 'directory-services/local/groups/members' -and
                $QueryParams['group_names'] -eq 'mydomain\share-admins' -and
                $Body['members'].Count -eq 1 -and
                $Body['members'][0].member.name -eq 'CORP\jdoe'
            }
        }

        It 'supports multiple members in one call' {
            New-PfbLocalGroupMember -Group 'g1' -Member 'CORP\a','CORP\b' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['members'].Count -eq 2 -and
                $Body['members'][1].member.name -eq 'CORP\b'
            }
        }
    }

    Context 'Module exports the local directory-services cmdlets' {
        It 'exports all 8 local directory-services cmdlets' {
            $expected = 'Get-PfbLocalDirectoryService','New-PfbLocalDirectoryService',
                        'Get-PfbLocalGroup','New-PfbLocalGroup','Remove-PfbLocalGroup',
                        'Get-PfbLocalGroupMember','New-PfbLocalGroupMember','Remove-PfbLocalGroupMember'
            foreach ($c in $expected) {
                (Get-Command -Module PureStorageFlashBladePowerShell -Name $c -ErrorAction SilentlyContinue) | Should -Not -BeNullOrEmpty
            }
        }
    }
}
