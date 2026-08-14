#Requires -Version 5.1
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

        Set-Item -Path 'function:script:Assert-PfbConnection' -Value { param($Array) }
    }

    $definition = & $module { (Get-Command Invoke-PfbApiRequest).Definition }
    if ($definition -notmatch 'PfbSelectorProbeCapture') {
        throw 'HARNESS ISOLATION FAILED: Invoke-PfbApiRequest does not resolve to the capture shim. Refusing to probe.'
    }

    $assertDefinition = & $module { (Get-Command Assert-PfbConnection).Definition }
    if ($assertDefinition -match 'Not connected') {
        throw 'HARNESS ISOLATION FAILED: Assert-PfbConnection was not shadowed. Refusing to probe.'
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
            if ($parameter.Name -in $SuppliedArgument) { continue }
            if ($parameter.ValueFromPipeline) { continue }

            if ($parameter.ValueFromPipelineByPropertyName) {
                $names = @($parameter.Name) + @($parameter.Aliases)
                if (@($names | Where-Object { $_ -in $probeProperty }).Count) { continue }
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
    .OUTPUTS
        [PSCustomObject]@{ Calls; Error }
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

    # Refuse to invoke anything that would prompt. In a real console an unbound mandatory
    # parameter blocks on a prompt rendered to the user's desktop, which the sweep cannot see
    # and cannot answer. Reported as a BindError, which is a triage outcome, not a finding.
    $bindable = Test-PfbSelectorProbeBindable -Command $command -ProbeObject $ProbeObject `
        -SuppliedArgument @($arguments.Keys)
    if (-not $bindable.Bindable) {
        return [PSCustomObject]@{ Calls = @(); Error = $bindable.Reason }
    }

    $errorText = $null
    try {
        $ProbeObject | & $command @arguments -ErrorAction Stop | Out-Null
    }
    catch {
        $errorText = $_.Exception.Message
    }

    return [PSCustomObject]@{
        Calls = Get-PfbSelectorCapture -Module $Module
        Error = $errorText
    }
}
