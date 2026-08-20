#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule

    $script:testPassword = ConvertTo-SecureString 'hunter2' -AsPlainText -Force
}

Describe 'Get-PfbApiTokenViaSsh' {
    Context 'Posh-SSH not installed' {
        It 'throws an informative install-instructions error' {
            Mock -ModuleName PureStorageFlashBladePowerShell Get-Module { $null } -ParameterFilter { $ListAvailable -and $Name -eq 'Posh-SSH' }

            { InModuleScope PureStorageFlashBladePowerShell { Get-PfbApiTokenViaSsh -Endpoint 'fb.test' -Username 'pureuser' -Password (ConvertTo-SecureString 'hunter2' -AsPlainText -Force) } } |
                Should -Throw -ExpectedMessage '*Install-Module -Name Posh-SSH*'
        }
    }

    Context 'Posh-SSH installed, existing token retrieval' {
        BeforeEach {
            Mock -ModuleName PureStorageFlashBladePowerShell Get-Module { [PSCustomObject]@{ Name = 'Posh-SSH' } } -ParameterFilter { $ListAvailable -and $Name -eq 'Posh-SSH' }
            Mock -ModuleName PureStorageFlashBladePowerShell Import-Module { } -ParameterFilter { $Name -eq 'Posh-SSH' }
            Mock -ModuleName PureStorageFlashBladePowerShell New-SSHSession { [PSCustomObject]@{ SessionId = 1 } }
            Mock -ModuleName PureStorageFlashBladePowerShell Remove-SSHSession { }
        }

        It 'returns an existing token from "pureadmin list --api-token --expose" without creating a new one' {
            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-SSHCommand {
                [PSCustomObject]@{ ExitStatus = 0; Output = @('Name  API Token  Created  Expires', 'pureuser  T-11111111-2222-3333-4444-555555555555  -  -') }
            } -ParameterFilter { $Command -eq 'pureadmin list --api-token --expose' }

            $token = InModuleScope PureStorageFlashBladePowerShell { Get-PfbApiTokenViaSsh -Endpoint 'fb.test' -Username 'pureuser' -Password (ConvertTo-SecureString 'hunter2' -AsPlainText -Force) }

            $token | Should -Be 'T-11111111-2222-3333-4444-555555555555'
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-SSHCommand -Times 0 -ParameterFilter { $Command -eq 'pureadmin create --api-token' }
        }

        It 'creates a new token when none exists' {
            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-SSHCommand {
                [PSCustomObject]@{ ExitStatus = 0; Output = @('Name  API Token  Created  Expires', 'pureuser  -  -  -') }
            } -ParameterFilter { $Command -eq 'pureadmin list --api-token --expose' }

            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-SSHCommand {
                [PSCustomObject]@{ ExitStatus = 0; Output = @('Name  API Token  Created  Expires', 'pureuser  T-99999999-8888-7777-6666-555555555555  -  -') }
            } -ParameterFilter { $Command -eq 'pureadmin create --api-token' }

            $token = InModuleScope PureStorageFlashBladePowerShell { Get-PfbApiTokenViaSsh -Endpoint 'fb.test' -Username 'pureuser' -Password (ConvertTo-SecureString 'hunter2' -AsPlainText -Force) }

            $token | Should -Be 'T-99999999-8888-7777-6666-555555555555'
        }

        It 'always cleans up the SSH session, even when token creation fails' {
            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-SSHCommand {
                [PSCustomObject]@{ ExitStatus = 0; Output = @() }
            } -ParameterFilter { $Command -eq 'pureadmin list --api-token --expose' }
            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-SSHCommand {
                [PSCustomObject]@{ ExitStatus = 1; Output = @(); Error = @('permission denied') }
            } -ParameterFilter { $Command -eq 'pureadmin create --api-token' }

            { InModuleScope PureStorageFlashBladePowerShell { Get-PfbApiTokenViaSsh -Endpoint 'fb.test' -Username 'pureuser' -Password (ConvertTo-SecureString 'hunter2' -AsPlainText -Force) } } | Should -Throw

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Remove-SSHSession -Times 1 -Exactly
        }
    }

    Context 'SSH connection itself fails' {
        It 'throws a clear SSH connection error' {
            Mock -ModuleName PureStorageFlashBladePowerShell Get-Module { [PSCustomObject]@{ Name = 'Posh-SSH' } } -ParameterFilter { $ListAvailable -and $Name -eq 'Posh-SSH' }
            Mock -ModuleName PureStorageFlashBladePowerShell Import-Module { } -ParameterFilter { $Name -eq 'Posh-SSH' }
            Mock -ModuleName PureStorageFlashBladePowerShell New-SSHSession { throw 'connection timed out' }

            { InModuleScope PureStorageFlashBladePowerShell { Get-PfbApiTokenViaSsh -Endpoint 'fb.test' -Username 'pureuser' -Password (ConvertTo-SecureString 'hunter2' -AsPlainText -Force) } } |
                Should -Throw -ExpectedMessage "*SSH connection to FlashBlade 'fb.test' failed*"
        }
    }
}
