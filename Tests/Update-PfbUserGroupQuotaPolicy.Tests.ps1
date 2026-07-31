#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.25'; AuthToken = 'x' }
}

Describe 'Update-PfbUserGroupQuotaPolicy' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    It 'PATCHes user-group-quota-policies by -Name' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ arr = $fakeArray } {
            param($arr)
            Update-PfbUserGroupQuotaPolicy -Name 'pol-1' -Enabled:$false -Confirm:$false -Array $arr
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'PATCH' -and
            $Endpoint -eq 'user-group-quota-policies' -and
            $QueryParams['names'] -eq 'pol-1' -and
            $Body['enabled'] -eq $false
        }
    }

    It 'targets by -Id when supplied instead of -Name' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ arr = $fakeArray } {
            param($arr)
            Update-PfbUserGroupQuotaPolicy -Id 'id-1' -Rules @(@{ quota_limit = 5 }) -Confirm:$false -Array $arr
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['ids'] -eq 'id-1' -and -not $QueryParams.ContainsKey('names') -and
            $Body['rules'][0]['quota_limit'] -eq 5
        }
    }

    It 'sends ignore_usage and versions when requested' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ arr = $fakeArray } {
            param($arr)
            Update-PfbUserGroupQuotaPolicy -Name 'pol-1' -Enabled:$true -IgnoreUsage -Version 'v1' -Confirm:$false -Array $arr
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['ignore_usage'] -eq 'true' -and $QueryParams['versions'] -eq 'v1'
        }
    }

    It '-Attributes overrides the constructed body verbatim' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ arr = $fakeArray } {
            param($arr)
            Update-PfbUserGroupQuotaPolicy -Name 'pol-1' -Attributes @{ enabled = $true } -Confirm:$false -Array $arr
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $Body.Keys.Count -eq 1 -and $Body['enabled'] -eq $true
        }
    }

    It 'rejects a -Name that looks like a wildcard' {
        { InModuleScope PureStorageFlashBladePowerShell -Parameters @{ arr = $fakeArray } {
            param($arr)
            Update-PfbUserGroupQuotaPolicy -Name '*' -Enabled:$true -Confirm:$false -Array $arr
        } } | Should -Throw
    }

    It 'does not call the API under -WhatIf' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ arr = $fakeArray } {
            param($arr)
            Update-PfbUserGroupQuotaPolicy -Name 'pol-1' -Enabled:$true -WhatIf -Array $arr
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0
    }

    It 'declares -Name and -Id mandatory in mutually exclusive parameter sets (rejects neither being supplied)' {
        InModuleScope PureStorageFlashBladePowerShell {
            $cmd = Get-Command Update-PfbUserGroupQuotaPolicy
            $nameSet = $cmd.Parameters['Name'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.ParameterSetName -eq 'ByName' }
            $idSet = $cmd.Parameters['Id'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.ParameterSetName -eq 'ById' }

            $nameSet.Mandatory | Should -BeTrue
            $idSet.Mandatory | Should -BeTrue
        }
    }
}
