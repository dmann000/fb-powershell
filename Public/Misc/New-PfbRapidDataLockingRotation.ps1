function New-PfbRapidDataLockingRotation {
    <#
    .SYNOPSIS
        Initiates a rapid data locking key rotation on a FlashBlade array.
    .DESCRIPTION
        The New-PfbRapidDataLockingRotation cmdlet triggers a key rotation for rapid data
        locking on the connected Pure Storage FlashBlade. WARNING: This is a critical
        operation that should be performed with extreme caution.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbRapidDataLockingRotation

        Initiates a key rotation after prompting for confirmation.
    .EXAMPLE
        New-PfbRapidDataLockingRotation -Confirm:$false

        Initiates a key rotation without prompting (use with extreme caution).
    .EXAMPLE
        New-PfbRapidDataLockingRotation -WhatIf

        Shows what would happen without actually rotating the key.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([Parameter()] [PSCustomObject]$Array)
    Assert-PfbConnection -Array ([ref]$Array)
    if ($PSCmdlet.ShouldProcess('FlashBlade', 'Rotate rapid data locking key (CRITICAL)')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'rapid-data-locking/rotate'
    }
}
