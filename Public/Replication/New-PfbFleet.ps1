function New-PfbFleet {
    <#
    .SYNOPSIS
        Creates a new fleet on a FlashBlade array.
    .DESCRIPTION
        The New-PfbFleet cmdlet creates a new fleet on the connected Pure Storage FlashBlade.
        Fleets group multiple FlashBlade arrays for coordinated management and replication.
        The Attributes hashtable specifies the fleet configuration details.
    .PARAMETER Name
        The name for the new fleet.
    .PARAMETER Attributes
        A hashtable of fleet attributes to configure.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbFleet -Name "fleet-prod" -Attributes @{}

        Creates a new fleet named "fleet-prod" with default attributes.
    .EXAMPLE
        New-PfbFleet -Name "fleet-dr" -Attributes @{ description = "Disaster recovery fleet" }

        Creates a new fleet with a description.
    .EXAMPLE
        New-PfbFleet -Name "fleet-test" -Attributes @{} -WhatIf

        Shows what would happen without actually creating the fleet.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)] [string]$Name,
        [Parameter(Mandatory)] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )
    Assert-PfbConnection -Array ([ref]$Array)
    $q = @{ 'names' = $Name }
    if ($PSCmdlet.ShouldProcess($Name, 'Create fleet')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'fleets' -Body $Attributes -QueryParams $q
    }
}
