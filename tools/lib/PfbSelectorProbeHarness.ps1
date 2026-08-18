#Requires -Version 7.0
<#
.SYNOPSIS
    Fail-closed binding harness for the issue #90 pipeline-selector audit.
.DESCRIPTION
    Imports the shipped module and replaces Invoke-PfbApiRequest and Assert-PfbConnection
    INSIDE MODULE SCOPE, so a probe records what would have gone on the wire and never dials.

    SAFETY -- the shadowing has a silent failure mode. Declaring the replacement as
    `& $module { function Invoke-PfbApiRequest {...} }` defines it in the SCRIPT BLOCK's scope,
    which is discarded on exit; the module keeps calling the real function and opens a socket.
    Measured during design: a probe of Get-PfbArrayConnectionPath reached
    "No such host is known. (fb.example.test:443)". With a real array object in scope the same
    fall-through on a Remove-Pfb* probe is a live DELETE.

    Therefore: bind with Set-Item function:script:, and VERIFY before returning. A harness that
    cannot prove its own isolation produces no output.

    PowerShell 7 only, like the rest of tools/ -- see tools/lib/PfbPipelineSelectorTools.ps1.
    The module this harness IMPORTS still supports Windows PowerShell 5.1; the harness itself
    does not need to.
#>

$script:PfbHarnessFakeArray = [PSCustomObject]@{
    Endpoint   = 'probe.invalid'
    ApiVersion = '2.28'
    AuthToken  = 'probe-token'
}

function Initialize-PfbSelectorHarness {
    <#
    .SYNOPSIS
        Imports the module, installs the capture shim, and proves it is live.
    .OUTPUTS
        [PSModuleInfo] -- throws if isolation cannot be verified.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ManifestPath
    )

    $module = Import-Module -Name $ManifestPath -Force -PassThru -ErrorAction Stop

    & $module {
        $script:PfbSelectorProbeCapture = [System.Collections.Generic.List[object]]::new()

        Set-Item -Path 'function:script:Invoke-PfbApiRequest' -Value {
            param(
                $Array, $Method, $Endpoint, $QueryParams, $Body,
                [switch]$AutoPaginate, $ApiVersion
            )
            # The capture list's name is referenced here so the verification below can find
            # it by inspecting the resolved function's definition text.
            $script:PfbSelectorProbeCapture.Add([PSCustomObject]@{
                    Method      = $Method
                    Endpoint    = $Endpoint
                    QueryParams = $QueryParams
                    Body        = $Body
                })
        }

        # Carries its own marker for the same reason the capture list does: the check below is
        # positive-match, so a reworded message in the REAL Assert-PfbConnection cannot make it
        # pass vacuously.
        Set-Item -Path 'function:script:Assert-PfbConnection' -Value {
            param($Array)
            $null = 'PfbSelectorProbeCaptureAssert'
        }
    }

    $definition = & $module { (Get-Command Invoke-PfbApiRequest).Definition }
    if ($definition -notmatch 'PfbSelectorProbeCapture') {
        throw 'HARNESS ISOLATION FAILED: Invoke-PfbApiRequest does not resolve to the capture shim. Refusing to probe.'
    }

    $assertDefinition = & $module { (Get-Command Assert-PfbConnection).Definition }
    if ($assertDefinition -notmatch 'PfbSelectorProbeCaptureAssert') {
        throw 'HARNESS ISOLATION FAILED: Assert-PfbConnection does not resolve to the shim. Refusing to probe.'
    }

    return $module
}

function Clear-PfbSelectorCapture {
    <#
    .SYNOPSIS
        Empties the module-scope capture list.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Management.Automation.PSModuleInfo]$Module)
    & $Module { $script:PfbSelectorProbeCapture.Clear() }
}

function Get-PfbSelectorCapture {
    <#
    .SYNOPSIS
        The requests the shim recorded since the last clear.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Management.Automation.PSModuleInfo]$Module)
    return @(& $Module { $script:PfbSelectorProbeCapture.ToArray() })
}

function Test-PfbSelectorParameterSatisfied {
    <#
    .SYNOPSIS
        Is this mandatory parameter already accounted for, without the harness supplying it?
    .DESCRIPTION
        The single definition of "the probe could have bound this". Two callers depend on it and
        they must never disagree: Test-PfbSelectorProbeBindable uses it to decide whether the
        cmdlet would prompt, and New-PfbSelectorFillerArgument uses it to decide what it is
        allowed to fill.

        That agreement is the entire safety argument for fillers. A filler is legitimate only
        because it goes to a parameter the piped object provably could not have bound -- so it
        cannot suppress a pass-2 binding that would otherwise have happened, and cannot redirect
        pass-3 coercion, which targets ValueFromPipeline parameters only. Let the two lists drift
        and a filler could silently manufacture the very defect the audit is measuring.
    .OUTPUTS
        [bool]
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Parameter,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$ProbeProperty,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$SuppliedArgument
    )

    if ($Parameter.Name -in $SuppliedArgument) { return $true }
    if ($Parameter.ValueFromPipeline) { return $true }

    if ($Parameter.ValueFromPipelineByPropertyName) {
        $names = @($Parameter.Name) + @($Parameter.Aliases)
        if (@($names | Where-Object { $_ -in $ProbeProperty }).Count) { return $true }
    }

    return $false
}

function New-PfbSelectorFillerArgument {
    <#
    .SYNOPSIS
        Synthesises throwaway values for the mandatory parameters a probe object cannot supply.
    .DESCRIPTION
        Without this, any cmdlet declaring a mandatory parameter outside the piped object's
        reach is never invoked at all, and its pipeline-bound selectors get no verdict. Measured
        on the first full sweep: 25 (cmdlet, parameter) pairs unmeasured, concentrated in the
        object-store access-policy, quota and *-Rule families -- the same families where the
        confirmed defect clusters, and 21 of them Remove-* or Update-*. A blind spot in exactly
        the worst place is not an acceptable resting state for the audit.

        Fillers go ONLY to parameters Test-PfbSelectorParameterSatisfied reports as unreachable
        by the probe, which is what makes them evidence-neutral -- see that function.

        Values carry a FILLER- prefix rather than the probe's PROBE- prefix, so a filler landing
        on a query key can never be misread as the piped object's property. Get-PfbSelectorOutcome
        recognises only PROBE- sentinels, so a FILLER- value on the parameter's own wire key
        classifies as NoSelector, never as a finding.

        Parameter sets are tried in declaration order and the first fully fillable one wins.
    .OUTPUTS
        [PSCustomObject]@{ Fillable (bool); Argument (hashtable); Reason (string) }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Command,
        [Parameter(Mandatory)][PSCustomObject]$ProbeObject,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$SuppliedArgument
    )

    $probeProperty = @($ProbeObject.PSObject.Properties.Name)
    $blocked = [System.Collections.Generic.List[string]]::new()

    # If ANY set is already satisfiable unaided, supply nothing at all. Filling a parameter that
    # the probe could not bind is safe per-parameter but NOT per-set: making a second set
    # satisfiable can change which set PowerShell selects, and the pipeline parameter may bind
    # differently -- or not at all -- in the set that then wins.
    #
    # Measured, and it is why this check exists: Update-PfbArrayConnection was binding -Id from
    # the piped object. Filling a mandatory parameter belonging to a different set moved the
    # selection to that set, and six rows flipped -- two of them from Bound to Unbindable, a
    # verdict the harness had manufactured rather than observed. A filler is only ever a way to
    # reach a cmdlet that would otherwise be refused outright.
    foreach ($set in $Command.ParameterSets) {
        $unsatisfied = @($set.Parameters | Where-Object { $_.IsMandatory } | Where-Object {
                -not (Test-PfbSelectorParameterSatisfied -Parameter $_ -ProbeProperty $probeProperty `
                        -SuppliedArgument $SuppliedArgument)
            })
        if (-not $unsatisfied.Count) {
            return [PSCustomObject]@{ Fillable = $true; Argument = @{}; Reason = $null }
        }
    }

    foreach ($set in $Command.ParameterSets) {
        $argument = @{}
        $unfillable = [System.Collections.Generic.List[string]]::new()

        foreach ($parameter in @($set.Parameters | Where-Object { $_.IsMandatory })) {
            if (Test-PfbSelectorParameterSatisfied -Parameter $parameter -ProbeProperty $probeProperty `
                    -SuppliedArgument $SuppliedArgument) {
                continue
            }

            $type = $parameter.ParameterType
            $value = switch ($true) {
                { $type -eq [string] } { "FILLER-$($parameter.Name)"; break }
                { $type -eq [string[]] } { , @("FILLER-$($parameter.Name)"); break }
                { $type -in @([int], [long], [short]) } { 1; break }
                { $type -eq [hashtable] } { @{}; break }
                default { $null }
            }

            if ($null -eq $value) {
                $unfillable.Add("$($parameter.Name) ($($type.Name))")
                continue
            }
            $argument[$parameter.Name] = $value
        }

        if (-not $unfillable.Count) {
            return [PSCustomObject]@{ Fillable = $true; Argument = $argument; Reason = $null }
        }
        $blocked.Add("$($set.Name): $($unfillable -join ', ')")
    }

    return [PSCustomObject]@{
        Fillable = $false
        Argument = @{}
        Reason   = "no parameter set is fillable -- $($blocked -join ' | ')"
    }
}

function Test-PfbSelectorProbeBindable {
    <#
    .SYNOPSIS
        Can -Command run to completion without PROMPTING for a mandatory parameter?
    .DESCRIPTION
        SAFETY, not tidiness. A [Parameter(Mandatory)] parameter that goes unbound throws a
        ParameterBindingException in a non-interactive host but PROMPTS AND BLOCKS in a real
        console -- and the prompt renders on the user's desktop while the agent driving the
        sweep sees nothing at all. Measured: Update-PfbSmbShareRule declares one parameter set
        whose mandatory parameters are Name and Attributes; a probe object can never supply
        -Attributes, so the sweep stopped dead on "cmdlet Update-PfbSmbShareRule at command
        pipeline position 1 / Supply values for the following parameters:".

        A parameter set is satisfiable when every one of its mandatory parameters is either
        passed explicitly by the harness, or bindable from the probe object -- by property
        name (name or alias matching a probe property) or by taking the whole object by value.
        If NO set is satisfiable the cmdlet is never invoked at all.
    .OUTPUTS
        [PSCustomObject]@{ Bindable (bool); Reason (string) }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Management.Automation.CommandInfo]$Command,
        [Parameter(Mandatory)][PSCustomObject]$ProbeObject,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$SuppliedArgument
    )

    $probeProperty = @($ProbeObject.PSObject.Properties.Name)
    $unsatisfied = [System.Collections.Generic.List[string]]::new()

    foreach ($set in $Command.ParameterSets) {
        $missing = [System.Collections.Generic.List[string]]::new()

        foreach ($parameter in @($set.Parameters | Where-Object { $_.IsMandatory })) {
            if (Test-PfbSelectorParameterSatisfied -Parameter $parameter -ProbeProperty $probeProperty `
                    -SuppliedArgument $SuppliedArgument) {
                continue
            }
            $missing.Add($parameter.Name)
        }

        if (-not $missing.Count) {
            return [PSCustomObject]@{ Bindable = $true; Reason = $null }
        }
        $unsatisfied.Add("$($set.Name): $($missing -join ', ')")
    }

    return [PSCustomObject]@{
        Bindable = $false
        Reason   = "would prompt for an unbound mandatory parameter -- $($unsatisfied -join ' | ')"
    }
}

function Invoke-PfbSelectorProbe {
    <#
    .SYNOPSIS
        Pipes one probe object into one real cmdlet and returns what reached the shim.
    .DESCRIPTION
        -Confirm:$false is passed to every ShouldProcess cmdlet, because ConfirmImpact = High
        throws under a non-interactive host rather than proceeding.

        A terminating error is CAPTURED, not rethrown: an Assert-Pfb*NotCoerced guard throwing
        is a legitimate outcome (Guarded), as is a parameter-set failure (BindError).

        ErrorKind separates causes the message alone conflates, and is read from the error
        record's type and FullyQualifiedErrorId rather than its text, which is culture-dependent
        and would classify differently on a CI host:

        - 'HarnessRefusal'      -- never invoked; the only genuinely unmeasured outcome.
        - 'InputObjectNotBound' -- PowerShell refused to bind THIS probe object at all. It is a
                                   per-probe observation, NOT a structural immunity: binding has FOUR
                                   passes, including ByPropertyName WITH coercion, so an alias matching
                                   an object-valued property can coerce even when ValueFromPipeline is absent.
        - 'ParameterBindingError' -- some other binding failure, e.g. an ambiguous set.
        - 'CmdletError'         -- the cmdlet itself threw before reaching the shim.
    .OUTPUTS
        [PSCustomObject]@{ Calls; Error; ErrorKind; FillerArgument }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Management.Automation.PSModuleInfo]$Module,
        [Parameter(Mandatory)][string]$Cmdlet,
        [Parameter(Mandatory)][PSCustomObject]$ProbeObject,
        [hashtable]$ExtraArgument = @{}
    )

    Clear-PfbSelectorCapture -Module $Module

    $arguments = @{ Array = $script:PfbHarnessFakeArray } + $ExtraArgument
    $command = Get-Command -Name $Cmdlet -Module $Module.Name -ErrorAction Stop
    if ($command.Parameters.ContainsKey('Confirm')) { $arguments['Confirm'] = $false }

    # Synthesise values for the mandatory parameters the probe cannot reach, so the cmdlet runs
    # far enough to build a request instead of being refused outright. Fillers only ever target
    # parameters the piped object provably could not have bound, which is why they do not
    # disturb the binding under test -- see New-PfbSelectorFillerArgument.
    $filler = New-PfbSelectorFillerArgument -Command $command -ProbeObject $ProbeObject `
        -SuppliedArgument @($arguments.Keys)
    foreach ($key in $filler.Argument.Keys) { $arguments[$key] = $filler.Argument[$key] }

    # The guard remains the final authority, re-run against the filled argument list. In a real
    # console an unbound mandatory parameter blocks on a prompt rendered to the user's desktop,
    # which the sweep cannot see and cannot answer.
    $bindable = Test-PfbSelectorProbeBindable -Command $command -ProbeObject $ProbeObject `
        -SuppliedArgument @($arguments.Keys)
    if (-not $bindable.Bindable) {
        return [PSCustomObject]@{
            Calls          = @()
            Error          = $bindable.Reason
            ErrorKind      = 'HarnessRefusal'
            FillerArgument = @{}
        }
    }

    $errorText = $null
    $errorKind = $null
    try {
        $ProbeObject | & $command @arguments -ErrorAction Stop | Out-Null
    }
    catch {
        $errorText = $_.Exception.Message
        $errorKind = if ($_.Exception -is [System.Management.Automation.ParameterBindingException]) {
            if ([string]$_.FullyQualifiedErrorId -like 'InputObjectNotBound*') { 'InputObjectNotBound' }
            else { 'ParameterBindingError' }
        }
        else { 'CmdletError' }
    }

    return [PSCustomObject]@{
        Calls          = Get-PfbSelectorCapture -Module $Module
        Error          = $errorText
        ErrorKind      = $errorKind
        FillerArgument = $filler.Argument
    }
}
