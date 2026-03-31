function Update-PfbNodeGroup {
    <#
    .SYNOPSIS
        Updates an existing node group on a FlashBlade array.
    .DESCRIPTION
        The Update-PfbNodeGroup cmdlet modifies attributes of an existing node group on the
        connected Pure Storage FlashBlade. The group can be identified by name or ID.
        Supports ShouldProcess for -WhatIf and -Confirm.
    .PARAMETER Name
        The name of the node group to update.
    .PARAMETER Id
        The ID of the node group to update.
    .PARAMETER Attributes
        A hashtable of node group attributes to modify.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbNodeGroup -Name "analytics-group" -Attributes @{ name = 'analytics-primary' }

        Renames the node group.
    .EXAMPLE
        Update-PfbNodeGroup -Id "10314f42-020d-7080-8013-000ddt400020" -Attributes @{ priority = 'low' }

        Updates the node group identified by ID.
    .EXAMPLE
        Update-PfbNodeGroup -Name "test-group" -Attributes @{ name = 'prod-group' } -WhatIf

        Shows what would happen without applying the change.
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
        if ($Id)   { $queryParams['ids']   = $Id }
        $target = if ($Name) { $Name } else { $Id }
        if ($PSCmdlet.ShouldProcess($target, 'Update node group')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'node-groups' -Body $Attributes -QueryParams $queryParams
        }
    }
}
