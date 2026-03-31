function Remove-PfbSubnet {
    <#
    .SYNOPSIS
        Removes a subnet from the FlashBlade.
    .PARAMETER Name
        The name of the subnet to remove.
    .PARAMETER Id
        The ID of the subnet to remove.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        Remove-PfbSubnet -Name "subnet1"
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

        if ($PSCmdlet.ShouldProcess($target, 'Remove subnet')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'subnets' -QueryParams $queryParams
        }
    }
}
