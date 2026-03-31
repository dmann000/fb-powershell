function Get-PfbSnmpAgent {
    <#
    .SYNOPSIS
        Retrieves SNMP agent configuration from a Pure Storage FlashBlade.
    .DESCRIPTION
        The Get-PfbSnmpAgent cmdlet returns the SNMP agent configuration on the FlashBlade.
        The SNMP agent defines the local SNMP settings such as community strings and SNMPv3
        engine ID. Results can be narrowed using a server-side filter expression.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbSnmpAgent

        Returns the SNMP agent configuration for the connected FlashBlade.
    .EXAMPLE
        Get-PfbSnmpAgent -Array $FlashBlade

        Returns the SNMP agent configuration using a specific FlashBlade connection object.
    .EXAMPLE
        Get-PfbSnmpAgent -Filter "version='v3'"

        Returns SNMP agent configuration filtered to SNMPv3 entries.
    #>
    [CmdletBinding()]
    param(
        [Parameter()] [string]$Filter,
        [Parameter()] [PSCustomObject]$Array
    )
    Assert-PfbConnection -Array ([ref]$Array)
    $queryParams = @{}
    if ($Filter) { $queryParams['filter'] = $Filter }
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'snmp-agents' -QueryParams $queryParams -AutoPaginate
}
