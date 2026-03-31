function Remove-PfbObjectStoreAccount {
    <#
    .SYNOPSIS
        Removes an object store account from the FlashBlade.
    .PARAMETER Name
        The name of the account to remove.
    .PARAMETER Id
        The ID of the account to remove.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        Remove-PfbObjectStoreAccount -Name "myaccount"
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

        if ($PSCmdlet.ShouldProcess($target, 'Remove object store account')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'object-store-accounts' -QueryParams $queryParams
        }
    }
}
