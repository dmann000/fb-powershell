function New-PfbStorageClassTieringPolicy {
    <#
    .SYNOPSIS
        Creates a new storage class tiering policy on a FlashBlade array.
    .DESCRIPTION
        The New-PfbStorageClassTieringPolicy cmdlet creates a new storage class tiering policy
        on the connected Pure Storage FlashBlade. Tiering policies control data movement
        between storage classes.
    .PARAMETER Name
        The name for the new tiering policy.
    .PARAMETER Attributes
        A hashtable of tiering policy attributes such as rules and storage class targets.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbStorageClassTieringPolicy -Name "tier-to-archive" -Attributes @{ enabled = $true }

        Creates a new tiering policy with default settings.
    .EXAMPLE
        New-PfbStorageClassTieringPolicy -Name "tier-cold-data" -Attributes @{ cooldown_period = 86400000 }

        Creates a tiering policy with a 24-hour cooldown period.
    .EXAMPLE
        New-PfbStorageClassTieringPolicy -Name "tier-test" -Attributes @{} -WhatIf

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
    if ($PSCmdlet.ShouldProcess($Name, 'Create storage class tiering policy')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'storage-class-tiering-policies' -Body $Attributes -QueryParams $q
    }
}
