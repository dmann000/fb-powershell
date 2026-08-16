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

    It 'satisfies every mandatory parameter it does not refuse outright' {
        # Update-PfbSmbShareRule declares one parameter set whose mandatory parameters are Name
        # and Attributes. A probe object can never supply -Attributes, so invoking it blocked
        # the sweep on "Supply values for the following parameters:" -- a prompt rendered on
        # the user's desktop that the sweep can neither see nor answer.
        #
        # The harness now fills -Attributes rather than refusing the cmdlet, which is what gives
        # its selectors a verdict. The safety property is therefore no longer "refuse this
        # cmdlet" but the weaker and more general one asserted here: after fillers are applied,
        # every cmdlet is EITHER fully satisfiable OR explicitly refused. There is no third
        # state in which one is invoked with a mandatory parameter still unbound.
        $probe = [PSCustomObject]@{ id = 'PROBE-id'; name = 'PROBE-name' }
        $supplied = @('Array', 'Confirm')
        $unsafe = [System.Collections.Generic.List[string]]::new()

        foreach ($command in @(Get-Command -Module $script:module.Name -CommandType Function)) {
            $filler = New-PfbSelectorFillerArgument -Command $command -ProbeObject $probe -SuppliedArgument $supplied
            $bindable = Test-PfbSelectorProbeBindable -Command $command -ProbeObject $probe `
                -SuppliedArgument (@($supplied) + @($filler.Argument.Keys))

            if ($filler.Fillable -and -not $bindable.Bindable) { $unsafe.Add($command.Name) }
        }

        $unsafe -join '; ' | Should -BeNullOrEmpty
    }

    It 'fills the mandatory parameter that first caused the prompt' {
        $probe = [PSCustomObject]@{ id = 'PROBE-id'; name = 'PROBE-name' }
        $command = Get-Command -Module $script:module.Name -Name 'Update-PfbSmbShareRule'
        $filler = New-PfbSelectorFillerArgument -Command $command -ProbeObject $probe `
            -SuppliedArgument @('Array', 'Confirm')

        $filler.Fillable | Should -BeTrue
        $filler.Argument.ContainsKey('Attributes') | Should -BeTrue
        # -Name is the parameter under test and is ValueFromPipeline; filling it would destroy
        # the measurement by binding explicitly what the pipeline was supposed to bind.
        $filler.Argument.ContainsKey('Name') | Should -BeFalse
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

Describe 'Filler arguments for unsatisfiable mandatory parameters' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {

    It 'never fills a parameter the piped object could itself have bound' {
        # THE safety property of the whole mechanism, asserted over the entire module rather
        # than a sample. A filler is only legitimate because it goes to parameters the probe
        # provably could not bind: fill one the pipeline would have bound and you suppress a
        # real pass-2 binding, which can make pass 3 fire and manufacture a false Coerced.
        $probe = [PSCustomObject]@{ id = 'PROBE-id'; name = 'PROBE-name' }
        $probeProperty = @($probe.PSObject.Properties.Name)
        $violations = [System.Collections.Generic.List[string]]::new()

        foreach ($command in @(Get-Command -Module $script:module.Name -CommandType Function)) {
            $filler = New-PfbSelectorFillerArgument -Command $command -ProbeObject $probe `
                -SuppliedArgument @('Array', 'Confirm')
            if (-not $filler.Fillable) { continue }

            foreach ($key in $filler.Argument.Keys) {
                $parameter = $command.Parameters[$key]
                $attributes = @($parameter.Attributes |
                        Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] })

                if (@($attributes | Where-Object { $_.ValueFromPipeline }).Count) {
                    $violations.Add("$($command.Name)/$key is ValueFromPipeline")
                }
                if (@($attributes | Where-Object { $_.ValueFromPipelineByPropertyName }).Count) {
                    $names = @($key) + @($parameter.Aliases)
                    if (@($names | Where-Object { $_ -in $probeProperty }).Count) {
                        $violations.Add("$($command.Name)/$key binds a probe property")
                    }
                }
            }
        }

        $violations -join '; ' | Should -BeNullOrEmpty
    }

    It 'supplies nothing when the cmdlet is already invokable unaided' {
        # Perturbation caught by diffing filler-on against filler-off across all 1179 rows.
        # Update-PfbArrayConnection bound -Id from the piped object; filling a mandatory
        # parameter of a DIFFERENT set made that set satisfiable, PowerShell selected it, and
        # six rows flipped -- two from Bound to Unbindable. Per-parameter safety is not enough
        # on its own, because parameter-set selection is a whole-command decision.
        $probe = [PSCustomObject]@{ id = 'PROBE-id'; name = 'PROBE-name' }
        $command = Get-Command -Module $script:module.Name -Name 'Update-PfbArrayConnection'
        $filler = New-PfbSelectorFillerArgument -Command $command -ProbeObject $probe `
            -SuppliedArgument @('Array', 'Confirm')

        $filler.Fillable | Should -BeTrue
        $filler.Argument.Count | Should -Be 0
    }

    It 'tags every filler value so it can never be read as probe evidence' {
        $probe = [PSCustomObject]@{ id = 'PROBE-id'; name = 'PROBE-name' }
        $command = Get-Command -Module $script:module.Name -Name 'Remove-PfbQuotaUser'
        $filler = New-PfbSelectorFillerArgument -Command $command -ProbeObject $probe `
            -SuppliedArgument @('Array', 'Confirm')

        $filler.Fillable | Should -BeTrue
        $filler.Argument['FileSystemName'] | Should -Be 'FILLER-FileSystemName'
    }

    It 'refuses a mandatory parameter whose type it cannot synthesise, naming the type' {
        $probe = [PSCustomObject]@{ id = 'PROBE-id' }
        $command = [PSCustomObject]@{
            Name          = 'Test-Unfillable'
            ParameterSets = @(
                [PSCustomObject]@{
                    Name       = '__AllParameterSets'
                    Parameters = @(
                        [PSCustomObject]@{
                            Name                            = 'Credential'
                            IsMandatory                     = $true
                            ParameterType                   = [System.Management.Automation.PSCredential]
                            ValueFromPipeline               = $false
                            ValueFromPipelineByPropertyName = $false
                            Aliases                         = @()
                        })
                })
        }
        $filler = New-PfbSelectorFillerArgument -Command $command -ProbeObject $probe -SuppliedArgument @()

        $filler.Fillable | Should -BeFalse
        $filler.Reason | Should -Match 'PSCredential'
    }

    It 'invokes Update-PfbSmbShareRule instead of refusing it, and still never prompts' {
        # The cmdlet that stopped the first sweep dead on a console prompt. It must now run --
        # -Attributes is satisfiable with an empty hashtable -- and must still not prompt.
        $probe = [PSCustomObject]@{ name = 'PROBE-name'; id = 'PROBE-id' }
        $result = Invoke-PfbSelectorProbe -Module $script:module -Cmdlet 'Update-PfbSmbShareRule' -ProbeObject $probe

        # Assert the property EXISTS before asserting its value: a missing ErrorKind is $null,
        # which passes -Not -Be 'HarnessRefusal' vacuously.
        $result.PSObject.Properties.Name | Should -Contain 'ErrorKind'
        $result.ErrorKind | Should -Not -Be 'HarnessRefusal'
        if ($result.Error) { $result.Error | Should -Not -Match 'Supply values for the following' }
    }
}

Describe 'Probe error classification' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {

    BeforeAll {
        if ($PSVersionTable.PSVersion.Major -ge 7) {
            . (Join-Path $script:repoRoot 'tools/lib/PfbPipelineSelectorTools.ps1')
        }
    }

    It 'reports a refusal by PowerShell to bind at all as Unbindable, not a harness failure' {
        # ValueFromPipelineByPropertyName-only parameters cannot take pass-3 coercion, which is
        # ByValue. PowerShell throwing InputObjectNotBound IS the verdict: this pair is safe.
        $probe = [PSCustomObject]@{ zzz = 'PROBE-zzz' }
        $result = Invoke-PfbSelectorProbe -Module $script:module `
            -Cmdlet 'Get-PfbObjectStoreRoleAccessPolicy' -ProbeObject $probe
        $result.ErrorKind | Should -Be 'InputObjectNotBound'

        $outcome = Get-PfbSelectorOutcome -ProbeResult $result -Parameter 'RoleName' `
            -WireName 'role_names' -ProbeObject $probe
        $outcome.Outcome | Should -Be 'Unbindable'
    }

    It 'reports a cmdlet throwing before the shim as CmdletError' {
        $probe = [PSCustomObject]@{ zzz = 'PROBE-zzz' }
        $result = Invoke-PfbSelectorProbe -Module $script:module -Cmdlet 'Set-PfbContext' -ProbeObject $probe
        $result.ErrorKind | Should -Be 'CmdletError'

        $outcome = Get-PfbSelectorOutcome -ProbeResult $result -Parameter 'Context' `
            -WireName 'context_names' -ProbeObject $probe
        $outcome.Outcome | Should -Be 'CmdletError'
    }
}
