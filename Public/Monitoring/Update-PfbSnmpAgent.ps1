function Update-PfbSnmpAgent {
    <#
    .SYNOPSIS
        Updates the SNMP agent configuration on a Pure Storage FlashBlade.
    .DESCRIPTION
        The Update-PfbSnmpAgent cmdlet modifies the SNMP agent settings on the FlashBlade.
        The Attributes hashtable must contain the configuration properties to update, such as
        community strings, SNMPv3 user credentials, or engine ID.
        This cmdlet supports the ShouldProcess pattern for -WhatIf and -Confirm.
    .PARAMETER Attributes
        A hashtable containing the SNMP agent attributes to update. Supported keys include
        'community', 'version', 'v3' (with nested auth and privacy settings), and 'engine_id'.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbSnmpAgent -Attributes @{ community = 'monitoring-ro' }

        Updates the SNMP community string to 'monitoring-ro'.
    .EXAMPLE
        $v3Config = @{ version = 'v3'; v3 = @{ auth_protocol = 'SHA'; auth_passphrase = 'AuthPass123'; privacy_protocol = 'AES'; privacy_passphrase = 'PrivPass456' } }
        Update-PfbSnmpAgent -Attributes $v3Config

        Configures the SNMP agent to use SNMPv3 with SHA authentication and AES privacy.
    .EXAMPLE
        Update-PfbSnmpAgent -Attributes @{ community = 'public' } -WhatIf

        Shows what would happen when updating the SNMP agent without applying the change.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )
    Assert-PfbConnection -Array ([ref]$Array)
    if ($PSCmdlet.ShouldProcess('SNMP Agent', 'Update SNMP agent')) {
        Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'snmp-agents' -Body $Attributes
    }
}
