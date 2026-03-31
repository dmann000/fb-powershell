function Update-PfbObjectStoreRole {
    <#
    .SYNOPSIS
        Updates an existing object store role on the FlashBlade.
    .DESCRIPTION
        Modifies the properties of an existing object store role, such as its
        description or assume-role policy document.
    .PARAMETER Name
        The name of the role to update.
    .PARAMETER Id
        The ID of the role to update.
    .PARAMETER Attributes
        A hashtable of role properties to update.
    .PARAMETER Array
        The FlashBlade connection object.
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
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(ParameterSetName = 'ById', Mandatory)]
        [string]$Id,

        [Parameter()]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $target = if ($Name) { $Name } else { $Id }
        $body = if ($Attributes) { $Attributes } else { @{} }
        $queryParams = @{}
        if ($Name) { $queryParams['names'] = $Name }
        if ($Id)   { $queryParams['ids']   = $Id }

        if ($PSCmdlet.ShouldProcess($target, 'Update object store role')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'object-store-roles' -Body $body -QueryParams $queryParams
        }
    }
}
