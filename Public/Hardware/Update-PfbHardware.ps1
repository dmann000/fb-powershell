function Update-PfbHardware {
    <#
    .SYNOPSIS
        Updates a hardware component on a FlashBlade array.
    .DESCRIPTION
        The Update-PfbHardware cmdlet modifies attributes of a hardware component on the
        connected Everpure FlashBlade. The component can be identified by name or ID.
        Common updates include enabling or disabling visual identification LEDs.
        Supports ShouldProcess for -WhatIf and -Confirm.

        The individual typed parameters and the raw -Attributes hashtable are mutually
        exclusive: they live in separate parameter sets, so PowerShell rejects a mixed
        invocation at bind time rather than letting -Attributes silently override an
        explicitly supplied value.
    .PARAMETER Name
        The name of the hardware component to update. Accepts pipeline input by property name.
    .PARAMETER Id
        The ID of the hardware component to update.
    .PARAMETER IdentifyEnabled
        State of an LED used to visually identify the component.
    .PARAMETER Attributes
        A hashtable of hardware attributes to modify. Mutually exclusive with the individual
        typed parameters above.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbHardware -Name "CH1.FB1" -IdentifyEnabled $true

        Enables the identification LED on the specified hardware component using a typed
        parameter.
    .EXAMPLE
        Update-PfbHardware -Id "10314f42-020d-7080-8013-000ddt400001" -Attributes @{ identify_enabled = $false }

        Disables the identification LED on the hardware component identified by ID.
    .EXAMPLE
        Update-PfbHardware -Name "CH1.FM1" -Attributes @{ identify_enabled = $true } -WhatIf

        Shows what would happen without applying the change.
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
        [Nullable[bool]]$IdentifyEnabled,

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

        if ($PSCmdlet.ParameterSetName -like '*Attributes') {
            $body = $Attributes
        }
        else {
            # Every value-carrying parameter is guarded by ContainsKey, never by truthiness --
            # see the canonical explanation in Update-PfbAdmin.ps1.
            $body = @{}
            if ($PSBoundParameters.ContainsKey('IdentifyEnabled')) { $body['identify_enabled'] = $IdentifyEnabled }
        }

        $target = if ($Name) { $Name } else { $Id }
        if ($PSCmdlet.ShouldProcess($target, 'Update hardware')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'hardware' -Body $body -QueryParams $queryParams
        }
    }
}
