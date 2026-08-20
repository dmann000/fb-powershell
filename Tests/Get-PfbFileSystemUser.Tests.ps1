#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.25'; AuthToken = 'x' }
}

Describe 'Get-PfbFileSystemUser' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    It 'GETs file-systems/users with AutoPaginate' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ arr = $fakeArray } {
            param($arr)
            Get-PfbFileSystemUser -Array $arr
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'GET' -and $Endpoint -eq 'file-systems/users' -and $AutoPaginate -eq $true
        }
    }

    It 'filters by -FileSystemName' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ arr = $fakeArray } {
            param($arr)
            Get-PfbFileSystemUser -FileSystemName 'fs1' -Array $arr
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['file_system_names'] -eq 'fs1'
        }
    }

    It 'sends -UserName as user_names, -UserId as uids, and -UserSid as user_sids' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ arr = $fakeArray } {
            param($arr)
            Get-PfbFileSystemUser -UserName 'jdoe' -UserId '1001' -UserSid 'S-1-5-1' -Array $arr
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['user_names'] -eq 'jdoe' -and $QueryParams['uids'] -eq '1001' -and $QueryParams['user_sids'] -eq 'S-1-5-1'
        }
    }

    It 'honors falsy -Limit 0 and empty -Filter instead of dropping them' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ arr = $fakeArray } {
            param($arr)
            Get-PfbFileSystemUser -Filter '' -Limit 0 -Array $arr
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams.ContainsKey('filter') -and $QueryParams['filter'] -eq '' -and
            $QueryParams.ContainsKey('limit') -and $QueryParams['limit'] -eq 0
        }
    }

    It 'does not expose -TotalOnly (file-systems/users does not declare total_only, #102)' {
        (Get-Command Get-PfbFileSystemUser).Parameters.Keys | Should -Not -Contain 'TotalOnly'

        { Get-PfbFileSystemUser -TotalOnly -Array $fakeArray } |
            Should -Throw -ExpectedMessage '*TotalOnly*'
    }
}
