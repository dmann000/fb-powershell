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
