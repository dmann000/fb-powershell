function Remove-PfbTarget {
    <#
    .SYNOPSIS
        Removes a replication target from a FlashBlade array.
    .DESCRIPTION
        The Remove-PfbTarget cmdlet deletes a replication target from the connected Pure Storage
        FlashBlade. The target can be identified by name or ID. This cmdlet has a high confirm
        impact and will prompt for confirmation by default. Removing a target will prevent any
        associated replication policies from functioning. Supports pipeline input.
    .PARAMETER Name
        The name of the replication target to remove. Accepts pipeline input.
    .PARAMETER Id
        The ID of the replication target to remove.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbTarget -Name "s3-target-old"

        Removes the replication target named "s3-target-old" after prompting for confirmation.
    .EXAMPLE
        Remove-PfbTarget -Name "remote-fb-test" -Confirm:$false

        Removes the replication target named "remote-fb-test" without prompting.
    .EXAMPLE
        Get-PfbTarget -Filter "status='disconnected'" | Remove-PfbTarget

        Removes all disconnected replication targets via pipeline input.
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
        if ($PSCmdlet.ShouldProcess($target, 'Remove target')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'targets' -QueryParams $queryParams
        }
    }
}
