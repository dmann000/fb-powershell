function Remove-PfbObjectStoreRole {
    <#
    .SYNOPSIS
        Removes an object store role from the FlashBlade.
    .DESCRIPTION
        Deletes the specified object store role. The role must not be in active
        use by any sessions. Associated access policy and trust policy links are
        removed automatically.
    .PARAMETER Name
        The name of the role to remove.
    .PARAMETER Id
        The ID of the role to remove.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        Remove-PfbObjectStoreRole -Name "obsolete-role"
        Removes the role named 'obsolete-role'.
    .EXAMPLE
        Remove-PfbObjectStoreRole -Id "10314f42-020d-7080-8013-000ddt400012"
        Removes a role by its ID.
    .EXAMPLE
        Get-PfbObjectStoreRole -Name "temp-role" | Remove-PfbObjectStoreRole
        Retrieves and removes the role via pipeline.
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

        if ($PSCmdlet.ShouldProcess($target, 'Remove object store role')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'object-store-roles' -QueryParams $queryParams
        }
    }
}
