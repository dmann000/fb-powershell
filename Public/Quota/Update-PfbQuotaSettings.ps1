function Update-PfbQuotaSettings {
    <#
    .SYNOPSIS
        Updates quota settings on a FlashBlade array.
    .DESCRIPTION
        The Update-PfbQuotaSettings cmdlet modifies the global quota settings on the connected
        Pure Storage FlashBlade.
    .PARAMETER Attributes
        A hashtable of quota settings to modify.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbQuotaSettings -Attributes @{ contact_info = "admin@example.com" }

        Updates the quota contact information.
    .EXAMPLE
        Update-PfbQuotaSettings -Attributes @{ notification_enabled = $true }

        Enables quota notifications.
    .EXAMPLE
        Update-PfbQuotaSettings -Attributes @{} -WhatIf

        Shows what would happen without actually updating the settings.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )
    Assert-PfbConnection -Array ([ref]$Array)
    if ($PSCmdlet.ShouldProcess('FlashBlade', 'Update quota settings')) {
        Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'quotas/settings' -Body $Attributes
    }
}
