function Get-PfbSyslogServer {
    <#
    .SYNOPSIS
        Retrieves syslog server configurations from a FlashBlade array.
    .DESCRIPTION
        The Get-PfbSyslogServer cmdlet returns one or more syslog server configurations
        from the connected Pure Storage FlashBlade. Results can be filtered by name, ID,
        or a server-side filter expression. Supports pipeline input for batch lookups.
    .PARAMETER Name
        One or more syslog server names to retrieve. Accepts pipeline input.
    .PARAMETER Id
        One or more syslog server IDs to retrieve.
    .PARAMETER Filter
        A server-side filter expression to narrow results (e.g., "name='syslog1'").
    .PARAMETER Sort
        Sort field and direction (e.g., "name" or "name-").
    .PARAMETER Limit
        Maximum number of syslog server entries to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbSyslogServer

        Retrieves all syslog server configurations from the connected FlashBlade.
    .EXAMPLE
        Get-PfbSyslogServer -Name "syslog-prod"

        Retrieves the syslog server configuration named "syslog-prod".
    .EXAMPLE
        Get-PfbSyslogServer -Filter "enabled='true'" -Sort "name" -Limit 10

        Retrieves up to 10 enabled syslog servers sorted by name.
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
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'syslog-servers' -QueryParams $queryParams -AutoPaginate
    }
}
