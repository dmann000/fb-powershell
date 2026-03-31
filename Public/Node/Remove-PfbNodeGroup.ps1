function Remove-PfbNodeGroup {
    <#
    .SYNOPSIS
        Removes a node group from a FlashBlade array.
    .DESCRIPTION
        The Remove-PfbNodeGroup cmdlet deletes a node group from the connected Pure Storage
        FlashBlade. The group can be identified by name or ID. This cmdlet has a high confirm
        impact and will prompt for confirmation by default. Nodes must be removed from the
        group before it can be deleted.
    .PARAMETER Name
        The name of the node group to remove. Accepts pipeline input.
    .PARAMETER Id
        The ID of the node group to remove.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbNodeGroup -Name "old-group"

        Removes the node group after prompting for confirmation.
    .EXAMPLE
        Remove-PfbNodeGroup -Name "test-group" -Confirm:$false

        Removes the node group without prompting.
    .EXAMPLE
        Get-PfbNodeGroup -Filter "node_count=0" | Remove-PfbNodeGroup

        Removes all empty node groups via pipeline input.
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
        if ($PSCmdlet.ShouldProcess($target, 'Remove node group')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'node-groups' -QueryParams $queryParams
        }
    }
}
