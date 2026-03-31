function Remove-PfbObjectStoreUser {
    <#
    .SYNOPSIS
        Removes an object store user from the FlashBlade.
    .PARAMETER Name
        The name of the user to remove.
    .PARAMETER Id
        The ID of the user to remove.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        Remove-PfbObjectStoreUser -Name "myaccount/myuser"
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

        if ($PSCmdlet.ShouldProcess($target, 'Remove object store user')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'object-store-users' -QueryParams $queryParams
        }
    }
}
