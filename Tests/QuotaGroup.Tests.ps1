#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    Import-Module "$PSScriptRoot/../PureStorageFlashBladePowerShell.psd1" -Force
    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Remove-PfbQuotaGroup' {
    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    It 'binds FileSystemName/GroupName from a piped flattened quota (DELETE)' {
        [pscustomobject]@{ FileSystemName = 'fs-home'; GroupName = 'engineering' } |
            Remove-PfbQuotaGroup -Confirm:$false -Array $fakeArray

        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'DELETE' -and $Endpoint -eq 'quotas/groups' -and
            $QueryParams['group_names'] -eq 'engineering' -and
            $QueryParams['file_system_names'] -eq 'fs-home' -and
            -not $QueryParams.ContainsKey('names')
        }
    }

    It 'sends gids as an integer and not group_names' {
        Remove-PfbQuotaGroup -FileSystemName 'fs-home' -GroupId 1001 -Confirm:$false -Array $fakeArray

        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'DELETE' -and
            $QueryParams['gids'] -eq 1001 -and
            $QueryParams['gids'] -is [int] -and
            -not $QueryParams.ContainsKey('group_names') -and
            -not $QueryParams.ContainsKey('names')
        }
    }

    It 'throws when both -GroupName and -GroupId are supplied' {
        { Remove-PfbQuotaGroup -FileSystemName 'fs-home' -GroupName 'engineering' -GroupId 1001 -Confirm:$false -Array $fakeArray } |
            Should -Throw
    }
}

Describe 'Update-PfbQuotaGroup' {
    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    It 'binds FileSystemName/GroupName from a piped flattened quota (PATCH with body)' {
        [pscustomobject]@{ FileSystemName = 'fs-home'; GroupName = 'engineering' } |
            Update-PfbQuotaGroup -Quota 999 -Confirm:$false -Array $fakeArray

        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'PATCH' -and $Endpoint -eq 'quotas/groups' -and
            $QueryParams['group_names'] -eq 'engineering' -and
            $QueryParams['file_system_names'] -eq 'fs-home' -and
            $Body['quota'] -eq 999 -and
            -not $QueryParams.ContainsKey('names')
        }
    }

    It 'sends gids as an integer and not group_names' {
        Update-PfbQuotaGroup -FileSystemName 'fs-home' -GroupId 1001 -Quota 999 -Confirm:$false -Array $fakeArray

        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'PATCH' -and
            $QueryParams['gids'] -eq 1001 -and
            $QueryParams['gids'] -is [int] -and
            -not $QueryParams.ContainsKey('group_names') -and
            -not $QueryParams.ContainsKey('names')
        }
    }

    It 'throws when both -GroupName and -GroupId are supplied' {
        { Update-PfbQuotaGroup -FileSystemName 'fs-home' -GroupName 'engineering' -GroupId 1001 -Quota 999 -Confirm:$false -Array $fakeArray } |
            Should -Throw
    }
}
