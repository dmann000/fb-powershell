function Remove-PfbObjectStoreAccessPolicy {
    <#
    .SYNOPSIS
        Removes an object store access policy from the FlashBlade.
    .DESCRIPTION
        Deletes an IAM-style access policy. Any users or accounts that
        reference this policy must have the policy detached before it
        can be deleted.
    .PARAMETER Name
        The name of the access policy to remove.
    .PARAMETER Id
        The ID of the access policy to remove.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        Remove-PfbObjectStoreAccessPolicy -Name "old-policy"
        Removes the access policy named 'old-policy'.
    .EXAMPLE
        Remove-PfbObjectStoreAccessPolicy -Id "10314f42-020d-7080-8013-000ddt400090"
        Removes the access policy by its ID.
    .EXAMPLE
        Get-PfbObjectStoreAccessPolicy -Name "temp-policy" | Remove-PfbObjectStoreAccessPolicy
        Retrieves and removes the specified access policy via pipeline.
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

        if ($PSCmdlet.ShouldProcess($target, 'Remove object store access policy')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'object-store-access-policies' -QueryParams $queryParams
        }
    }
}
