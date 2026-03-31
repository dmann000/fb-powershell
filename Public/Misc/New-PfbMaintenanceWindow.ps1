function New-PfbMaintenanceWindow {
    <#
    .SYNOPSIS
        Creates a new maintenance window on a FlashBlade array.
    .DESCRIPTION
        The New-PfbMaintenanceWindow cmdlet creates a new maintenance window on the connected
        Pure Storage FlashBlade. Maintenance windows suppress alerts during planned activities.
    .PARAMETER Attributes
        A hashtable of maintenance window attributes such as timeout.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbMaintenanceWindow -Attributes @{ timeout = 3600000 }

        Creates a 1-hour maintenance window.
    .EXAMPLE
        New-PfbMaintenanceWindow -Attributes @{ timeout = 7200000 }

        Creates a 2-hour maintenance window.
    .EXAMPLE
        New-PfbMaintenanceWindow -Attributes @{} -WhatIf

        Shows what would happen without actually creating the window.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )
    Assert-PfbConnection -Array ([ref]$Array)
    if ($PSCmdlet.ShouldProcess('FlashBlade', 'Create maintenance window')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'maintenance-windows' -Body $Attributes
    }
}
