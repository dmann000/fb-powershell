function Get-PfbSnmpManager {
    <#
    .SYNOPSIS
        Retrieves SNMP manager (trap host) configurations from a Pure Storage FlashBlade.
    .DESCRIPTION
        The Get-PfbSnmpManager cmdlet returns SNMP manager entries configured on the FlashBlade.
        SNMP managers are remote hosts that receive SNMP traps and notifications from the array.
        Managers can be retrieved by name, by ID, or all at once. Supports filtering, sorting,
        pagination, and pipeline input.
    .PARAMETER Name
        One or more SNMP manager names to retrieve. Accepts pipeline input.
    .PARAMETER Id
        One or more SNMP manager IDs to retrieve.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        The field and direction to sort results by (e.g., 'name' or 'name-').
    .PARAMETER Limit
        The maximum number of items to return per page.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbSnmpManager

        Returns all SNMP managers configured on the connected FlashBlade.
    .EXAMPLE
        Get-PfbSnmpManager -Name 'snmp-mgr01'

        Retrieves the SNMP manager named 'snmp-mgr01'.
    .EXAMPLE
        'snmp-mgr01', 'snmp-mgr02' | Get-PfbSnmpManager

        Retrieves multiple SNMP managers by piping their names to the cmdlet.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(ParameterSetName = 'ByName', ValueFromPipeline, ValueFromPipelineByPropertyName)] [string[]]$Name,
        [Parameter(ParameterSetName = 'ById')] [string[]]$Id,
        [Parameter()] [string]$Filter, [Parameter()] [string]$Sort, [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )
    begin {
        Assert-PfbConnection -Array ([ref]$Array)
        $allNames = [System.Collections.Generic.List[string]]::new()
        $allIds = [System.Collections.Generic.List[string]]::new()
    }

    process {
        if ($Name) { foreach ($n in $Name) { $allNames.Add($n) } }
        if ($Id) { foreach ($i in $Id) { $allIds.Add($i) } }
    }

    end {
        $queryParams = @{}
        if ($allNames.Count -gt 0) { $queryParams['names'] = $allNames -join ',' }
        if ($allIds.Count -gt 0) { $queryParams['ids'] = $allIds -join ',' }
        if ($Filter) { $queryParams['filter'] = $Filter }
        if ($Sort) { $queryParams['sort'] = $Sort }
        if ($Limit -gt 0) { $queryParams['limit'] = $Limit }
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'snmp-managers' -QueryParams $queryParams -AutoPaginate
    }
}
