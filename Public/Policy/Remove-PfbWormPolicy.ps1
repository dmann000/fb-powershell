function Remove-PfbWormPolicy {
    <#
    .SYNOPSIS
        Removes a WORM data policy from a FlashBlade array.
    .DESCRIPTION
        The Remove-PfbWormPolicy cmdlet deletes a WORM data policy from the connected Pure Storage
        FlashBlade. The policy can be identified by name or ID. This cmdlet has a high confirm
        impact and will prompt for confirmation by default.
    .PARAMETER Name
        The name of the WORM policy to remove. Accepts pipeline input.
    .PARAMETER Id
        The ID of the WORM policy to remove.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbWormPolicy -Name "worm-old"

        Removes the WORM policy after prompting for confirmation.
    .EXAMPLE
        Remove-PfbWormPolicy -Name "worm-test" -Confirm:$false

        Removes the WORM policy without prompting.
    .EXAMPLE
        Get-PfbWormPolicy -Filter "enabled='false'" | Remove-PfbWormPolicy

        Removes all disabled WORM policies via pipeline input.
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
        if ($PSCmdlet.ShouldProcess($target, 'Remove WORM data policy')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'worm-data-policies' -QueryParams $queryParams
        }
    }
}
