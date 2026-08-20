#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule
}

Describe 'Set-PfbTlsProtocol' {
    It 'sets SecurityProtocol to Tls12 on Windows PowerShell 5.1' -Skip:($PSVersionTable.PSVersion.Major -ge 6) {
        InModuleScope PureStorageFlashBladePowerShell {
            $original = [System.Net.ServicePointManager]::SecurityProtocol
            try {
                [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Ssl3
                Set-PfbTlsProtocol
                [System.Net.ServicePointManager]::SecurityProtocol | Should -Be ([System.Net.SecurityProtocolType]::Tls12)
            }
            finally {
                [System.Net.ServicePointManager]::SecurityProtocol = $original
            }
        }
    }

    It 'is a no-op on PowerShell 7+' -Skip:($PSVersionTable.PSVersion.Major -lt 6) {
        InModuleScope PureStorageFlashBladePowerShell {
            { Set-PfbTlsProtocol } | Should -Not -Throw
        }
    }
}
