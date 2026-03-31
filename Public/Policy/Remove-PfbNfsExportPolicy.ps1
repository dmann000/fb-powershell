function Remove-PfbNfsExportPolicy {
    <#
    .SYNOPSIS
        Removes an NFS export policy from the FlashBlade.
    .DESCRIPTION
        Deletes an NFS export policy identified by name or ID from the FlashBlade.
        This action is irreversible. Use -Confirm:$false to suppress the confirmation
        prompt in automation scenarios.
    .PARAMETER Name
        The name of the NFS export policy to remove.
    .PARAMETER Id
        The ID of the NFS export policy to remove.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbNfsExportPolicy -Name "nfs-export-01"

        Removes the NFS export policy named 'nfs-export-01'.
    .EXAMPLE
        Remove-PfbNfsExportPolicy -Id "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

        Removes the NFS export policy by ID.
    .EXAMPLE
        Remove-PfbNfsExportPolicy -Name "nfs-export-01" -Confirm:$false

        Removes the NFS export policy without confirmation.
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

        if ($PSCmdlet.ShouldProcess($target, 'Remove NFS export policy')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'nfs-export-policies' -QueryParams $queryParams
        }
    }
}
