function Update-PfbTlsPolicy {
    <#
    .SYNOPSIS
        Updates an existing TLS policy on a FlashBlade array.
    .DESCRIPTION
        The Update-PfbTlsPolicy cmdlet modifies attributes of an existing TLS policy on the
        connected Pure Storage FlashBlade. The policy can be identified by name or ID.
    .PARAMETER Name
        The name of the TLS policy to update.
    .PARAMETER Id
        The ID of the TLS policy to update.
    .PARAMETER Attributes
        A hashtable of TLS policy attributes to modify.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbTlsPolicy -Name "tls-strict" -Attributes @{ min_version = "1.3" }

        Updates the minimum TLS version for the specified policy.
    .EXAMPLE
        Update-PfbTlsPolicy -Id "10314f42-020d-7080-8013-000ddt400012" -Attributes @{ min_version = "1.2" }

        Updates the TLS policy by ID.
    .EXAMPLE
        Update-PfbTlsPolicy -Name "tls-strict" -Attributes @{ min_version = "1.3" } -WhatIf

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
        if ($PSCmdlet.ShouldProcess($target, 'Update TLS policy')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'tls-policies' -Body $Attributes -QueryParams $queryParams
        }
    }
}
