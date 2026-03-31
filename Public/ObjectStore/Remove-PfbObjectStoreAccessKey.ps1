function Remove-PfbObjectStoreAccessKey {
    <#
    .SYNOPSIS
        Removes an object store access key from the FlashBlade.
    .PARAMETER Name
        The access key name to remove.
    .PARAMETER Id
        The access key ID to remove.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        Remove-PfbObjectStoreAccessKey -Name "PSFBIKXXXXXXXXX"
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

        if ($PSCmdlet.ShouldProcess($target, 'Remove object store access key')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'object-store-access-keys' -QueryParams $queryParams
        }
    }
}
