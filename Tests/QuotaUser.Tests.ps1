#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule
    # A throwaway connection object; Assert-PfbConnection is mocked so its contents don't matter.
    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Get-PfbQuotaUser flatten' {
    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    It 'flattens nested user/file_system into top-level UserName/FileSystemName' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest {
            [pscustomobject]@{
                name        = 'fs-home:jdoe'
                user        = [pscustomobject]@{ name = 'jdoe' }
                file_system = [pscustomobject]@{ name = 'fs-home' }
                quota       = 1073741824
            }
        }
        $result = Get-PfbQuotaUser -FileSystemName 'fs-home' -Array $fakeArray
        $result.FileSystemName | Should -Be 'fs-home'
        $result.UserName       | Should -Be 'jdoe'
    }

    It 'sends only file_system_names when -Name is not supplied' {
        Get-PfbQuotaUser -FileSystemName 'fs-home' -Array $fakeArray
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $QueryParams['file_system_names'] -eq 'fs-home' -and -not $QueryParams.ContainsKey('names')
        }
    }

    It 'sends only names (omits file_system_names) when -Name is supplied alongside the mandatory -FileSystemName -- FlashBlade rejects combining names with file_system_names, confirmed live against our lab array' {
        Get-PfbQuotaUser -FileSystemName 'fs-home' -Name 'fs-home/1235' -Array $fakeArray
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $QueryParams['names'] -eq 'fs-home/1235' -and -not $QueryParams.ContainsKey('file_system_names')
        }
    }
}

Describe 'Remove-PfbQuotaUser' {
    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    It 'binds FileSystemName/UserName from a piped flattened quota (DELETE)' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -ParameterFilter { $Method -eq 'GET' } {
            [pscustomobject]@{
                name        = 'fs-home:jdoe'
                user        = [pscustomobject]@{ name = 'jdoe' }
                file_system = [pscustomobject]@{ name = 'fs-home' }
            }
        }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -ParameterFilter { $Method -ne 'GET' } { }
        Get-PfbQuotaUser -FileSystemName 'fs-home' -Array $fakeArray | Remove-PfbQuotaUser -Confirm:$false -Array $fakeArray
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'DELETE' -and $Endpoint -eq 'quotas/users' -and
            $QueryParams['user_names'] -eq 'jdoe' -and $QueryParams['file_system_names'] -eq 'fs-home'
        }
    }

    It 'pipes 2 quota objects into 2 separate DELETE calls' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
        @(
            [pscustomobject]@{ FileSystemName = 'fs-home'; UserName = 'jdoe' }
            [pscustomobject]@{ FileSystemName = 'fs-home'; UserName = 'asmith' }
        ) | Remove-PfbQuotaUser -Confirm:$false -Array $fakeArray
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 2 -Exactly -ParameterFilter { $Method -eq 'DELETE' }
    }

    It 'explicit -FileSystemName / -UserName still works' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
        Remove-PfbQuotaUser -FileSystemName 'fs-home' -UserName 'jdoe' -Confirm:$false -Array $fakeArray
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'DELETE' -and $QueryParams['user_names'] -eq 'jdoe' -and $QueryParams['file_system_names'] -eq 'fs-home'
        }
    }
}

Describe 'Update-PfbQuotaUser' {
    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    It 'binds FileSystemName/UserName from a piped flattened quota (PATCH with body)' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -ParameterFilter { $Method -eq 'GET' } {
            [pscustomobject]@{
                name        = 'fs-home:jdoe'
                user        = [pscustomobject]@{ name = 'jdoe' }
                file_system = [pscustomobject]@{ name = 'fs-home' }
            }
        }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -ParameterFilter { $Method -ne 'GET' } { }
        Get-PfbQuotaUser -FileSystemName 'fs-home' -Array $fakeArray | Update-PfbQuotaUser -Quota 999 -Confirm:$false -Array $fakeArray
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'PATCH' -and $Endpoint -eq 'quotas/users' -and
            $QueryParams['user_names'] -eq 'jdoe' -and $QueryParams['file_system_names'] -eq 'fs-home' -and
            $Body['quota'] -eq 999
        }
    }

    It 'explicit -FileSystemName / -UserName still works' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
        Update-PfbQuotaUser -FileSystemName 'fs-home' -UserName 'jdoe' -Quota 10737418240 -Confirm:$false -Array $fakeArray
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'PATCH' -and $QueryParams['user_names'] -eq 'jdoe' -and $QueryParams['file_system_names'] -eq 'fs-home'
        }
    }
}
