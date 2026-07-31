#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.25'; AuthToken = 'x' }
}

Describe 'New-PfbUserGroupQuotaPolicy' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    It 'POSTs user-group-quota-policies with the name query param and an empty body by default' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ arr = $fakeArray } {
            param($arr)
            New-PfbUserGroupQuotaPolicy -Name 'pol-1' -Confirm:$false -Array $arr
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'POST' -and
            $Endpoint -eq 'user-group-quota-policies' -and
            $QueryParams['names'] -eq 'pol-1' -and
            $Body.Keys.Count -eq 0
        }
    }

    It 'builds enabled/location/rules into the body from typed params' {
        $rules = @(@{ quota_type = 'user-default'; quota_limit = 1073741824 })
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ arr = $fakeArray; rules = $rules } {
            param($arr, $rules)
            New-PfbUserGroupQuotaPolicy -Name 'pol-1' -Enabled:$false -Rules $rules -Confirm:$false -Array $arr
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $Body['enabled'] -eq $false -and
            $Body['rules'][0]['quota_type'] -eq 'user-default'
        }
    }

    It 'sends file_system_names for the legacy-quota-import path, mutually exclusive with file_system_ids' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ arr = $fakeArray } {
            param($arr)
            New-PfbUserGroupQuotaPolicy -Name 'pol-1' -FileSystemName 'fs1' -Confirm:$false -Array $arr
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['file_system_names'] -eq 'fs1' -and -not $QueryParams.ContainsKey('file_system_ids')
        }
    }

    It 'throws when both -FileSystemName and -FileSystemId are supplied' {
        { InModuleScope PureStorageFlashBladePowerShell -Parameters @{ arr = $fakeArray } {
            param($arr)
            New-PfbUserGroupQuotaPolicy -Name 'pol-1' -FileSystemName 'fs1' -FileSystemId 'id1' -Confirm:$false -Array $arr
        } } |
            Should -Throw
    }

    It '-Attributes overrides the constructed body verbatim' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ arr = $fakeArray } {
            param($arr)
            New-PfbUserGroupQuotaPolicy -Name 'pol-1' -Attributes @{ enabled = $true } -Confirm:$false -Array $arr
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $Body['enabled'] -eq $true -and $Body.Keys.Count -eq 1
        }
    }

    It 'does not call the API under -WhatIf' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ arr = $fakeArray } {
            param($arr)
            New-PfbUserGroupQuotaPolicy -Name 'pol-1' -WhatIf -Array $arr
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0
    }
}
