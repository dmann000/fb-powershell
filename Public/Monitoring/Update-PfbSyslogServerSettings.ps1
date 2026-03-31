function Update-PfbSyslogServerSettings {
    <#
    .SYNOPSIS
        Updates syslog server settings on a FlashBlade array.
    .DESCRIPTION
        The Update-PfbSyslogServerSettings cmdlet modifies the global syslog server settings
        on the connected Pure Storage FlashBlade.
    .PARAMETER Attributes
        A hashtable of syslog server settings to modify.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbSyslogServerSettings -Attributes @{ ca_certificate = "-----BEGIN CERTIFICATE-----..." }

        Updates the CA certificate for syslog TLS connections.
    .EXAMPLE
        Update-PfbSyslogServerSettings -Attributes @{} -WhatIf

        Shows what would happen without actually updating the settings.
    .EXAMPLE
        Update-PfbSyslogServerSettings -Attributes @{ ca_certificate = $null }

        Clears the CA certificate from the syslog settings.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )
    Assert-PfbConnection -Array ([ref]$Array)
    if ($PSCmdlet.ShouldProcess('FlashBlade', 'Update syslog server settings')) {
        Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'syslog-servers/settings' -Body $Attributes
    }
}
