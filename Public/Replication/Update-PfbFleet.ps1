function Update-PfbFleet {
    <#
    .SYNOPSIS
        Updates an existing fleet on a FlashBlade array.
    .DESCRIPTION
        The Update-PfbFleet cmdlet modifies attributes of an existing fleet on the connected
        Pure Storage FlashBlade. The fleet can be identified by name or ID. Supports pipeline
        input and ShouldProcess for confirmation prompts.
    .PARAMETER Name
        The name of the fleet to update. Accepts pipeline input by property name.
    .PARAMETER Id
        The ID of the fleet to update.
    .PARAMETER Attributes
        A hashtable of fleet attributes to modify.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbFleet -Name "fleet-prod" -Attributes @{ description = "Updated description" }

        Updates the description for the fleet named "fleet-prod".
    .EXAMPLE
        Update-PfbFleet -Id "10314f42-020d-7080-8013-000ddt400012" -Attributes @{ name = "fleet-renamed" }

        Renames the fleet identified by the specified ID.
    .EXAMPLE
        Update-PfbFleet -Name "fleet-prod" -Attributes @{} -WhatIf

        Shows what would happen without actually updating the fleet.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, ValueFromPipelineByPropertyName)] [string]$Name,
        [Parameter(ParameterSetName = 'ById', Mandatory)] [string]$Id,
        [Parameter(Mandatory)] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )
    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $queryParams = @{}
        if ($Name) { $queryParams['names'] = $Name }
        if ($Id) { $queryParams['ids'] = $Id }
        $target = if ($Name) { $Name } else { $Id }
        if ($PSCmdlet.ShouldProcess($target, 'Update fleet')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'fleets' -Body $Attributes -QueryParams $queryParams
        }
    }
}
