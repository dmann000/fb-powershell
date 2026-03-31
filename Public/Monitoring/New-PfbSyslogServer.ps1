function New-PfbSyslogServer {
    <#
    .SYNOPSIS
        Creates a new syslog server configuration on a FlashBlade array.
    .DESCRIPTION
        The New-PfbSyslogServer cmdlet creates a new syslog server entry on the connected
        Pure Storage FlashBlade. The server attributes such as URI and transport protocol
        are specified through the Attributes hashtable. Supports ShouldProcess for
        confirmation prompts when used with -WhatIf or -Confirm.
    .PARAMETER Name
        The name for the new syslog server configuration.
    .PARAMETER Attributes
        A hashtable of syslog server attributes including URI, transport protocol, and other
        configuration options (e.g., @{ uri = "tcp://syslog.example.com:514" }).
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbSyslogServer -Name "syslog-prod" -Attributes @{ uri = "tcp://syslog.example.com:514" }

        Creates a syslog server named "syslog-prod" sending logs via TCP.
    .EXAMPLE
        New-PfbSyslogServer -Name "syslog-sec" -Attributes @{ uri = "udp://10.0.1.50:514" }

        Creates a syslog server named "syslog-sec" using UDP transport.
    .EXAMPLE
        New-PfbSyslogServer -Name "syslog-tls" -Attributes @{ uri = "tls://syslog.corp.com:6514"; ca_certificate = $cert } -WhatIf

        Shows what would happen if the syslog server were created without actually creating it.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)] [string]$Name,
        [Parameter(Mandatory)] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )
    Assert-PfbConnection -Array ([ref]$Array)
    $q = @{ 'names' = $Name }
    if ($PSCmdlet.ShouldProcess($Name, 'Create syslog server')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'syslog-servers' -Body $Attributes -QueryParams $q
    }
}
