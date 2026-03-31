function Update-PfbWormPolicy {
    <#
    .SYNOPSIS
        Updates an existing WORM data policy on a FlashBlade array.
    .DESCRIPTION
        The Update-PfbWormPolicy cmdlet modifies attributes of an existing WORM data policy
        on the connected Pure Storage FlashBlade. The policy can be identified by name or ID.
    .PARAMETER Name
        The name of the WORM policy to update.
    .PARAMETER Id
        The ID of the WORM policy to update.
    .PARAMETER Attributes
        A hashtable of WORM policy attributes to modify.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbWormPolicy -Name "worm-compliance" -Attributes @{ min_retention = "P90D" }

        Updates the minimum retention period for the WORM policy.
    .EXAMPLE
        Update-PfbWormPolicy -Id "10314f42-020d-7080-8013-000ddt400012" -Attributes @{ enabled = $true }

        Enables the WORM policy by ID.
    .EXAMPLE
        Update-PfbWormPolicy -Name "worm-compliance" -Attributes @{} -WhatIf

        Shows what would happen without actually updating the policy.
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
        if ($PSCmdlet.ShouldProcess($target, 'Update WORM data policy')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'worm-data-policies' -Body $Attributes -QueryParams $queryParams
        }
    }
}
