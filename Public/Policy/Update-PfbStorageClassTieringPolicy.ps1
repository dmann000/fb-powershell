function Update-PfbStorageClassTieringPolicy {
    <#
    .SYNOPSIS
        Updates an existing storage class tiering policy on a FlashBlade array.
    .DESCRIPTION
        The Update-PfbStorageClassTieringPolicy cmdlet modifies attributes of an existing
        storage class tiering policy on the connected Everpure FlashBlade.

        The individual typed parameters and the raw -Attributes hashtable are mutually
        exclusive: they live in separate parameter sets, so PowerShell rejects a mixed
        invocation at bind time rather than letting -Attributes silently override an
        explicitly supplied value.
    .PARAMETER Name
        The name of the tiering policy to update. Accepts pipeline input by property name.
    .PARAMETER Id
        The ID of the tiering policy to update.
    .PARAMETER ArchivalRules
        The list of archival rules for this policy.
    .PARAMETER Enabled
        If true, the policy is enabled.
    .PARAMETER Location
        Reference to the array where the policy is defined.
    .PARAMETER NewName
        A new name for the tiering policy.
    .PARAMETER RetrievalRules
        The list of retrieval rules for this policy.
    .PARAMETER Attributes
        A hashtable of tiering policy attributes to modify. Mutually exclusive with the
        individual typed parameters above.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbStorageClassTieringPolicy -Name "tier-to-archive" -Enabled $false

        Disables the tiering policy using a typed parameter.
    .EXAMPLE
        Update-PfbStorageClassTieringPolicy -Id "10314f42-020d-7080-8013-000ddt400012" -Attributes @{ cooldown_period = 172800000 }

        Updates the cooldown period by ID.
    .EXAMPLE
        Update-PfbStorageClassTieringPolicy -Name "tier-to-archive" -Attributes @{} -WhatIf

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
        [hashtable[]]$ArchivalRules,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [Nullable[bool]]$Enabled,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$Location,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$NewName,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [hashtable[]]$RetrievalRules,

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
            # Constraint 8(c): archival_rules/retrieval_rules are composite objects (they carry
            # properties outside {id, name, resource_type}), so the parameter is [hashtable[]]
            # and the value is passed straight through -- no @{ name = ... } projection.
            $body = @{}
            if ($PSBoundParameters.ContainsKey('ArchivalRules'))  { $body['archival_rules']  = @($ArchivalRules) }
            if ($PSBoundParameters.ContainsKey('Enabled'))        { $body['enabled']         = $Enabled }
            if ($PSBoundParameters.ContainsKey('Location'))       { $body['location']        = @{ name = $Location } }
            if ($PSBoundParameters.ContainsKey('NewName'))        { $body['name']             = $NewName }
            if ($PSBoundParameters.ContainsKey('RetrievalRules')) { $body['retrieval_rules'] = @($RetrievalRules) }
        }

        $target = if ($Name) { $Name } else { $Id }
        if ($PSCmdlet.ShouldProcess($target, 'Update storage class tiering policy')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'storage-class-tiering-policies' -Body $body -QueryParams $queryParams
        }
    }
}
