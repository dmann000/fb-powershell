function Get-PfbSnmpAgentMib {
    <#
    .SYNOPSIS
        Retrieves the SNMP agent MIB from a FlashBlade array.
    .DESCRIPTION
        The Get-PfbSnmpAgentMib cmdlet returns the SNMP agent MIB data from the connected
        Pure Storage FlashBlade. This is a singleton endpoint.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbSnmpAgentMib

        Returns the SNMP agent MIB for the connected FlashBlade.
    .EXAMPLE
        Get-PfbSnmpAgentMib -Array $FlashBlade

        Returns the SNMP MIB using a specific FlashBlade connection.
    .EXAMPLE
        $mib = Get-PfbSnmpAgentMib; $mib | Out-File -FilePath "flashblade.mib"

        Downloads the SNMP MIB and saves it to a file.
    #>
    [CmdletBinding()]
    param([Parameter()] [PSCustomObject]$Array)
    Assert-PfbConnection -Array ([ref]$Array)
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'snmp-agents/mib'
}
