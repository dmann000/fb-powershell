function Update-PfbObjectStoreAccountExport {
    <#
    .SYNOPSIS
        Updates an existing object store account export on the FlashBlade.
    .DESCRIPTION
        Modifies the properties of an existing account export, such as its
        enabled state or export rules.

        The individual typed parameters and the raw -Attributes hashtable are mutually
        exclusive: they live in separate parameter sets, so PowerShell rejects a mixed
        invocation at bind time rather than letting -Attributes silently override an
        explicitly supplied value.
    .PARAMETER Name
        The name of the account export to update.
    .PARAMETER Id
        The ID of the account export to update.
    .PARAMETER ExportEnabled
        If set to `true`, the account export is enabled.
    .PARAMETER Policy
        Reference to the s3 export policy that is used for the export.
    .PARAMETER Attributes
        A hashtable of export properties to update. Mutually exclusive with the
        individual typed parameters above.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        Update-PfbObjectStoreAccountExport -Name "nfs-export-1" -ExportEnabled:$false

        Disables the specified account export using a typed parameter.
    .EXAMPLE
        Update-PfbObjectStoreAccountExport -Name "nfs-export-1" -Attributes @{
            export_enabled = $false
        }
        Disables the specified account export.
    .EXAMPLE
        Update-PfbObjectStoreAccountExport -Id "10314f42-020d-7080-8013-000ddt400090" -Attributes @{
            export_enabled = $true
        }
        Enables an account export by its ID.
    .EXAMPLE
        Update-PfbObjectStoreAccountExport -Name "export-acct-prod" -Attributes @{}
        Sends an empty update to refresh the export object.
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
        [Nullable[bool]]$ExportEnabled,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$Policy,

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
            if ($PSBoundParameters.ContainsKey('ExportEnabled')) { $body['export_enabled'] = $ExportEnabled }

            # Constraint 8(a): policy is a SCALAR REFERENCE (item schema is {id, name,
            # resource_type}), so the parameter is [string] and the projection is assigned
            # INLINE -- constraint 7 forbids a local variable here.
            if ($PSBoundParameters.ContainsKey('Policy')) { $body['policy'] = @{ name = $Policy } }
        }

        $target = if ($Name) { $Name } else { $Id }
        if ($PSCmdlet.ShouldProcess($target, 'Update object store account export')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'object-store-account-exports' -Body $body -QueryParams $queryParams
        }
    }
}
