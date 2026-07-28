function Update-PfbQosPolicy {
    <#
    .SYNOPSIS
        Updates an existing QoS policy on a FlashBlade array.
    .DESCRIPTION
        The Update-PfbQosPolicy cmdlet modifies attributes of an existing QoS policy on the
        connected Everpure FlashBlade. The policy can be identified by name or ID.

        The individual typed parameters and the raw -Attributes hashtable are mutually
        exclusive: they live in separate parameter sets, so PowerShell rejects a mixed
        invocation at bind time rather than letting -Attributes silently override an
        explicitly supplied value.
    .PARAMETER Name
        The name of the QoS policy to update. Accepts pipeline input by property name.
    .PARAMETER Id
        The ID of the QoS policy to update.
    .PARAMETER Enabled
        If true, the policy is enabled.
    .PARAMETER Location
        Reference to the array where the policy is defined.
    .PARAMETER MaxTotalBytesPerSec
        The maximum allowed bytes/s totaled across all the clients.
    .PARAMETER MaxTotalOpsPerSec
        The maximum allowed operations/s totaled across all the clients.
    .PARAMETER NewName
        A new name for the QoS policy.
    .PARAMETER Attributes
        A hashtable of QoS policy attributes to modify. Mutually exclusive with the
        individual typed parameters above.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbQosPolicy -Name "qos-gold" -MaxTotalBytesPerSec 2147483648

        Updates the max bandwidth for the specified QoS policy to 2 GB/s using a typed
        parameter.
    .EXAMPLE
        Update-PfbQosPolicy -Id "10314f42-020d-7080-8013-000ddt400012" -Attributes @{ max_total_ops_per_sec = 20000 }

        Updates the max IOPS for the QoS policy by ID.
    .EXAMPLE
        Update-PfbQosPolicy -Name "qos-gold" -Attributes @{} -WhatIf

        Shows what would happen without actually updating the policy.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium',
                   DefaultParameterSetName = 'ByNameIndividual')]
    param(
        [Parameter(ParameterSetName = 'ByNameIndividual', Mandatory, ValueFromPipelineByPropertyName)]
        [Parameter(ParameterSetName = 'ByNameAttributes',  Mandatory, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(ParameterSetName = 'ByIdIndividual', Mandatory)]
        [Parameter(ParameterSetName = 'ByIdAttributes',  Mandatory)]
        [string]$Id,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [Nullable[bool]]$Enabled,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$Location,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [long]$MaxTotalBytesPerSec,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [long]$MaxTotalOpsPerSec,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$NewName,

        [Parameter(ParameterSetName = 'ByNameAttributes', Mandatory)]
        [Parameter(ParameterSetName = 'ByIdAttributes',   Mandatory)]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )
    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $queryParams = @{}
        if ($Name) { $queryParams['names'] = $Name }
        if ($Id) { $queryParams['ids'] = $Id }

        if ($PSCmdlet.ParameterSetName -like '*Attributes') {
            $body = $Attributes
        }
        else {
            $body = @{}
            if ($PSBoundParameters.ContainsKey('Enabled'))             { $body['enabled']                 = $Enabled }
            if ($PSBoundParameters.ContainsKey('Location'))            { $body['location']                = @{ name = $Location } }
            if ($PSBoundParameters.ContainsKey('MaxTotalBytesPerSec')) { $body['max_total_bytes_per_sec'] = $MaxTotalBytesPerSec }
            if ($PSBoundParameters.ContainsKey('MaxTotalOpsPerSec'))   { $body['max_total_ops_per_sec']   = $MaxTotalOpsPerSec }
            if ($PSBoundParameters.ContainsKey('NewName'))             { $body['name']                    = $NewName }
        }

        $target = if ($Name) { $Name } else { $Id }
        if ($PSCmdlet.ShouldProcess($target, 'Update QoS policy')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'qos-policies' -Body $body -QueryParams $queryParams
        }
    }
}
