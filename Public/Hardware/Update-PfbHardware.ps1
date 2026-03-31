function Update-PfbHardware {
    <#
    .SYNOPSIS
        Updates a hardware component on a FlashBlade array.
    .DESCRIPTION
        The Update-PfbHardware cmdlet modifies attributes of a hardware component on the
        connected Pure Storage FlashBlade. The component can be identified by name or ID.
        Common updates include enabling or disabling visual identification LEDs.
        Supports ShouldProcess for -WhatIf and -Confirm.
    .PARAMETER Name
        The name of the hardware component to update.
    .PARAMETER Id
        The ID of the hardware component to update.
    .PARAMETER Attributes
        A hashtable of hardware attributes to modify, such as identify_enabled.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbHardware -Name "CH1.FB1" -Attributes @{ identify_enabled = $true }

        Enables the identification LED on the specified hardware component.
    .EXAMPLE
        Update-PfbHardware -Id "10314f42-020d-7080-8013-000ddt400001" -Attributes @{ identify_enabled = $false }

        Disables the identification LED on the hardware component identified by ID.
    .EXAMPLE
        Update-PfbHardware -Name "CH1.FM1" -Attributes @{ identify_enabled = $true } -WhatIf

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
        if ($PSCmdlet.ShouldProcess($target, 'Update hardware')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'hardware' -Body $Attributes -QueryParams $queryParams
        }
    }
}
