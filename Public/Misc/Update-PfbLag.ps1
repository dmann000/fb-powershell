function Update-PfbLag {
    <#
    .SYNOPSIS
        Updates a link aggregation group (LAG) on the FlashBlade.
    .DESCRIPTION
        Modifies the configuration of an existing LAG on the FlashBlade, such as
        adding or removing ports or changing LACP settings.
    .PARAMETER Name
        The name of the LAG to update.
    .PARAMETER Id
        The ID of the LAG to update.
    .PARAMETER Attributes
        A hashtable of LAG attributes to update, such as ports or LACP mode.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        Update-PfbLag -Name "lag1" -Attributes @{ ports = @(@{ name = "CH1.FM1.ETH1" }, @{ name = "CH1.FM1.ETH3" }) }

        Updates the ports assigned to the LAG named 'lag1'.
    .EXAMPLE
        Update-PfbLag -Name "lag1" -Attributes @{ lacp_mode = "passive" }

        Changes the LACP mode of 'lag1' to passive.
    .EXAMPLE
        Update-PfbLag -Id "10314f42-020d-7080-8013-000ddt400012" -Attributes @{ lacp_mode = "active" }

        Updates the LAG with the specified ID to active LACP mode.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, ValueFromPipelineByPropertyName)] [string]$Name,
        [Parameter(ParameterSetName = 'ById', Mandatory)] [string]$Id,
        [Parameter(Mandatory)] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )
    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $queryParams = @{}
        if ($Name) { $queryParams['names'] = $Name }
        if ($Id) { $queryParams['ids'] = $Id }
        $target = if ($Name) { $Name } else { $Id }
        if ($PSCmdlet.ShouldProcess($target, 'Update LAG')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'link-aggregation-groups' -Body $Attributes -QueryParams $queryParams
        }
    }
}
