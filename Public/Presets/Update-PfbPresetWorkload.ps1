function Update-PfbPresetWorkload {
    <#
    .SYNOPSIS
        Renames a workload preset on the FlashBlade (PATCH).
    .DESCRIPTION
        The PresetWorkloadPatch schema only supports rename. To replace the preset
        definition, use Set-PfbPresetWorkload.
    .PARAMETER Name
        Current preset name.
    .PARAMETER Id
        Current preset ID.
    .PARAMETER NewName
        New name for the preset.
    .PARAMETER Array
        FlashBlade connection.
    .EXAMPLE
        Update-PfbPresetWorkload -Name 'analytics-template' -NewName 'analytics-template-v2'
    .NOTES
        <!-- PfbContext: generated from Data/PfbCapabilityMap.json contextScope. Do not edit. -->
        Context requirement (PATCH /presets/workload): this cmdlet targets a fleet-scoped resource
        and requires a bare fleet context. Set one with
        Set-PfbContext -Context <fleet> -Kind Fleet, or scope a single call with
        Invoke-PfbInContext. Get the fleet name from Get-PfbFleet.
        <!-- /PfbContext -->
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
        [string]$NewName,

        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    if ($Name) { $queryParams['names'] = $Name }
    if ($Id)   { $queryParams['ids']   = $Id }

    $body = @{ name = $NewName }

    $target = if ($Name) { $Name } else { $Id }
    if ($PSCmdlet.ShouldProcess($target, "Rename workload preset to '$NewName'")) {
        Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'presets/workload' -QueryParams $queryParams -Body $body
    }
}
