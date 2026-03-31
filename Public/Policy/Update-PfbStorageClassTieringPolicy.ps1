function Update-PfbStorageClassTieringPolicy {
    <#
    .SYNOPSIS
        Updates an existing storage class tiering policy on a FlashBlade array.
    .DESCRIPTION
        The Update-PfbStorageClassTieringPolicy cmdlet modifies attributes of an existing
        storage class tiering policy on the connected Pure Storage FlashBlade.
    .PARAMETER Name
        The name of the tiering policy to update.
    .PARAMETER Id
        The ID of the tiering policy to update.
    .PARAMETER Attributes
        A hashtable of tiering policy attributes to modify.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbStorageClassTieringPolicy -Name "tier-to-archive" -Attributes @{ enabled = $false }

        Disables the tiering policy.
    .EXAMPLE
        Update-PfbStorageClassTieringPolicy -Id "10314f42-020d-7080-8013-000ddt400012" -Attributes @{ cooldown_period = 172800000 }

        Updates the cooldown period by ID.
    .EXAMPLE
        Update-PfbStorageClassTieringPolicy -Name "tier-to-archive" -Attributes @{} -WhatIf

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
        if ($PSCmdlet.ShouldProcess($target, 'Update storage class tiering policy')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'storage-class-tiering-policies' -Body $Attributes -QueryParams $queryParams
        }
    }
}
