function Update-PfbRapidDataLocking {
    <#
    .SYNOPSIS
        Updates rapid data locking settings on the FlashBlade.
    .DESCRIPTION
        The Update-PfbRapidDataLocking cmdlet modifies the rapid data locking configuration on
        the connected Pure Storage FlashBlade. Rapid data locking provides a fast mechanism to
        cryptographically erase all data on the array by destroying encryption keys.
    .PARAMETER Attributes
        A hashtable of rapid data locking settings to update.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbRapidDataLocking -Attributes @{ enabled = $true }

        Enables rapid data locking on the connected FlashBlade.
    .EXAMPLE
        Update-PfbRapidDataLocking -Attributes @{ enabled = $false }

        Disables rapid data locking on the connected FlashBlade.
    .EXAMPLE
        Update-PfbRapidDataLocking -Attributes @{ enabled = $true } -Confirm:$false

        Enables rapid data locking without prompting for confirmation.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    if ($PSCmdlet.ShouldProcess('Rapid Data Locking', 'Update rapid data locking settings')) {
        Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'rapid-data-locking' -Body $Attributes
    }
}
