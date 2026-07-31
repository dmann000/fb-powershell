function Remove-PfbUserGroupQuotaPolicy {
    <#
    .SYNOPSIS
        Removes a user/group quota policy from a FlashBlade array.
    .PARAMETER Name
        The name of the policy to remove.
    .PARAMETER Id
        The ID of the policy to remove.
    .PARAMETER Version
        One or more version tags for optimistic concurrency control. Fails with a 412 if the
        resource's current version doesn't match.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbUserGroupQuotaPolicy -Name "quota-pol-1"
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateScript({ Assert-PfbSafeName $_ })]
        [string]$Name,

        [Parameter(ParameterSetName = 'ById', Mandatory)]
        [string]$Id,

        [Parameter()] [string[]]$Version,
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
        if ($Version) { $queryParams['versions'] = $Version -join ',' }

        if ($PSCmdlet.ShouldProcess($target, 'Remove user-group-quota policy')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'user-group-quota-policies' -QueryParams $queryParams
        }
    }
}
