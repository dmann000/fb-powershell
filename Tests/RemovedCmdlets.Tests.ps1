#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:moduleRootPath = $moduleRoot
    $script:manifestPath   = $manifest
}

Describe 'Broken/duplicate policy cmdlets are removed' {
    It 'no longer exports <Name>' -ForEach @(
        @{ Name = 'New-PfbFileSystemSnapshotPolicy' }
        @{ Name = 'New-PfbPolicyMember' }
        @{ Name = 'Remove-PfbPolicyMember' }
        @{ Name = 'Get-PfbPolicyMember' }
    ) {
        (Get-Command -Module PureStorageFlashBladePowerShell -Name $Name -ErrorAction SilentlyContinue) |
            Should -BeNullOrEmpty
    }
}

Describe 'Legacy REST 1.12 /smtp cmdlets are removed (issue #80)' {
    It 'no longer exports <Name>' -ForEach @(
        @{ Name = 'Get-PfbSmtp' }
        @{ Name = 'Update-PfbSmtp' }
    ) {
        (Get-Command -Module PureStorageFlashBladePowerShell -Name $Name -ErrorAction SilentlyContinue) |
            Should -BeNullOrEmpty
    }

    It 'lists <Name> nowhere in FunctionsToExport' -ForEach @(
        @{ Name = 'Get-PfbSmtp' }
        @{ Name = 'Update-PfbSmtp' }
    ) {
        $exported = (Import-PowerShellDataFile -Path $script:manifestPath).FunctionsToExport
        $exported | Should -Not -Contain $Name
    }

    It 'has no source file under Public/ defining <Name>' -ForEach @(
        @{ Name = 'Get-PfbSmtp' }
        @{ Name = 'Update-PfbSmtp' }
    ) {
        $publicRoot = Join-Path $script:moduleRootPath 'Public'
        $hits = Get-ChildItem -Path $publicRoot -Filter '*.ps1' -Recurse |
            Select-String -Pattern "^\s*function\s+$Name\s*\{" -SimpleMatch:$false
        $hits | Should -BeNullOrEmpty
    }
}

Describe 'Replacement cmdlets are exported' {
    It 'exports <Name>' -ForEach @(
        @{ Name = 'New-PfbPolicyFileSystem' }
        @{ Name = 'Remove-PfbPolicyFileSystem' }
        @{ Name = 'Update-PfbSmtpServer' }
    ) {
        (Get-Command -Module PureStorageFlashBladePowerShell -Name $Name -ErrorAction SilentlyContinue) |
            Should -Not -BeNullOrEmpty
    }
}

Describe 'Retained correct cmdlets are untouched' {
    It 'still exports <Name>' -ForEach @(
        @{ Name = 'Remove-PfbFileSystemSnapshotPolicy' }
        @{ Name = 'Get-PfbPolicyFileSystem' }
        @{ Name = 'New-PfbPolicyFileSystemReplicaLink' }
        @{ Name = 'Remove-PfbPolicyFileSystemReplicaLink' }
        @{ Name = 'Get-PfbSmtpServer' }
    ) {
        (Get-Command -Module PureStorageFlashBladePowerShell -Name $Name -ErrorAction SilentlyContinue) |
            Should -Not -BeNullOrEmpty
    }
}
