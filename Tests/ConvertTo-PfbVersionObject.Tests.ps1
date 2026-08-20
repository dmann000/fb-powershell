#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule
}

Describe 'ConvertTo-PfbVersionObject' {
    It 'parses Version/Major/Minor correctly for a simple list' {
        $result = InModuleScope PureStorageFlashBladePowerShell {
            ConvertTo-PfbVersionObject -Versions @('1.8', '2.9')
        }
        $v18 = $result | Where-Object { $_.Version -eq '1.8' }
        $v29 = $result | Where-Object { $_.Version -eq '2.9' }

        $v18.Major | Should -Be 1
        $v18.Minor | Should -Be 8
        $v29.Major | Should -Be 2
        $v29.Minor | Should -Be 9
    }

    It 'sorts numerically, not lexicographically (2.26 ranks above 2.9)' {
        $result = InModuleScope PureStorageFlashBladePowerShell {
            ConvertTo-PfbVersionObject -Versions @('2.9', '2.26', '2.10')
        }

        $result[0].Version | Should -Be '2.26'
        $result[1].Version | Should -Be '2.10'
        $result[2].Version | Should -Be '2.9'
    }

    It 'sorts a mix of 1.x and 2.x versions with 2.x ranking highest' {
        $result = InModuleScope PureStorageFlashBladePowerShell {
            ConvertTo-PfbVersionObject -Versions @('1.12', '1.8', '2.0', '2.26')
        }

        $result[0].Version | Should -Be '2.26'
        $result[1].Version | Should -Be '2.0'
        $result[2].Version | Should -Be '1.12'
        $result[3].Version | Should -Be '1.8'
    }

    It 'ranks a hypothetical future major version 3.0 above all 2.x versions' {
        $result = InModuleScope PureStorageFlashBladePowerShell {
            ConvertTo-PfbVersionObject -Versions @('2.26', '3.0', '2.9')
        }

        $result[0].Version | Should -Be '3.0'
    }

    It 'handles single-digit and double-digit minors correctly within the same major' {
        $result = InModuleScope PureStorageFlashBladePowerShell {
            ConvertTo-PfbVersionObject -Versions @('1.9', '1.10', '1.11')
        }

        $result[0].Version | Should -Be '1.11'
        $result[1].Version | Should -Be '1.10'
        $result[2].Version | Should -Be '1.9'
    }
}
