#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'New-PfbQuotaGroup' {
    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context '-GroupName path' {
        It 'POSTs quotas/groups with file_system_names + group_names and a quota-only body' {
            New-PfbQuotaGroup -FileSystemName 'fs-share' -GroupName 'engineering' -Quota 5368709120 -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and
                $Endpoint -eq 'quotas/groups' -and
                $QueryParams['file_system_names'] -eq 'fs-share' -and
                $QueryParams['group_names'] -eq 'engineering' -and
                $Body['quota'] -eq 5368709120 -and
                $Body.Keys.Count -eq 1
            }
        }
    }

    Context '-GroupId path' {
        It 'sends integer gids (not group_names)' {
            New-PfbQuotaGroup -FileSystemName 'fs-share' -GroupId 1001 -Quota 1073741824 -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and
                $Endpoint -eq 'quotas/groups' -and
                $QueryParams['file_system_names'] -eq 'fs-share' -and
                $QueryParams['gids'] -eq 1001 -and
                $QueryParams['gids'] -is [int] -and
                -not $QueryParams.ContainsKey('group_names')
            }
        }
    }

    Context '-Attributes override' {
        It 'uses the attributes hashtable as the body while identity remains in the query' {
            New-PfbQuotaGroup -FileSystemName 'fs-share' -GroupName 'engineering' -Attributes @{ quota = 2147483648 } -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['quota'] -eq 2147483648 -and
                $QueryParams['group_names'] -eq 'engineering' -and
                $QueryParams['file_system_names'] -eq 'fs-share'
            }
        }
    }

    Context 'regression: wrong shapes are never used' {
        It 'never sends the legacy names query key or nested group/file_system body fields' {
            New-PfbQuotaGroup -FileSystemName 'fs-share' -GroupName 'engineering' -Quota 100 -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                -not $QueryParams.ContainsKey('names') -and
                -not $Body.ContainsKey('group') -and
                -not $Body.ContainsKey('file_system')
            }
        }
    }

    Context 'identity validation' {
        It 'declares -GroupName and -GroupId mandatory in mutually exclusive parameter sets' {
            $cmd = Get-Command New-PfbQuotaGroup
            $groupNameSet = $cmd.Parameters['GroupName'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.ParameterSetName -eq 'ByName' }
            $groupIdSet = $cmd.Parameters['GroupId'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.ParameterSetName -eq 'ById' }

            $groupNameSet.Mandatory | Should -BeTrue
            $groupIdSet.Mandatory | Should -BeTrue
        }

        It 'throws when both -GroupName and -GroupId are supplied' {
            { New-PfbQuotaGroup -FileSystemName 'fs-share' -GroupName 'engineering' -GroupId 1001 -Confirm:$false -Array $fakeArray } |
                Should -Throw
        }
    }

    Context 'body validation' {
        It 'throws when neither -Quota nor -Attributes is supplied' {
            { New-PfbQuotaGroup -FileSystemName 'fs-share' -GroupName 'engineering' -Confirm:$false -Array $fakeArray } |
                Should -Throw
        }
    }
}
