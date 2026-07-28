function Update-PfbFleet {
    <#
    .SYNOPSIS
        Updates an existing fleet on a FlashBlade array.
    .DESCRIPTION
        The Update-PfbFleet cmdlet modifies attributes of an existing fleet on the connected
        Pure Storage FlashBlade. The fleet can be identified by name or ID. Supports pipeline
        input and ShouldProcess for confirmation prompts.

        The individual typed parameters and the raw -Attributes hashtable are mutually
        exclusive: they live in separate parameter sets, so PowerShell rejects a mixed
        invocation at bind time rather than letting -Attributes silently override an
        explicitly supplied value.
    .PARAMETER Name
        The name of the fleet to update. Accepts pipeline input by property name.
    .PARAMETER Id
        The ID of the fleet to update.
    .PARAMETER NewName
        A new user-specified name for the fleet. Named -NewName rather than -Name because
        -Name already identifies which fleet to update.
    .PARAMETER Attributes
        A hashtable of fleet attributes to modify. Mutually exclusive with the individual
        typed parameters above.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbFleet -Name "fleet-prod" -Attributes @{ description = "Updated description" }

        Updates the description for the fleet named "fleet-prod".
    .EXAMPLE
        Update-PfbFleet -Id "10314f42-020d-7080-8013-000ddt400012" -Attributes @{ name = "fleet-renamed" }

        Renames the fleet identified by the specified ID.
    .EXAMPLE
        Update-PfbFleet -Name "fleet-prod" -Attributes @{} -WhatIf

        Shows what would happen without actually updating the fleet.
    .EXAMPLE
        Update-PfbFleet -Name "fleet-prod" -NewName "fleet-renamed"

        Renames the fleet named "fleet-prod" using the typed parameter.
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
        if ($Id) { $queryParams['ids'] = $Id }

        if ($PSCmdlet.ParameterSetName -like '*Attributes') {
            $body = $Attributes
        }
        else {
            $body = @{}
            if ($PSBoundParameters.ContainsKey('NewName')) { $body['name'] = $NewName }
        }

        $target = if ($Name) { $Name } else { $Id }
        if ($PSCmdlet.ShouldProcess($target, 'Update fleet')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'fleets' -Body $body -QueryParams $queryParams
        }
    }
}
