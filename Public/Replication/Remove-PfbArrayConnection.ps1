function Remove-PfbArrayConnection {
    <#
    .SYNOPSIS
        Removes an array connection from a FlashBlade array.
    .DESCRIPTION
        The Remove-PfbArrayConnection cmdlet deletes a replication connection from the connected
        Pure Storage FlashBlade. The target connection can be identified by name or ID. This
        cmdlet has a high confirm impact and will prompt for confirmation by default. Removing
        an array connection will prevent any associated replication from continuing.
    .PARAMETER Name
        The name of the array connection to remove. Accepts pipeline input.
    .PARAMETER Id
        The ID of the array connection to remove.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbArrayConnection -Name "remote-fb-old"

        Removes the array connection named "remote-fb-old" after prompting for confirmation.
    .EXAMPLE
        Remove-PfbArrayConnection -Name "remote-fb-test" -Confirm:$false

        Removes the array connection named "remote-fb-test" without prompting.
    .EXAMPLE
        Get-PfbArrayConnection -Filter "status='disconnected'" | Remove-PfbArrayConnection

        Removes all disconnected array connections via pipeline input.
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
        if ($Id) { $queryParams['ids'] = $Id }
        if ($PSCmdlet.ShouldProcess($target, 'Remove array connection')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'array-connections' -QueryParams $queryParams
        }
    }
}
