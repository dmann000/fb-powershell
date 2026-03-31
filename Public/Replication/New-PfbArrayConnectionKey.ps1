function New-PfbArrayConnectionKey {
    <#
    .SYNOPSIS
        Creates a new array connection key on a FlashBlade array.
    .DESCRIPTION
        The New-PfbArrayConnectionKey cmdlet generates a new array connection key on the
        connected Pure Storage FlashBlade. Connection keys authenticate replication connections.
    .PARAMETER Attributes
        A hashtable of connection key attributes to configure.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbArrayConnectionKey -Attributes @{}

        Generates a new array connection key with default settings.
    .EXAMPLE
        New-PfbArrayConnectionKey -Attributes @{} -WhatIf

        Shows what would happen without actually creating the key.
    .EXAMPLE
        $key = New-PfbArrayConnectionKey -Attributes @{}; $key.connection_key

        Creates a key and displays the connection key value.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )
    Assert-PfbConnection -Array ([ref]$Array)
    if ($PSCmdlet.ShouldProcess('FlashBlade', 'Create array connection key')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'array-connections/connection-key' -Body $Attributes
    }
}
