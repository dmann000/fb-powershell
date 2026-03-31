function Update-PfbObjectStoreAccountExport {
    <#
    .SYNOPSIS
        Updates an existing object store account export on the FlashBlade.
    .DESCRIPTION
        Modifies the properties of an existing account export, such as its
        enabled state or export rules.
    .PARAMETER Name
        The name of the account export to update.
    .PARAMETER Id
        The ID of the account export to update.
    .PARAMETER Attributes
        A hashtable of export properties to update.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        Update-PfbObjectStoreAccountExport -Name "nfs-export-1" -Attributes @{
            enabled = $false
        }
        Disables the specified account export.
    .EXAMPLE
        Update-PfbObjectStoreAccountExport -Id "10314f42-020d-7080-8013-000ddt400090" -Attributes @{
            enabled = $true
        }
        Enables an account export by its ID.
    .EXAMPLE
        Update-PfbObjectStoreAccountExport -Name "export-acct-prod" -Attributes @{}
        Sends an empty update to refresh the export object.
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

        if ($PSCmdlet.ShouldProcess($target, 'Update object store account export')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'object-store-account-exports' -Body $body -QueryParams $queryParams
        }
    }
}
