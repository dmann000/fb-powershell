#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule

    $script:originalModuleRoot = InModuleScope PureStorageFlashBladePowerShell { $script:PfbModuleRoot }
}

Describe 'Get-PfbCapabilityMap' {
    AfterEach {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ root = $script:originalModuleRoot } {
            $script:PfbCapabilityMap = $null
            $script:PfbModuleRoot = $root
        }
    }

    It 'loads and returns the manifest from Data/PfbCapabilityMap.json under the module root' {
        New-Item -ItemType Directory -Path 'TestDrive:\Data' -Force | Out-Null
        [PSCustomObject]@{
            schemaVersion = 2
            endpoints     = [PSCustomObject]@{ 'GET /widgets' = [PSCustomObject]@{ minVersion = '9.0' } }
        } | ConvertTo-Json -Depth 10 | Set-Content -Path 'TestDrive:\Data\PfbCapabilityMap.json'

        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ root = 'TestDrive:\' } {
            $script:PfbModuleRoot = $root
            $result = Get-PfbCapabilityMap
            $result.endpoints.'GET /widgets'.minVersion | Should -Be '9.0'
        }
    }

    It 'caches the loaded manifest -- a second call does not re-read the file' {
        New-Item -ItemType Directory -Path 'TestDrive:\Data' -Force | Out-Null
        [PSCustomObject]@{ schemaVersion = 2; endpoints = [PSCustomObject]@{} } |
            ConvertTo-Json -Depth 10 | Set-Content -Path 'TestDrive:\Data\PfbCapabilityMap.json'

        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ root = 'TestDrive:\' } {
            $script:PfbModuleRoot = $root
            $first = Get-PfbCapabilityMap
            Remove-Item -Path (Join-Path $root 'Data/PfbCapabilityMap.json') -Force
            $second = Get-PfbCapabilityMap
            [object]::ReferenceEquals($first, $second) | Should -BeTrue
        }
    }

    It 'returns $null gracefully when Data/PfbCapabilityMap.json does not exist' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ root = 'TestDrive:\empty' } {
            $script:PfbModuleRoot = $root
            Get-PfbCapabilityMap | Should -BeNullOrEmpty
        }
    }
}
