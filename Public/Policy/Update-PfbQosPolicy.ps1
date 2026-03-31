function Update-PfbQosPolicy {
    <#
    .SYNOPSIS
        Updates an existing QoS policy on a FlashBlade array.
    .DESCRIPTION
        The Update-PfbQosPolicy cmdlet modifies attributes of an existing QoS policy on the
        connected Pure Storage FlashBlade. The policy can be identified by name or ID.
    .PARAMETER Name
        The name of the QoS policy to update.
    .PARAMETER Id
        The ID of the QoS policy to update.
    .PARAMETER Attributes
        A hashtable of QoS policy attributes to modify.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbQosPolicy -Name "qos-gold" -Attributes @{ max_total_bytes_per_sec = 2147483648 }

        Updates the max bandwidth for the specified QoS policy to 2 GB/s.
    .EXAMPLE
        Update-PfbQosPolicy -Id "10314f42-020d-7080-8013-000ddt400012" -Attributes @{ max_total_ops_per_sec = 20000 }

        Updates the max IOPS for the QoS policy by ID.
    .EXAMPLE
        Update-PfbQosPolicy -Name "qos-gold" -Attributes @{} -WhatIf

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
        if ($PSCmdlet.ShouldProcess($target, 'Update QoS policy')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'qos-policies' -Body $Attributes -QueryParams $queryParams
        }
    }
}
