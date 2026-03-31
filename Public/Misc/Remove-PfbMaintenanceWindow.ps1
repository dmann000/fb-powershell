function Remove-PfbMaintenanceWindow {
    <#
    .SYNOPSIS
        Removes a maintenance window from a FlashBlade array.
    .DESCRIPTION
        The Remove-PfbMaintenanceWindow cmdlet deletes a maintenance window from the connected
        Pure Storage FlashBlade. The window can be identified by name or ID.
    .PARAMETER Name
        The name of the maintenance window to remove. Accepts pipeline input.
    .PARAMETER Id
        The ID of the maintenance window to remove.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbMaintenanceWindow -Name "maint-old"

        Removes the maintenance window after prompting for confirmation.
    .EXAMPLE
        Remove-PfbMaintenanceWindow -Name "maint-test" -Confirm:$false

        Removes the maintenance window without prompting.
    .EXAMPLE
        Remove-PfbMaintenanceWindow -Id "10314f42-020d-7080-8013-000ddt400012"

        Removes the maintenance window by ID.
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
        if ($PSCmdlet.ShouldProcess($target, 'Remove maintenance window')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'maintenance-windows' -QueryParams $queryParams
        }
    }
}
