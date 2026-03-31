function Remove-PfbLag {
    <#
    .SYNOPSIS
        Removes a link aggregation group (LAG) from the FlashBlade.
    .DESCRIPTION
        Deletes a LAG from the FlashBlade array. All subnets and network interfaces
        associated with the LAG must be removed first. This operation requires confirmation.
    .PARAMETER Name
        The name of the LAG to remove.
    .PARAMETER Id
        The ID of the LAG to remove.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        Remove-PfbLag -Name "lag1"

        Removes the LAG named 'lag1' after confirmation.
    .EXAMPLE
        Remove-PfbLag -Name "lag1" -Confirm:$false

        Removes the LAG named 'lag1' without prompting for confirmation.
    .EXAMPLE
        Remove-PfbLag -Id "10314f42-020d-7080-8013-000ddt400012"

        Removes the LAG with the specified ID after confirmation.
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
        if ($PSCmdlet.ShouldProcess($target, 'Remove LAG')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'link-aggregation-groups' -QueryParams $queryParams
        }
    }
}
