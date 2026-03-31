function New-PfbWormPolicy {
    <#
    .SYNOPSIS
        Creates a new WORM data policy on a FlashBlade array.
    .DESCRIPTION
        The New-PfbWormPolicy cmdlet creates a new WORM (Write Once Read Many) data policy
        on the connected Pure Storage FlashBlade. WORM policies enforce data immutability
        for compliance and regulatory requirements.
    .PARAMETER Name
        The name for the new WORM policy.
    .PARAMETER Attributes
        A hashtable of WORM policy attributes such as min_retention and max_retention.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbWormPolicy -Name "worm-compliance" -Attributes @{ min_retention = "P30D" }

        Creates a WORM policy with 30-day minimum retention.
    .EXAMPLE
        New-PfbWormPolicy -Name "worm-legal-hold" -Attributes @{ autocommit_period = "PT1H" }

        Creates a WORM policy with 1-hour autocommit period.
    .EXAMPLE
        New-PfbWormPolicy -Name "worm-test" -Attributes @{} -WhatIf

        Shows what would happen without actually creating the policy.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)] [string]$Name,
        [Parameter(Mandatory)] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )
    Assert-PfbConnection -Array ([ref]$Array)
    $q = @{ 'names' = $Name }
    if ($PSCmdlet.ShouldProcess($Name, 'Create WORM data policy')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'worm-data-policies' -Body $Attributes -QueryParams $q
    }
}
