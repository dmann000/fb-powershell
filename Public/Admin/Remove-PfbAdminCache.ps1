function Remove-PfbAdminCache {
    <#
    .SYNOPSIS
        Clears admin cache entries from the FlashBlade.
    .DESCRIPTION
        The Remove-PfbAdminCache cmdlet deletes cached administrator entries from the connected
        FlashBlade. Clearing the admin cache forces re-authentication of administrator accounts,
        which can be useful after changing directory service configurations or roles.
    .PARAMETER Name
        The name of the admin cache entry to remove.
    .PARAMETER Id
        The ID of the admin cache entry to remove.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbAdminCache -Name 'pureuser'

        Clears the admin cache entry for 'pureuser' after confirmation.
    .EXAMPLE
        Remove-PfbAdminCache -Name 'pureuser' -Confirm:$false

        Clears the admin cache entry without prompting for confirmation.
    .EXAMPLE
        Get-PfbAdminCache | Remove-PfbAdminCache

        Clears all admin cache entries via pipeline input.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)] [string]$Name,
        [Parameter(ParameterSetName = 'ById', Mandatory)] [string]$Id,
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
        if ($PSCmdlet.ShouldProcess($target, 'Clear admin cache entry')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'admins/cache' -QueryParams $queryParams
        }
    }
}
