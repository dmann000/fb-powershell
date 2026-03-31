function Remove-PfbNetworkInterface {
    <#
    .SYNOPSIS
        Removes a network interface from the FlashBlade.
    .PARAMETER Name
        The name of the network interface to remove.
    .PARAMETER Id
        The ID of the network interface to remove.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        Remove-PfbNetworkInterface -Name "vir0"
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(ParameterSetName = 'ById', Mandatory)]
        [string]$Id,

        [Parameter()]
        [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $target = if ($Name) { $Name } else { $Id }
        $queryParams = @{}
        if ($Name) { $queryParams['names'] = $Name }
        if ($Id)   { $queryParams['ids']   = $Id }

        if ($PSCmdlet.ShouldProcess($target, 'Remove network interface')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'network-interfaces' -QueryParams $queryParams
        }
    }
}
