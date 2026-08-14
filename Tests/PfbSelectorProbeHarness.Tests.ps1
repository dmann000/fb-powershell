#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Isolation and behavioural self-tests for tools/lib/PfbSelectorProbeHarness.ps1.
.DESCRIPTION
    The isolation Describe is safety-critical, not hygiene: the harness mutates the shipped
    module's function table, and its silent failure mode is a real network call. On a
    Remove-Pfb* probe with a real array in scope that is a live DELETE.

    The harness is #Requires -Version 7.0 (developer/CI tooling), so the Describes are skipped
    on 5.1 and the file-level BeforeAll guards its own body -- a skipped Describe does not
    stop it running, and dot-sourcing a 7-only script on 5.1 kills the whole container. The
    module being imported here still supports 5.1; only the harness does not.
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:manifest = Join-Path $script:repoRoot 'PureStorageFlashBladePowerShell.psd1'

    if ($PSVersionTable.PSVersion.Major -ge 7) {
        . (Join-Path $script:repoRoot 'tools/lib/PfbSelectorProbeHarness.ps1')
        $script:module = Initialize-PfbSelectorHarness -ManifestPath $script:manifest
    }
}

Describe 'Harness isolation (fail-closed)' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {

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

Describe 'Harness never prompts' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {

    It 'refuses to invoke a cmdlet whose mandatory parameters a probe cannot supply' {
        # Update-PfbSmbShareRule declares one parameter set whose mandatory parameters are
        # Name and Attributes. A probe object can never supply -Attributes, so invoking it
        # blocked the sweep on "Supply values for the following parameters:" -- a prompt
        # rendered on the user's desktop that the sweep can neither see nor answer.
        $probe = [PSCustomObject]@{ id = 'PROBE-id'; name = 'PROBE-name' }
        $result = Invoke-PfbSelectorProbe -Module $script:module -Cmdlet 'Update-PfbSmbShareRule' -ProbeObject $probe

        $result.Error | Should -Match 'would prompt for an unbound mandatory parameter'
        $result.Error | Should -Match 'Attributes'
        @($result.Calls).Count | Should -Be 0
    }

    It 'still invokes a cmdlet whose mandatory parameters the probe does supply' {
        $probe = [PSCustomObject]@{ id = 'PROBE-id'; name = 'PROBE-name' }
        $result = Invoke-PfbSelectorProbe -Module $script:module -Cmdlet 'Get-PfbFileSystem' -ProbeObject $probe

        $result.Error | Should -BeNullOrEmpty
        @($result.Calls).Count | Should -Be 1
    }

    It 'reports every pipeline-bound cmdlet as either bindable or explicitly refused' {
        # A sweep-wide guarantee: no cmdlet reaches invocation with an unsatisfiable mandatory
        # parameter, so no probe can ever block on a console prompt.
        . (Join-Path $script:repoRoot 'tools/lib/PfbPipelineSelectorTools.ps1')
        $bound = Get-PfbPipelineBoundParameter -Module $script:module
        $probe = [PSCustomObject]@{ id = 'PROBE-id'; name = 'PROBE-name' }

        $unclassified = @(foreach ($cmdlet in ($bound.Cmdlet | Sort-Object -Unique)) {
                $command = Get-Command -Name $cmdlet -Module $script:module.Name
                $verdict = Test-PfbSelectorProbeBindable -Command $command -ProbeObject $probe `
                    -SuppliedArgument @('Array', 'Confirm')
                if ($null -eq $verdict.Bindable) { $cmdlet }
            })

        $unclassified | Should -BeNullOrEmpty
    }
}

Describe 'Harness behavioural self-test' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {

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
