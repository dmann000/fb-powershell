#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Isolation and behavioural self-tests for tools/lib/PfbSelectorProbeHarness.ps1.
.DESCRIPTION
    The isolation Describe is safety-critical, not hygiene: the harness mutates the shipped
    module's function table, and its silent failure mode is a real network call. On a
    Remove-Pfb* probe with a real array in scope that is a live DELETE.
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $script:repoRoot 'tools/lib/PfbSelectorProbeHarness.ps1')
    $script:manifest = Join-Path $script:repoRoot 'PureStorageFlashBladePowerShell.psd1'
    $script:module = Initialize-PfbSelectorHarness -ManifestPath $script:manifest
}

Describe 'Harness isolation (fail-closed)' {

    It 'returns a module with the shim verified live' {
        $script:module | Should -Not -BeNullOrEmpty

        $resolved = & $script:module { (Get-Command Invoke-PfbApiRequest).Definition }
        $resolved | Should -Match 'PfbSelectorProbeCapture'
    }

    It 'the shim captures instead of dialling' {
        Clear-PfbSelectorCapture -Module $script:module

        $probe = [PSCustomObject]@{
            id     = 'PROBE-id'
            status = 'PROBE-status'
            remote = [PSCustomObject]@{ id = 'PROBE-remote-id'; name = 'PROBE-remote-name' }
        }
        $result = Invoke-PfbSelectorProbe -Module $script:module -Cmdlet 'Get-PfbArrayConnectionPath' -ProbeObject $probe

        $result.Error | Should -BeNullOrEmpty
        @($result.Calls).Count | Should -Be 1
        $result.Calls[0].Endpoint | Should -Be 'array-connections/path'
    }
}

Describe 'Harness behavioural self-test' {

    It 'reproduces the documented #64 result: a connection object binds -Id and emits ids' {
        # Pins Tests/Get-PfbArrayConnectionPath.Tests.ps1:107-119 through the harness.
        $probe = [PSCustomObject]@{
            id     = 'PROBE-id'
            status = 'PROBE-status'
            remote = [PSCustomObject]@{ id = 'PROBE-remote-id'; name = 'PROBE-remote-name' }
        }
        $result = Invoke-PfbSelectorProbe -Module $script:module -Cmdlet 'Get-PfbArrayConnectionPath' -ProbeObject $probe

        $result.Calls[0].QueryParams['ids'] | Should -Be 'PROBE-id'
        $result.Calls[0].QueryParams.ContainsKey('remote_names') | Should -BeFalse
    }

    It 'reproduces the #64 guard firing on an object with no id and no name' {
        $probe = [PSCustomObject]@{ status = 'PROBE-status'; type = 'PROBE-type' }
        $result = Invoke-PfbSelectorProbe -Module $script:module -Cmdlet 'Get-PfbArrayConnectionPath' -ProbeObject $probe

        $result.Error | Should -Match 'stringified object'
        @($result.Calls).Count | Should -Be 0
    }

    It 'reproduces the healthy case: a file system binds by name' {
        $probe = [PSCustomObject]@{ id = 'PROBE-id'; name = 'PROBE-name' }
        $result = Invoke-PfbSelectorProbe -Module $script:module -Cmdlet 'Get-PfbFileSystem' -ProbeObject $probe

        $result.Error | Should -BeNullOrEmpty
        @($result.Calls).Count | Should -Be 1
    }
}
