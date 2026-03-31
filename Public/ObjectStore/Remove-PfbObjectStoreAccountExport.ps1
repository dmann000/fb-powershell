function Remove-PfbObjectStoreAccountExport {
    <#
    .SYNOPSIS
        Removes an object store account export from the FlashBlade.
    .DESCRIPTION
        Deletes the specified object store account export configuration.
    .PARAMETER Name
        The name of the account export to remove.
    .PARAMETER Id
        The ID of the account export to remove.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        Remove-PfbObjectStoreAccountExport -Name "nfs-export-1"
        Removes the specified account export.
    .EXAMPLE
        Remove-PfbObjectStoreAccountExport -Id "10314f42-020d-7080-8013-000ddt400090"
        Removes an account export by its ID.
    .EXAMPLE
        Get-PfbObjectStoreAccountExport -Name "old-export" | Remove-PfbObjectStoreAccountExport
        Retrieves and removes an account export via pipeline.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(ParameterSetName = 'ById', Mandatory)]
        [string]$Id,

        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $target = if ($Name) { $Name } else { $Id }
        $queryParams = @{}
        if ($Name) { $queryParams['names'] = $Name }
        if ($Id)   { $queryParams['ids']   = $Id }

        if ($PSCmdlet.ShouldProcess($target, 'Remove object store account export')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'object-store-account-exports' -QueryParams $queryParams
        }
    }
}
