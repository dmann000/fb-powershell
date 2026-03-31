function Update-PfbSnmpManager {
    <#
    .SYNOPSIS
        Updates an existing SNMP manager (trap host) on a Pure Storage FlashBlade.
    .DESCRIPTION
        The Update-PfbSnmpManager cmdlet modifies an existing SNMP manager entry on the FlashBlade.
        The manager can be identified by name or by ID. The Attributes hashtable contains the
        configuration properties to update such as the host address, community string, or SNMPv3
        credentials. This cmdlet supports pipeline input by property name and the ShouldProcess pattern.
    .PARAMETER Name
        The name of the SNMP manager to update. Accepts pipeline input by property name.
    .PARAMETER Id
        The ID of the SNMP manager to update.
    .PARAMETER Attributes
        A hashtable containing the SNMP manager attributes to update.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbSnmpManager -Name 'snmp-mgr01' -Attributes @{ host = '10.21.100.55' }

        Updates the host address for the SNMP manager named 'snmp-mgr01'.
    .EXAMPLE
        Update-PfbSnmpManager -Name 'snmp-mgr01' -Attributes @{ community = 'new-community' }

        Changes the community string for the specified SNMP manager.
    .EXAMPLE
        Get-PfbSnmpManager -Name 'snmp-mgr01' | Update-PfbSnmpManager -Attributes @{ version = 'v2c'; community = 'updated' }

        Pipes an SNMP manager object to update its version and community string.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, ValueFromPipelineByPropertyName)] [string]$Name,
        [Parameter(ParameterSetName = 'ById', Mandatory)] [string]$Id,
        [Parameter(Mandatory)] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )
    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $queryParams = @{}
        if ($Name) { $queryParams['names'] = $Name }
        if ($Id) { $queryParams['ids'] = $Id }
        $target = if ($Name) { $Name } else { $Id }
        if ($PSCmdlet.ShouldProcess($target, 'Update SNMP manager')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'snmp-managers' -Body $Attributes -QueryParams $queryParams
        }
    }
}
