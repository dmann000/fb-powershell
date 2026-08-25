function Update-PfbSupport {
    <#
    .SYNOPSIS
        Updates support configuration on a FlashBlade array.
    .DESCRIPTION
        The Update-PfbSupport cmdlet modifies the support configuration -- Phone Home, Remote
        Assist and related settings -- on the connected FlashBlade.
    .PARAMETER Attributes
        A hashtable of support attributes to modify.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbSupport -Attributes @{ phonehome_enabled = $true }

        Enables Phone Home.
    .EXAMPLE
        Update-PfbSupport -Attributes @{ remote_assist_active = $false } -WhatIf

        Shows what would happen without actually updating the support configuration.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )
    Assert-PfbConnection -Array ([ref]$Array)
    if ($PSCmdlet.ShouldProcess('Support', 'Update support configuration')) {
        Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'support' -Body $Attributes
    }
}
