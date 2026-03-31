function Remove-PfbPolicy {
    <#
    .SYNOPSIS
        Removes a policy from the FlashBlade.
    .PARAMETER Name
        The name of the policy to remove.
    .PARAMETER Id
        The ID of the policy to remove.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        Remove-PfbPolicy -Name "daily-snap"
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

        if ($PSCmdlet.ShouldProcess($target, 'Remove policy')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'policies' -QueryParams $queryParams
        }
    }
}
