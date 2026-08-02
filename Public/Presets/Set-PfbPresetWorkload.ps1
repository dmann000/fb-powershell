function Set-PfbPresetWorkload {
    <#
    .SYNOPSIS
        Replaces a workload preset definition on the FlashBlade (PUT).
    .DESCRIPTION
        Full replacement of an existing preset. Pass the complete PresetWorkload body via
        -Attributes. To rename without replacing the body, use Update-PfbPresetWorkload.
    .PARAMETER Name
        Preset name to replace.
    .PARAMETER Id
        Preset ID to replace.
    .PARAMETER Attributes
        Full PresetWorkload body.
    .PARAMETER SkipVerifyDeployable
        Skip verification that the preset is deployable on the FB.
    .PARAMETER Array
        FlashBlade connection.
    .EXAMPLE
        Set-PfbPresetWorkload -Name 'analytics-template' -Attributes $newBody
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByName', Position = 0)]
        [ValidateScript({ Assert-PfbSafeName $_ })]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ById')]
        [ValidateNotNullOrEmpty()]
        [string]$Id,

        [Parameter(Mandatory)]
        [hashtable]$Attributes,

        [Parameter()] [switch]$SkipVerifyDeployable,
        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    if ($Name) { $queryParams['names'] = $Name }
    if ($Id)   { $queryParams['ids']   = $Id }
    if ($SkipVerifyDeployable) { $queryParams['skip_verify_deployable'] = 'true' }

    $target = if ($Name) { $Name } else { $Id }
    if ($PSCmdlet.ShouldProcess($target, 'Replace workload preset (PUT)')) {
        Invoke-PfbApiRequest -Array $Array -Method PUT -Endpoint 'presets/workload' `
            -Body $Attributes -QueryParams $queryParams
    }
}
