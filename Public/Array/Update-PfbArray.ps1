function Update-PfbArray {
    <#
    .SYNOPSIS
        Updates array-level settings on a FlashBlade.
    .DESCRIPTION
        The Update-PfbArray cmdlet modifies array-level configuration on the connected Pure
        Storage FlashBlade. This is a singleton endpoint that affects the entire array, such
        as changing the array name, NTP servers, or time zone.
    .PARAMETER Attributes
        A hashtable of array attributes to modify.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbArray -Attributes @{ name = "fb-prod-01" }

        Renames the FlashBlade array.
    .EXAMPLE
        Update-PfbArray -Attributes @{ ntp_servers = @("0.pool.ntp.org","1.pool.ntp.org") }

        Updates the NTP server configuration.
    .EXAMPLE
        Update-PfbArray -Attributes @{ time_zone = "America/New_York" } -WhatIf

        Shows what would happen without actually updating the array.
    .NOTES
        <!-- PfbContext (generated; do not edit) -->
        Context requirement (PATCH /arrays): the context scope for this endpoint is not
        recorded in the capability map, so the module will not pre-validate a context
        for it. A fleet or array context may still be required by the array itself; if
        a call fails with a context error, set one with Set-PfbContext or scope the
        call with Invoke-PfbInContext.
        <!-- /PfbContext -->
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )
    Assert-PfbConnection -Array ([ref]$Array)
    if ($PSCmdlet.ShouldProcess('FlashBlade', 'Update array settings')) {
        Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'arrays' -Body $Attributes
    }
}
