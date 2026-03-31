function Update-PfbNode {
    <#
    .SYNOPSIS
        Updates a node on a FlashBlade array.
    .DESCRIPTION
        The Update-PfbNode cmdlet modifies attributes of a node on the connected Pure Storage
        FlashBlade. The node can be identified by name or ID. Supports ShouldProcess for
        -WhatIf and -Confirm.
    .PARAMETER Name
        The name of the node to update.
    .PARAMETER Id
        The ID of the node to update.
    .PARAMETER Attributes
        A hashtable of node attributes to modify.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbNode -Name "CH1.FB1" -Attributes @{ identify_enabled = $true }

        Enables the identification LED on the specified node.
    .EXAMPLE
        Update-PfbNode -Id "10314f42-020d-7080-8013-000ddt400005" -Attributes @{ identify_enabled = $false }

        Disables the identification LED on the node identified by ID.
    .EXAMPLE
        Update-PfbNode -Name "CH1.FB1" -Attributes @{ identify_enabled = $true } -WhatIf

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
        if ($PSCmdlet.ShouldProcess($target, 'Update node')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'nodes' -Body $Attributes -QueryParams $queryParams
        }
    }
}
