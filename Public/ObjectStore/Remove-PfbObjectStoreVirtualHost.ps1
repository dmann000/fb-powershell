function Remove-PfbObjectStoreVirtualHost {
    <#
    .SYNOPSIS
        Removes an object store virtual host from the FlashBlade.
    .DESCRIPTION
        Deletes an object store virtual host identified by name or ID from the FlashBlade.
        This action is irreversible. Use -Confirm:$false to suppress the confirmation
        prompt in automation scenarios.
    .PARAMETER Name
        The name of the object store virtual host to remove.
    .PARAMETER Id
        The ID of the object store virtual host to remove.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbObjectStoreVirtualHost -Name "s3.example.com"

        Removes the object store virtual host named 's3.example.com'.
    .EXAMPLE
        Remove-PfbObjectStoreVirtualHost -Id "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

        Removes the object store virtual host by ID.
    .EXAMPLE
        Remove-PfbObjectStoreVirtualHost -Name "s3.example.com" -Confirm:$false

        Removes the object store virtual host without confirmation.
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

        if ($PSCmdlet.ShouldProcess($target, 'Remove object store virtual host')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'object-store-virtual-hosts' -QueryParams $queryParams
        }
    }
}
