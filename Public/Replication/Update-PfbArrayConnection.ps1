function Update-PfbArrayConnection {
    <#
    .SYNOPSIS
        Updates an existing array connection on a FlashBlade array.
    .DESCRIPTION
        The Update-PfbArrayConnection cmdlet modifies attributes of an existing replication
        connection on the connected Pure Storage FlashBlade. The target connection can be
        identified by name or ID. Common updates include changing replication addresses and
        connection throttling settings. Supports pipeline input and ShouldProcess.
    .PARAMETER Name
        The name of the array connection to update. Accepts pipeline input by property name.
    .PARAMETER Id
        The ID of the array connection to update.
    .PARAMETER Attributes
        A hashtable of array connection attributes to modify.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbArrayConnection -Name "remote-fb-dc2" -Attributes @{ management_address = "10.0.2.101" }

        Updates the management address for the array connection named "remote-fb-dc2".
    .EXAMPLE
        Update-PfbArrayConnection -Name "remote-fb-dr" -Attributes @{ replication_addresses = @("10.0.3.101") }

        Updates the replication address for the "remote-fb-dr" array connection.
    .EXAMPLE
        Update-PfbArrayConnection -Id "10314f42-020d-7080-8013-000ddt400077" -Attributes @{ status = "connected" }

        Updates the status of the array connection identified by the specified ID.
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
        if ($PSCmdlet.ShouldProcess($target, 'Update array connection')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'array-connections' -Body $Attributes -QueryParams $queryParams
        }
    }
}
