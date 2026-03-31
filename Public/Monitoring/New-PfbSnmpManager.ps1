function New-PfbSnmpManager {
    <#
    .SYNOPSIS
        Creates a new SNMP manager (trap host) on a Pure Storage FlashBlade.
    .DESCRIPTION
        The New-PfbSnmpManager cmdlet creates an SNMP manager entry on the FlashBlade that
        will receive SNMP traps and notifications. The Attributes hashtable must contain the
        manager configuration including the host address, SNMP version, and community string
        or SNMPv3 credentials. This cmdlet supports the ShouldProcess pattern for -WhatIf and -Confirm.
    .PARAMETER Name
        The name to assign to the SNMP manager entry.
    .PARAMETER Attributes
        A hashtable containing the SNMP manager configuration. Supported keys include 'host',
        'version', 'community', 'notification', and 'v3' (with nested auth and privacy settings).
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbSnmpManager -Name 'snmp-mgr01' -Attributes @{ host = '10.21.100.50'; version = 'v2c'; community = 'private' }

        Creates an SNMPv2c manager that sends traps to host 10.21.100.50.
    .EXAMPLE
        $v3Attrs = @{ host = '10.21.100.51'; version = 'v3'; v3 = @{ auth_protocol = 'SHA'; auth_passphrase = 'AuthPass'; privacy_protocol = 'AES'; privacy_passphrase = 'PrivPass'; user = 'snmpuser' } }
        New-PfbSnmpManager -Name 'snmp-mgr-v3' -Attributes $v3Attrs

        Creates an SNMPv3 manager with SHA authentication and AES privacy.
    .EXAMPLE
        New-PfbSnmpManager -Name 'snmp-mgr02' -Attributes @{ host = 'monitor.example.com'; version = 'v2c'; community = 'alerts' } -WhatIf

        Shows what would happen when creating the SNMP manager without actually creating it.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)] [string]$Name,
        [Parameter(Mandatory)] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )
    Assert-PfbConnection -Array ([ref]$Array)
    $q = @{ 'names' = $Name }
    if ($PSCmdlet.ShouldProcess($Name, 'Create SNMP manager')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'snmp-managers' -Body $Attributes -QueryParams $q
    }
}
