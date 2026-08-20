#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule

    $script:originalModuleRoot = InModuleScope PureStorageFlashBladePowerShell { $script:PfbModuleRoot }
}

Describe 'Get-PfbVersionMap' {
    AfterEach {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ root = $script:originalModuleRoot } {
            $script:PfbVersionMap = $null
            $script:PfbModuleRoot = $root
        }
    }

    It 'loads and returns the map from Data/PfbVersionMap.json under the module root' {
        New-Item -ItemType Directory -Path 'TestDrive:\Data' -Force | Out-Null
        [PSCustomObject]@{ '2.27' = [PSCustomObject]@{ purity = '4.8.3' } } |
            ConvertTo-Json -Depth 10 | Set-Content -Path 'TestDrive:\Data\PfbVersionMap.json'

        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ root = 'TestDrive:\' } {
            $script:PfbModuleRoot = $root
            $result = Get-PfbVersionMap
            $result.'2.27'.purity | Should -Be '4.8.3'
        }
    }

    It 'caches the loaded map -- a second call does not re-read the file' {
        New-Item -ItemType Directory -Path 'TestDrive:\Data' -Force | Out-Null
        [PSCustomObject]@{ '2.27' = [PSCustomObject]@{ purity = '4.8.3' } } |
            ConvertTo-Json -Depth 10 | Set-Content -Path 'TestDrive:\Data\PfbVersionMap.json'

        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ root = 'TestDrive:\' } {
            $script:PfbModuleRoot = $root
            $first = Get-PfbVersionMap
            Remove-Item -Path (Join-Path $root 'Data/PfbVersionMap.json') -Force
            $second = Get-PfbVersionMap
            [object]::ReferenceEquals($first, $second) | Should -BeTrue
        }
    }

    It 'returns $null gracefully when Data/PfbVersionMap.json does not exist' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ root = 'TestDrive:\empty' } {
            $script:PfbModuleRoot = $root
            Get-PfbVersionMap | Should -BeNullOrEmpty
        }
    }
}
