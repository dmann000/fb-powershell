function Remove-PfbFleet {
    <#
    .SYNOPSIS
        Removes a fleet from a FlashBlade array.
    .DESCRIPTION
        The Remove-PfbFleet cmdlet deletes a fleet from the connected Pure Storage FlashBlade.
        The fleet can be identified by name or ID. This cmdlet has a high confirm impact and
        will prompt for confirmation by default. Supports pipeline input.
    .PARAMETER Name
        The name of the fleet to remove. Accepts pipeline input.
    .PARAMETER Id
        The ID of the fleet to remove.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbFleet -Name "fleet-old"

        Removes the fleet named "fleet-old" after prompting for confirmation.
    .EXAMPLE
        Remove-PfbFleet -Name "fleet-test" -Confirm:$false

        Removes the fleet named "fleet-test" without prompting.
    .EXAMPLE
        Get-PfbFleet -Filter "name='temp-*'" | Remove-PfbFleet

        Removes all fleets matching the filter via pipeline input.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)] [string]$Name,
        [Parameter(ParameterSetName = 'ById', Mandatory)] [string]$Id,
        [Parameter()] [PSCustomObject]$Array
    )
    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $target = if ($Name) { $Name } else { $Id }
        $queryParams = @{}
        if ($Name) { $queryParams['names'] = $Name }
        if ($Id) { $queryParams['ids'] = $Id }
        if ($PSCmdlet.ShouldProcess($target, 'Remove fleet')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'fleets' -QueryParams $queryParams
        }
    }
}
