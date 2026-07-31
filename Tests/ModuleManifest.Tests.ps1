#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

Describe 'Module manifest FunctionsToExport completeness' {

    BeforeAll {
        $moduleRoot = Split-Path -Parent $PSScriptRoot
        $manifestPath = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
        $manifest = Import-PowerShellDataFile -Path $manifestPath
        $publicFiles = Get-ChildItem -Path (Join-Path $moduleRoot 'Public') -Filter '*.ps1' -Recurse
        $script:publicNames = $publicFiles.BaseName
        $script:exported = $manifest.FunctionsToExport
    }

    It 'exports every cmdlet defined under Public/' {
        $missing = $publicNames | Where-Object { $_ -notin $exported }
        $missing | Should -BeNullOrEmpty -Because "these Public/ cmdlets are missing from FunctionsToExport: $($missing -join ', ')"
    }

    It 'does not export a name with no backing Public/ file' {
        $stale = $exported | Where-Object { $_ -notin $publicNames }
        $stale | Should -BeNullOrEmpty -Because "these FunctionsToExport entries have no backing Public/ file: $($stale -join ', ')"
    }

    It 'does not export any name more than once' {
        $dupes = $exported | Group-Object | Where-Object Count -gt 1 | Select-Object -ExpandProperty Name
        $dupes | Should -BeNullOrEmpty -Because "duplicate FunctionsToExport entries: $($dupes -join ', ')"
    }

    It 'includes all 19 new user-group-quota-policy cmdlets' {
        $expected = @(
            'Get-PfbUserGroupQuotaPolicy', 'New-PfbUserGroupQuotaPolicy', 'Update-PfbUserGroupQuotaPolicy', 'Remove-PfbUserGroupQuotaPolicy',
            'Get-PfbUserGroupQuotaPolicyRule', 'New-PfbUserGroupQuotaPolicyRule', 'Update-PfbUserGroupQuotaPolicyRule', 'Remove-PfbUserGroupQuotaPolicyRule',
            'Get-PfbUserGroupQuotaPolicyFileSystem', 'New-PfbUserGroupQuotaPolicyFileSystem', 'Remove-PfbUserGroupQuotaPolicyFileSystem',
            'Get-PfbUserGroupQuotaPolicyMember',
            'Get-PfbFileSystemUserGroupQuotaPolicy', 'New-PfbFileSystemUserGroupQuotaPolicy', 'Remove-PfbFileSystemUserGroupQuotaPolicy',
            'Get-PfbFileSystemUserQuota', 'Get-PfbFileSystemGroupQuota', 'Get-PfbFileSystemUser', 'Get-PfbFileSystemGroup'
        )
        $missing = $expected | Where-Object { $_ -notin $exported }
        $missing | Should -BeNullOrEmpty -Because "expected new cmdlets missing from FunctionsToExport: $($missing -join ', ')"
    }
}
