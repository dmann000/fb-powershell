function New-PfbFleetKey {
    <#
    .SYNOPSIS
        Creates a new fleet key on a FlashBlade array.
    .DESCRIPTION
        The New-PfbFleetKey cmdlet generates a new fleet key on the connected Pure Storage
        FlashBlade. Fleet keys are used to authenticate new members joining a fleet.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbFleetKey

        Generates a new fleet key. The key is only displayed at creation time and cannot be
        retrieved afterward. Save it immediately for use in fleet member enrollment.
    .EXAMPLE
        $key = New-PfbFleetKey
        Write-Host "Fleet key: $($key.fleet_key)"

        Creates a fleet key and captures the value for enrollment.
    .EXAMPLE
        New-PfbFleetKey -WhatIf

        Shows what would happen without actually creating the fleet key.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter()] [PSCustomObject]$Array
    )
    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        if ($PSCmdlet.ShouldProcess('FlashBlade', 'Create fleet key (invalidates previous keys)')) {
            Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'fleets/fleet-key' -Body @{}
        }
    }
}
