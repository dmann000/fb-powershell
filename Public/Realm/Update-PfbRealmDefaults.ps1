function Update-PfbRealmDefaults {
    <#
    .SYNOPSIS
        Updates realm default settings on a FlashBlade array.
    .DESCRIPTION
        The Update-PfbRealmDefaults cmdlet modifies the default settings for a realm on the
        connected Pure Storage FlashBlade.
    .PARAMETER Name
        The name of the realm to update defaults for.
    .PARAMETER Id
        The ID of the realm to update defaults for.
    .PARAMETER Attributes
        A hashtable of realm default attributes to modify.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbRealmDefaults -Name "realm-prod" -Attributes @{ quota_limit = 1099511627776 }

        Updates the default quota limit for the specified realm.
    .EXAMPLE
        Update-PfbRealmDefaults -Id "10314f42-020d-7080-8013-000ddt400012" -Attributes @{}

        Updates realm defaults by ID.
    .EXAMPLE
        Update-PfbRealmDefaults -Name "realm-prod" -Attributes @{} -WhatIf

        Shows what would happen without actually updating the defaults.
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
        if ($PSCmdlet.ShouldProcess($target, 'Update realm defaults')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'realms/defaults' -Body $Attributes -QueryParams $queryParams
        }
    }
}
