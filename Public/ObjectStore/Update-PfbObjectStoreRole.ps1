function Update-PfbObjectStoreRole {
    <#
    .SYNOPSIS
        Updates an existing object store role on the FlashBlade.
    .DESCRIPTION
        Modifies the properties of an existing object store role, such as its
        description or assume-role policy document.

        The individual typed parameters and the raw -Attributes hashtable are mutually
        exclusive: they live in separate parameter sets, so PowerShell rejects a mixed
        invocation at bind time rather than letting -Attributes silently override an
        explicitly supplied value.
    .PARAMETER Name
        The name of the role to update.
    .PARAMETER Id
        The ID of the role to update.
    .PARAMETER Account
        Reference of the associated account.
    .PARAMETER MaxSessionDuration
        The maximum session duration for the role in milliseconds.
    .PARAMETER Attributes
        A hashtable of role properties to update. Mutually exclusive with the
        individual typed parameters above.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        Update-PfbObjectStoreRole -Name "s3-admin-role" -MaxSessionDuration 3600000

        Sets the maximum session duration for the role using a typed parameter.
    .EXAMPLE
        Update-PfbObjectStoreRole -Name "s3-admin-role" -Attributes @{
            description = "Updated admin role description"
        }
        Updates the description of the specified role.
    .EXAMPLE
        Update-PfbObjectStoreRole -Id "10314f42-020d-7080-8013-000ddt400012" -Attributes @{
            description = "Updated by ID"
        }
        Updates a role identified by its ID.
    .EXAMPLE
        Update-PfbObjectStoreRole -Name "replication-role" -Attributes @{}
        Sends an empty update to refresh the role object.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium',
                   DefaultParameterSetName = 'ByNameIndividual')]
    param(
        [Parameter(ParameterSetName = 'ByNameIndividual', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Parameter(ParameterSetName = 'ByNameAttributes',  Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(ParameterSetName = 'ByIdIndividual', Mandatory)]
        [Parameter(ParameterSetName = 'ByIdAttributes',  Mandatory)]
        [string]$Id,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$Account,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [int]$MaxSessionDuration,

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
        if ($Id)   { $queryParams['ids']   = $Id }

        if ($PSCmdlet.ParameterSetName -like '*Attributes') {
            $body = $Attributes
        }
        else {
            $body = @{}

            # Constraint 8(a): account is a SCALAR REFERENCE (item schema is {id, name,
            # resource_type}), so the parameter is [string] and the projection is assigned
            # INLINE -- constraint 7 forbids a local variable here.
            if ($PSBoundParameters.ContainsKey('Account')) { $body['account'] = @{ name = $Account } }

            # Constraint 2: integer body field -- guarded by ContainsKey, not truthiness, so
            # an explicit -MaxSessionDuration 0 still reaches the wire.
            if ($PSBoundParameters.ContainsKey('MaxSessionDuration')) { $body['max_session_duration'] = $MaxSessionDuration }
        }

        $target = if ($Name) { $Name } else { $Id }
        if ($PSCmdlet.ShouldProcess($target, 'Update object store role')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'object-store-roles' -Body $body -QueryParams $queryParams
        }
    }
}
