function Remove-PfbPresetWorkload {
    <#
    .SYNOPSIS
        Removes a workload preset from the FlashBlade.
    .DESCRIPTION
        Deletes a workload preset. Existing workloads instantiated from this preset are not
        affected.
    .PARAMETER Name
        Preset name to remove.
    .PARAMETER Id
        Preset ID to remove.
    .PARAMETER Array
        FlashBlade connection.
    .EXAMPLE
        Remove-PfbPresetWorkload -Name 'analytics-template'
    .NOTES
        <!-- PfbContext: generated from Data/PfbCapabilityMap.json contextScope. Do not edit. -->
        Context requirement (DELETE /presets/workload): this cmdlet targets a fleet-scoped resource
        and requires a bare fleet context. Set one with
        Set-PfbContext -Context <fleet> -Kind Fleet, or scope a single call with
        Invoke-PfbInContext. Get the fleet name from Get-PfbFleet.
        <!-- /PfbContext -->
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByName', Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateScript({ Assert-PfbSafeName $_ })]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ById')]
        [ValidateNotNullOrEmpty()]
        [string]$Id,

        [Parameter()] [PSCustomObject]$Array
    )

    begin { Assert-PfbConnection -Array ([ref]$Array) }

    process {
        $queryParams = @{}
        if ($Name) { $queryParams['names'] = $Name }
        if ($Id)   { $queryParams['ids']   = $Id }

        $target = if ($Name) { $Name } else { $Id }
        if ($PSCmdlet.ShouldProcess($target, 'Remove workload preset')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'presets/workload' -QueryParams $queryParams
        }
    }
}
