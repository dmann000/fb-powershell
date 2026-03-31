function Update-PfbObjectStoreVirtualHost {
    <#
    .SYNOPSIS
        Updates an existing object store virtual host on the FlashBlade.
    .DESCRIPTION
        Modifies the properties of an existing object store virtual host,
        such as its enabled state or associated access policies.
    .PARAMETER Name
        The name of the virtual host to update.
    .PARAMETER Id
        The ID of the virtual host to update.
    .PARAMETER Attributes
        A hashtable of virtual host properties to update.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        Update-PfbObjectStoreVirtualHost -Name "s3.example.com" -Attributes @{
            enabled = $true
        }
        Enables the specified virtual host.
    .EXAMPLE
        Update-PfbObjectStoreVirtualHost -Id "10314f42-020d-7080-8013-000ddt400090" -Attributes @{
            enabled = $false
        }
        Disables a virtual host by its ID.
    .EXAMPLE
        Update-PfbObjectStoreVirtualHost -Name "data.example.com" -Attributes @{}
        Sends an empty update to refresh the virtual host object.
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

        if ($PSCmdlet.ShouldProcess($target, 'Update object store virtual host')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'object-store-virtual-hosts' -Body $body -QueryParams $queryParams
        }
    }
}
