function Update-PfbRealmDefaults {
    <#
    .SYNOPSIS
        Updates realm default settings on a FlashBlade array.
    .DESCRIPTION
        The Update-PfbRealmDefaults cmdlet modifies the default settings for a realm on the
        connected Everpure FlashBlade.

        The individual typed parameters and the raw -Attributes hashtable are mutually
        exclusive: they live in separate parameter sets, so PowerShell rejects a mixed
        invocation at bind time rather than letting -Attributes silently override an
        explicitly supplied value.
    .PARAMETER Name
        The name of the realm to update defaults for.
    .PARAMETER Id
        The ID of the realm to update defaults for.
    .PARAMETER ObjectStore
        Default configurations for object store.
    .PARAMETER Attributes
        A hashtable of realm default attributes to modify. Mutually exclusive with the
        individual typed parameters above.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbRealmDefaults -Name "realm-prod" -ObjectStore @{ server = @{ name = "obj-server-1" } }

        Updates the default object store server for the specified realm using a typed parameter.
    .EXAMPLE
        Update-PfbRealmDefaults -Id "10314f42-020d-7080-8013-000ddt400012" -Attributes @{}

        Updates realm defaults by ID.
    .EXAMPLE
        Update-PfbRealmDefaults -Name "realm-prod" -Attributes @{} -WhatIf

        Shows what would happen without actually updating the defaults.
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
        [hashtable[]]$ObjectStore,

        [Parameter(ParameterSetName = 'ByNameAttributes', Mandatory)]
        [Parameter(ParameterSetName = 'ByIdAttributes',   Mandatory)]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )
    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        # Wire-key bug fix (#31): PATCH /realms/defaults only accepts realm_ids/realm_names
        # as query parameters -- there is no plain names/ids query parameter on this endpoint.
        # The previous code sent names/ids, which the array does not recognize for this
        # endpoint, so -Name and -Id had no effect on which realm's defaults were targeted.
        $queryParams = @{}
        if ($Name) { $queryParams['realm_names'] = $Name }
        if ($Id)   { $queryParams['realm_ids']   = $Id }

        if ($PSCmdlet.ParameterSetName -like '*Attributes') {
            $body = $Attributes
        }
        else {
            # Constraint 8(c): object_store is a COMPOSITE array (item schema has a property,
            # `server`, outside {id, name, resource_type}), so the parameter is [hashtable[]]
            # and is passed straight through -- constraint 7 forbids a $objectStoreItems local.
            $body = @{}
            if ($PSBoundParameters.ContainsKey('ObjectStore')) { $body['object_store'] = @($ObjectStore) }
        }

        $target = if ($Name) { $Name } else { $Id }
        if ($PSCmdlet.ShouldProcess($target, 'Update realm defaults')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'realms/defaults' -Body $body -QueryParams $queryParams
        }
    }
}
