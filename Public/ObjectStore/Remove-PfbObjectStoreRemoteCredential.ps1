function Remove-PfbObjectStoreRemoteCredential {
    <#
    .SYNOPSIS
        Removes an object store remote credential from the FlashBlade.
    .DESCRIPTION
        Deletes a remote credential used for object replication to external
        S3-compatible targets. Any replication configurations referencing this
        credential must be removed first.
    .PARAMETER Name
        The name of the remote credential to remove.
    .PARAMETER Id
        The ID of the remote credential to remove.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        Remove-PfbObjectStoreRemoteCredential -Name "s3-repl-cred"
        Removes the remote credential named 's3-repl-cred'.
    .EXAMPLE
        Remove-PfbObjectStoreRemoteCredential -Id "10314f42-020d-7080-8013-000ddt400090"
        Removes the remote credential by its ID.
    .EXAMPLE
        Get-PfbObjectStoreRemoteCredential -Name "old-cred" | Remove-PfbObjectStoreRemoteCredential
        Retrieves and removes the specified remote credential via pipeline.
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

        if ($PSCmdlet.ShouldProcess($target, 'Remove object store remote credential')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'object-store-remote-credentials' -QueryParams $queryParams
        }
    }
}
