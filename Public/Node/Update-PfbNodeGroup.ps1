function Update-PfbNodeGroup {
    <#
    .SYNOPSIS
        Updates an existing node group on a FlashBlade array.
    .DESCRIPTION
        The Update-PfbNodeGroup cmdlet modifies attributes of an existing node group on the
        connected Everpure FlashBlade. The group can be identified by name or ID. Supports
        ShouldProcess for -WhatIf and -Confirm.

        The individual typed parameters and the raw -Attributes hashtable are mutually
        exclusive: they live in separate parameter sets, so PowerShell rejects a mixed
        invocation at bind time rather than letting -Attributes silently override an
        explicitly supplied value.
    .PARAMETER Name
        The name of the node group to update.
    .PARAMETER Id
        The ID of the node group to update.
    .PARAMETER NewName
        A new user-specified name for the node group.
    .PARAMETER Attributes
        A hashtable of node group attributes to modify. Mutually exclusive with the individual
        typed parameters above.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbNodeGroup -Name "analytics-group" -Attributes @{ name = 'analytics-primary' }

        Renames the node group using the raw -Attributes hashtable.
    .EXAMPLE
        Update-PfbNodeGroup -Id "10314f42-020d-7080-8013-000ddt400020" -Attributes @{ priority = 'low' }

        Updates the node group identified by ID.
    .EXAMPLE
        Update-PfbNodeGroup -Name "test-group" -Attributes @{ name = 'prod-group' } -WhatIf

        Shows what would happen without applying the change.
    .EXAMPLE
        Update-PfbNodeGroup -Name "analytics-group" -NewName "analytics-primary"

        Renames the node group using the typed -NewName parameter.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium',
                   DefaultParameterSetName = 'ByNameIndividual')]
    param(
        [Parameter(ParameterSetName = 'ByNameIndividual', Mandatory, ValueFromPipelineByPropertyName)]
        [Parameter(ParameterSetName = 'ByNameAttributes',  Mandatory, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(ParameterSetName = 'ByIdIndividual', Mandatory)]
        [Parameter(ParameterSetName = 'ByIdAttributes',  Mandatory)]
        [string]$Id,

        # Exception: the body field is literally `name` (renames the resource), so the
        # parameter is -NewName, never -NodeGroupName -- see Update-PfbWorkload /
        # Update-PfbDataEvictionPolicy.
        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$NewName,

        [Parameter(ParameterSetName = 'ByNameAttributes', Mandatory)]
        [Parameter(ParameterSetName = 'ByIdAttributes',   Mandatory)]
        [hashtable]$Attributes,

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

        if ($PSCmdlet.ParameterSetName -like '*Attributes') {
            $body = $Attributes
        }
        else {
            # EVERY value-carrying parameter is guarded by $PSBoundParameters.ContainsKey,
            # never by truthiness -- see Update-PfbAdmin.ps1 for the full rationale.
            $body = @{}
            if ($PSBoundParameters.ContainsKey('NewName')) { $body['name'] = $NewName }
        }

        if ($PSCmdlet.ShouldProcess($target, 'Update node group')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'node-groups' -Body $body -QueryParams $queryParams
        }
    }
}
